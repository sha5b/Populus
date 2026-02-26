extends System
class_name SysAtmosphereFluid

var atmo_grid: AtmosphereGrid = null
var wind_system: SysWind = null
var weather_system: SysWeather = null

var _sim_accumulator: float = 0.0
const SIM_INTERVAL := GameConfig.ATMOS_SIM_INTERVAL

var _adv_moisture: PackedFloat32Array
var _adv_temp: PackedFloat32Array
var _lat_cache: PackedFloat32Array
var _old_density: PackedFloat32Array
var _initialized: bool = false

const ADVECTION_RATE := GameConfig.ATMOS_ADVECTION_RATE
const PRESSURE_SMOOTH := GameConfig.ATMOS_PRESSURE_SMOOTH
const BUOYANCY_FACTOR := GameConfig.ATMOS_BUOYANCY_FACTOR
const CORIOLIS_FACTOR := GameConfig.ATMOS_CORIOLIS_FACTOR
const CONDENSATION_RATE := GameConfig.ATMOS_CONDENSATION_RATE
const EVAPORATION_RATE := GameConfig.ATMOS_EVAPORATION_RATE
const PRECIP_THRESHOLD := GameConfig.ATMOS_PRECIP_THRESHOLD
const PRECIP_DRAIN := GameConfig.ATMOS_PRECIP_DRAIN
const LATENT_HEAT := GameConfig.ATMOS_LATENT_HEAT
const WIND_DAMPING := GameConfig.ATMOS_WIND_DAMPING

const MOISTURE_INJECT := GameConfig.ATMOS_MOISTURE_INJECT

var _is_simulating: bool = false
var _thread_task_id: int = -1

func update(_world: Node, delta: float) -> void:
	if atmo_grid == null:
		return

	if _is_simulating:
		if _thread_task_id != -1 and WorkerThreadPool.is_task_completed(_thread_task_id):
			WorkerThreadPool.wait_for_task_completion(_thread_task_id)
			_thread_task_id = -1
			_is_simulating = false
			_apply_sim_results()
		return

	_sim_accumulator += delta
	if _sim_accumulator < SIM_INTERVAL:
		return
	_sim_accumulator = 0.0

	if not _initialized:
		_init_buffers()

	for i in range(AtmosphereGrid.TOTAL_CELLS):
		_old_density[i] = atmo_grid.cloud_density[i]

	_is_simulating = true
	_thread_task_id = WorkerThreadPool.add_task(_run_sim_thread.bind(), true, "AtmosFluidSim")


func _run_sim_thread() -> void:
	_resample_surface_climate()
	_inject_surface_moisture()
	_apply_global_wind()
	_advection_step()
	_pressure_step()
	_buoyancy_step()
	_condensation_step()
	_precipitation_step()


func _apply_sim_results() -> void:
	for i in range(AtmosphereGrid.TOTAL_CELLS):
		atmo_grid.moisture[i] = _adv_moisture[i]
		atmo_grid.temperature[i] = _adv_temp[i]

	_damp_winds()

	_mark_changed_chunks()


func _resample_surface_climate() -> void:
	if weather_system == null or weather_system.grid == null:
		return
		
	var proj = atmo_grid._projector
	var gw = weather_system.grid.width
	var gh = weather_system.grid.height
	var temp_map = weather_system.temperature_map
	var moist_map = weather_system.moisture_map
	
	if temp_map.is_empty() or moist_map.is_empty():
		return
		
	for face in range(AtmosphereGrid.NUM_FACES):
		for fv in range(AtmosphereGrid.FACE_RES):
			for fu in range(AtmosphereGrid.FACE_RES):
				var u_norm := (float(fu) + 0.5) / float(AtmosphereGrid.FACE_RES)
				var v_norm := (float(fv) + 0.5) / float(AtmosphereGrid.FACE_RES)
				var world_pos := proj.cube_sphere_point(face, u_norm, v_norm)
				
				# Get grid coordinates for bilinear sampling
				var r := world_pos.length()
				var lat := asin(clampf(world_pos.y / maxf(r, 0.001), -1.0, 1.0))
				var lon := atan2(world_pos.z, world_pos.x)
				if lon < 0.0:
					lon += TAU
				var gx := (lon / TAU) * float(gw)
				var gy := ((lat + PI * 0.5) / PI) * float(gh)

				var x0: int = int(floor(gx)) % gw
				var y0: int = clampi(int(floor(gy)), 0, gh - 1)
				var x1: int = (x0 + 1) % gw
				var y1: int = clampi(y0 + 1, 0, gh - 1)
				var fx: float = gx - float(floor(gx))
				var fy: float = gy - float(floor(gy))

				var v00: float = moist_map[y0 * gw + x0]
				var v10: float = moist_map[y0 * gw + x1]
				var v01: float = moist_map[y1 * gw + x0]
				var v11: float = moist_map[y1 * gw + x1]
				var base_m := lerpf(lerpf(v00, v10, fx), lerpf(v01, v11, fx), fy)
				
				var t00: float = temp_map[y0 * gw + x0]
				var t10: float = temp_map[y0 * gw + x1]
				var t01: float = temp_map[y1 * gw + x0]
				var t11: float = temp_map[y1 * gw + x1]
				var sim_t := lerpf(lerpf(t00, t10, fx), lerpf(t01, t11, fx), fy)
				
				# Temperature from simulation is 0-1, map to Celsius (-10 to 30)
				var celsius_t := sim_t * 40.0 - 10.0
				
				var i := atmo_grid.idx(face, fu, fv, 0)
				
				# Slowly blend toward target to avoid shocking the fluid sim
				atmo_grid.temperature[i] = lerpf(atmo_grid.temperature[i], celsius_t, 0.05)
				atmo_grid.moisture[i] = lerpf(atmo_grid.moisture[i], base_m, 0.02)


func _init_buffers() -> void:
	var tc := AtmosphereGrid.TOTAL_CELLS
	_adv_moisture = PackedFloat32Array()
	_adv_moisture.resize(tc)
	_adv_temp = PackedFloat32Array()
	_adv_temp.resize(tc)
	_old_density = PackedFloat32Array()
	_old_density.resize(tc)

	_lat_cache = PackedFloat32Array()
	var face_cells := AtmosphereGrid.FACE_RES * AtmosphereGrid.FACE_RES
	_lat_cache.resize(AtmosphereGrid.NUM_FACES * face_cells)
	for face in range(AtmosphereGrid.NUM_FACES):
		for fv in range(AtmosphereGrid.FACE_RES):
			for fu in range(AtmosphereGrid.FACE_RES):
				var ci := face * face_cells + fv * AtmosphereGrid.FACE_RES + fu
				_lat_cache[ci] = atmo_grid.get_latitude_fraction(face, fu, fv)
	_initialized = true


func _mark_changed_chunks() -> void:
	var cpf := AtmosphereGrid.CHUNKS_PER_FACE
	var cs := AtmosphereGrid.CHUNK_SIZE
	var threshold := GameConfig.ATMOS_DIRTY_THRESHOLD

	for face in range(AtmosphereGrid.NUM_FACES):
		for cv in range(cpf):
			for cu in range(cpf):
				var chunk_changed := false
				var fu_start := cu * cs
				var fv_start := cv * cs
				for fv in range(fv_start, fv_start + cs):
					for fu in range(fu_start, fu_start + cs):
						for alt in range(AtmosphereGrid.ALT_RES):
							var i := atmo_grid.idx(face, fu, fv, alt)
							if absf(atmo_grid.cloud_density[i] - _old_density[i]) > threshold:
								chunk_changed = true
								break
						if chunk_changed:
							break
					if chunk_changed:
						break
				if chunk_changed:
					atmo_grid.mark_chunk_dirty_by_idx(atmo_grid.chunk_idx(face, cu, cv))


func _inject_surface_moisture() -> void:
	var state := 0
	if weather_system:
		state = weather_system.current_state
	var base_inject: float = MOISTURE_INJECT.get(state, 0.01)

	for face in range(AtmosphereGrid.NUM_FACES):
		for fv in range(AtmosphereGrid.FACE_RES):
			for fu in range(AtmosphereGrid.FACE_RES):
				var i := atmo_grid.idx(face, fu, fv, 0)
				var surface_temp := atmo_grid.temperature[i]
				var surface_moist := atmo_grid.moisture[i]

				var temp_factor := clampf((surface_temp + 10.0) / 40.0, 0.0, 1.0)
				var dry_evap := clampf(1.0 - surface_moist * 0.5, 0.3, 1.0)
				var inject := base_inject * temp_factor * dry_evap

				atmo_grid.moisture[i] += inject
				atmo_grid.moisture[i] = minf(atmo_grid.moisture[i], 1.0)


func _apply_global_wind() -> void:
	if wind_system == null:
		return

	var fc := AtmosphereGrid.FACE_RES * AtmosphereGrid.FACE_RES
	for face in range(AtmosphereGrid.NUM_FACES):
		for fv in range(AtmosphereGrid.FACE_RES):
			for fu in range(AtmosphereGrid.FACE_RES):
				var lat_frac := _lat_cache[face * fc + fv * AtmosphereGrid.FACE_RES + fu]
				var band_wind := wind_system.get_wind_at_latitude(lat_frac)

				for alt in range(AtmosphereGrid.ALT_RES):
					var i := atmo_grid.idx(face, fu, fv, alt)
					var alt_factor := 1.0 + float(alt) * 0.15
					atmo_grid.wind_u[i] += band_wind.x * 0.05 * alt_factor
					atmo_grid.wind_v[i] += band_wind.y * 0.05


func _advection_step() -> void:
	for face in range(AtmosphereGrid.NUM_FACES):
		for fv in range(AtmosphereGrid.FACE_RES):
			for fu in range(AtmosphereGrid.FACE_RES):
				for alt in range(AtmosphereGrid.ALT_RES):
					var i := atmo_grid.idx(face, fu, fv, alt)
					var u := atmo_grid.wind_u[i]
					var v := atmo_grid.wind_v[i]
					var w := atmo_grid.wind_w[i]

					var src_fu := float(fu) - u * ADVECTION_RATE
					var src_fv := float(fv) - v * ADVECTION_RATE
					var src_alt := float(alt) - w * ADVECTION_RATE

					_adv_moisture[i] = _sample_trilinear(atmo_grid.moisture, face, src_fu, src_fv, src_alt)
					_adv_temp[i] = _sample_trilinear(atmo_grid.temperature, face, src_fu, src_fv, src_alt)

	for i in range(AtmosphereGrid.TOTAL_CELLS):
		atmo_grid.moisture[i] = _adv_moisture[i]
		atmo_grid.temperature[i] = _adv_temp[i]


func _sample_trilinear(field: PackedFloat32Array, face: int, fu: float, fv: float, alt: float) -> float:
	var fu0 := int(floor(fu))
	var fv0 := int(floor(fv))
	var alt0 := int(floor(alt))

	var ff: float = fu - float(fu0)
	var fvf: float = fv - float(fv0)
	var fa: float = alt - float(alt0)

	var c000 := field[atmo_grid.idx(face, fu0, fv0, alt0)]
	var c100 := field[atmo_grid.idx(face, fu0 + 1, fv0, alt0)]
	var c010 := field[atmo_grid.idx(face, fu0, fv0 + 1, alt0)]
	var c110 := field[atmo_grid.idx(face, fu0 + 1, fv0 + 1, alt0)]
	var c001 := field[atmo_grid.idx(face, fu0, fv0, alt0 + 1)]
	var c101 := field[atmo_grid.idx(face, fu0 + 1, fv0, alt0 + 1)]
	var c011 := field[atmo_grid.idx(face, fu0, fv0 + 1, alt0 + 1)]
	var c111 := field[atmo_grid.idx(face, fu0 + 1, fv0 + 1, alt0 + 1)]

	var c00 := lerpf(c000, c100, ff)
	var c10 := lerpf(c010, c110, ff)
	var c01 := lerpf(c001, c101, ff)
	var c11 := lerpf(c011, c111, ff)

	var c0 := lerpf(c00, c10, fvf)
	var c1 := lerpf(c01, c11, fvf)

	return lerpf(c0, c1, fa)


func _pressure_step() -> void:
	var fc := AtmosphereGrid.FACE_RES * AtmosphereGrid.FACE_RES
	var fr := AtmosphereGrid.FACE_RES
	for face in range(AtmosphereGrid.NUM_FACES):
		for fv in range(fr):
			for fu in range(fr):
				var lat_frac := _lat_cache[face * fc + fv * fr + fu]
				var lat_norm := (lat_frac - 0.5) * 2.0
				var coriolis := lat_norm * CORIOLIS_FACTOR

				for alt in range(AtmosphereGrid.ALT_RES):
					var i := atmo_grid.idx(face, fu, fv, alt)
					atmo_grid.pressure[i] = AtmosphereGrid.BASE_PRESSURE * (1.0 + atmo_grid.temperature[i] * 0.003)

					var pl := atmo_grid.pressure[atmo_grid.idx(face, fu - 1, fv, alt)]
					var pr := atmo_grid.pressure[atmo_grid.idx(face, fu + 1, fv, alt)]
					var pd := atmo_grid.pressure[atmo_grid.idx(face, fu, fv - 1, alt)]
					var pu := atmo_grid.pressure[atmo_grid.idx(face, fu, fv + 1, alt)]

					atmo_grid.wind_u[i] += (pl - pr) * PRESSURE_SMOOTH
					atmo_grid.wind_v[i] += (pd - pu) * PRESSURE_SMOOTH

					var old_u := atmo_grid.wind_u[i]
					atmo_grid.wind_u[i] += atmo_grid.wind_v[i] * coriolis
					atmo_grid.wind_v[i] -= old_u * coriolis


func _buoyancy_step() -> void:
	for face in range(AtmosphereGrid.NUM_FACES):
		for fv in range(AtmosphereGrid.FACE_RES):
			for fu in range(AtmosphereGrid.FACE_RES):
				for alt in range(AtmosphereGrid.ALT_RES - 1):
					var i := atmo_grid.idx(face, fu, fv, alt)
					var i_above := atmo_grid.idx(face, fu, fv, alt + 1)

					var temp_diff := atmo_grid.temperature[i] - atmo_grid.temperature[i_above]
					var moist_boost := atmo_grid.moisture[i] * 0.5
					atmo_grid.wind_w[i] += (temp_diff + moist_boost) * BUOYANCY_FACTOR
					atmo_grid.wind_w[i] = clampf(atmo_grid.wind_w[i], -2.0, 2.0)


func _condensation_step() -> void:
	for i in range(AtmosphereGrid.TOTAL_CELLS):
		var temp := atmo_grid.temperature[i]
		var moist := atmo_grid.moisture[i]
		var sat := atmo_grid.saturation_humidity(temp)

		if moist > sat:
			var excess := (moist - sat) * CONDENSATION_RATE
			atmo_grid.cloud_density[i] += excess
			atmo_grid.moisture[i] -= excess
			atmo_grid.temperature[i] += excess * LATENT_HEAT
		else:
			var deficit := (sat - moist) * EVAPORATION_RATE
			var evap := minf(deficit, atmo_grid.cloud_density[i])
			atmo_grid.cloud_density[i] -= evap
			atmo_grid.moisture[i] += evap

		atmo_grid.cloud_density[i] = clampf(atmo_grid.cloud_density[i], 0.0, 1.0)
		atmo_grid.moisture[i] = clampf(atmo_grid.moisture[i], 0.0, 1.0)


func _precipitation_step() -> void:
	for face in range(AtmosphereGrid.NUM_FACES):
		for fv in range(AtmosphereGrid.FACE_RES):
			for fu in range(AtmosphereGrid.FACE_RES):
				for alt in range(AtmosphereGrid.ALT_RES):
					var i := atmo_grid.idx(face, fu, fv, alt)
					if atmo_grid.cloud_density[i] > PRECIP_THRESHOLD:
						var drain := (atmo_grid.cloud_density[i] - PRECIP_THRESHOLD) * PRECIP_DRAIN
						atmo_grid.cloud_density[i] -= drain
						if alt > 0:
							var below := atmo_grid.idx(face, fu, fv, alt - 1)
							atmo_grid.moisture[below] += drain * 0.5


func _damp_winds() -> void:
	for i in range(AtmosphereGrid.TOTAL_CELLS):
		atmo_grid.wind_u[i] *= WIND_DAMPING
		atmo_grid.wind_v[i] *= WIND_DAMPING
		atmo_grid.wind_w[i] *= WIND_DAMPING

extends System
class_name SysAtmosphereFluid

var atmo_grid: AtmosphereGrid = null
var wind_system: SysWind = null
var weather_system: SysWeather = null

var _sim_accumulator: float = 0.0
const SIM_INTERVAL := 3.0

var _adv_moisture: PackedFloat32Array
var _adv_temp: PackedFloat32Array
var _lat_cache: PackedFloat32Array
var _old_density: PackedFloat32Array
var _initialized: bool = false

const ADVECTION_RATE := 0.15
const PRESSURE_SMOOTH := 0.05
const BUOYANCY_FACTOR := 0.02
const CORIOLIS_FACTOR := 0.01
const CONDENSATION_RATE := 0.1
const EVAPORATION_RATE := 0.12
const PRECIP_THRESHOLD := 0.5
const PRECIP_DRAIN := 0.06
const LATENT_HEAT := 2.0
const WIND_DAMPING := 0.98

const MOISTURE_INJECT := {
	0: 0.002,   # CLEAR
	1: 0.008,   # CLOUDY
	2: 0.02,    # RAIN
	3: 0.04,    # STORM
	4: 0.005,   # SNOW
	5: 0.01,    # FOG
}


func update(_world: Node, delta: float) -> void:
	if atmo_grid == null:
		return

	_sim_accumulator += delta
	if _sim_accumulator < SIM_INTERVAL:
		return
	_sim_accumulator = 0.0

	if not _initialized:
		_init_buffers()

	_old_density.resize(AtmosphereGrid.TOTAL_CELLS)
	for i in range(AtmosphereGrid.TOTAL_CELLS):
		_old_density[i] = atmo_grid.cloud_density[i]

	_inject_surface_moisture()
	_apply_global_wind()
	_advection_step()
	_pressure_step()
	_buoyancy_step()
	_condensation_step()
	_precipitation_step()
	_damp_winds()

	_mark_changed_chunks()


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
	var threshold := 0.02

	for face in range(AtmosphereGrid.NUM_FACES):
		for cv in range(cpf):
			for cu in range(cpf):
				var changed := false
				var fu_start := cu * cs
				var fv_start := cv * cs
				for fv in range(fv_start, fv_start + cs):
					for fu in range(fu_start, fu_start + cs):
						for alt in range(AtmosphereGrid.ALT_RES):
							var i := atmo_grid.idx(face, fu, fv, alt)
							if absf(atmo_grid.cloud_density[i] - _old_density[i]) > threshold:
								changed = true
								break
						if changed:
							break
					if changed:
						break
				if changed:
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

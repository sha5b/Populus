extends System
class_name SysWaterDynamics

var grid: TorusGrid = null
var water: WaterGrid = null
var weather_system: SysWeather = null
var wind_system: SysWind = null
var temperature_map: PackedFloat32Array
var moisture_map: PackedFloat32Array
var river_system: SysRiverFormation = null

var _timer: float = 0.0
var _chunk_offset: int = 0
var _ocean_current_timer: float = 0.0

const TICK_INTERVAL := 0.5
const CHUNK_SIZE := 2048
const OCEAN_CURRENT_INTERVAL := 3.0

const GRAVITY := 0.08
const FLOW_DAMPING := 0.92
const MIN_DEPTH := 0.001
const RAIN_RATE := 0.0003
const STORM_RAIN_RATE := 0.001
const EVAPORATION_BASE := 0.00005
const EVAPORATION_HEAT_FACTOR := 0.0001
const WAVE_DECAY := 0.85
const STORM_WAVE_BOOST := 0.003
const WIND_CURRENT_STRENGTH := 0.005
const THERMAL_CURRENT_STRENGTH := 0.003
const CORIOLIS_FACTOR := 0.01
const RIVER_INJECT_RATE := 0.002


func setup(
	g: TorusGrid,
	wg: WaterGrid,
	ws: SysWeather,
	wi: SysWind,
	temp: PackedFloat32Array,
	moist: PackedFloat32Array,
	rs: SysRiverFormation
) -> void:
	grid = g
	water = wg
	weather_system = ws
	wind_system = wi
	temperature_map = temp
	moisture_map = moist
	river_system = rs


func update(_world: Node, delta: float) -> void:
	if water == null or grid == null:
		return

	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer -= TICK_INTERVAL

	_process_chunk()

	_ocean_current_timer += TICK_INTERVAL
	if _ocean_current_timer >= OCEAN_CURRENT_INTERVAL:
		_ocean_current_timer = 0.0
		_update_ocean_currents()


func _process_chunk() -> void:
	var total := water.width * water.height
	var end_idx := mini(_chunk_offset + CHUNK_SIZE, total)

	var is_raining := false
	var is_storm := false
	if weather_system:
		is_raining = weather_system.current_state == DefEnums.WeatherState.RAIN or weather_system.current_state == DefEnums.WeatherState.STORM
		is_storm = weather_system.current_state == DefEnums.WeatherState.STORM

	var wind_dir := Vector2.ZERO
	var wind_speed := 0.0
	if wind_system:
		wind_dir = wind_system.direction
		wind_speed = wind_system.speed

	for i in range(_chunk_offset, end_idx):
		var x := i % water.width
		var y := i / water.width
		_simulate_tile(x, y, i, is_raining, is_storm, wind_dir, wind_speed)

	_chunk_offset = end_idx if end_idx < total else 0


func _simulate_tile(x: int, y: int, idx: int, is_raining: bool, is_storm: bool, wind_dir: Vector2, wind_speed: float) -> void:
	var depth := water.water_depth[idx]
	var terrain_h := grid.get_height(x, y)
	var surface_h := terrain_h + depth

	# --- Weather: rain adds water, evaporation removes ---
	if is_raining:
		var rate := STORM_RAIN_RATE if is_storm else RAIN_RATE
		depth += rate
	var temp := water.water_temp[idx]
	var evap := EVAPORATION_BASE + temp * EVAPORATION_HEAT_FACTOR
	depth = maxf(depth - evap, 0.0)

	# --- River injection: rivers continuously feed water ---
	if river_system and river_system.river_map.size() > idx:
		var river_strength := river_system.river_map[idx]
		if river_strength > 0.0:
			depth += RIVER_INJECT_RATE * river_strength

	# --- Shallow water flow: water flows downhill ---
	if depth > MIN_DEPTH:
		var flow_x := water.flow_vx[idx]
		var flow_y := water.flow_vy[idx]

		# Gravity-driven flow from height gradient
		var h_l := grid.get_height(grid.wrap_x(x - 1), y) + water.water_depth[water.get_index(x - 1, y)]
		var h_r := grid.get_height(grid.wrap_x(x + 1), y) + water.water_depth[water.get_index(x + 1, y)]
		var h_u := grid.get_height(x, grid.wrap_y(y - 1)) + water.water_depth[water.get_index(x, y - 1)]
		var h_d := grid.get_height(x, grid.wrap_y(y + 1)) + water.water_depth[water.get_index(x, y + 1)]

		var grad_x := (h_l - h_r) * 0.5
		var grad_y := (h_u - h_d) * 0.5

		flow_x += grad_x * GRAVITY
		flow_y += grad_y * GRAVITY

		# Wind-driven surface current (only deep water)
		if depth > 0.05:
			flow_x += wind_dir.x * wind_speed * WIND_CURRENT_STRENGTH
			flow_y += wind_dir.y * wind_speed * WIND_CURRENT_STRENGTH

		# Coriolis deflection (latitude-dependent)
		var lat_factor := (float(y) / float(water.height) - 0.5) * 2.0
		var coriolis_x := -flow_y * CORIOLIS_FACTOR * lat_factor
		var coriolis_y := flow_x * CORIOLIS_FACTOR * lat_factor
		flow_x += coriolis_x
		flow_y += coriolis_y

		# Damping
		flow_x *= FLOW_DAMPING
		flow_y *= FLOW_DAMPING

		# Transfer water to neighbors
		var transfer := minf(depth * 0.25, 0.01)
		var flow_mag := sqrt(flow_x * flow_x + flow_y * flow_y)
		if flow_mag > 0.001 and transfer > 0.0:
			var fx := flow_x / flow_mag
			var fy := flow_y / flow_mag
			var tx := x + roundi(fx)
			var ty := y + roundi(fy)
			var ti := water.get_index(tx, ty)
			var target_terrain := grid.get_height(grid.wrap_x(tx), grid.wrap_y(ty))
			var target_surface := target_terrain + water.water_depth[ti]

			if surface_h > target_surface:
				var amount := minf(transfer * clampf(flow_mag, 0.1, 1.0), depth * 0.5)
				depth -= amount
				water.water_depth[ti] += amount

		water.flow_vx[idx] = flow_x
		water.flow_vy[idx] = flow_y

	# --- Waves ---
	var wave := water.wave_height[idx]
	if is_storm and depth > 0.05:
		wave += STORM_WAVE_BOOST * (0.5 + randf() * 0.5)
	wave *= WAVE_DECAY
	water.wave_height[idx] = wave

	# --- Commit ---
	water.water_depth[idx] = depth
	water.surface_height[idx] = terrain_h + depth


func _update_ocean_currents() -> void:
	var w := water.width
	var h := water.height

	# Temperature-driven thermohaline circulation
	# Warm equatorial water flows poleward, cold polar water sinks and flows equatorward
	var equator_y := h / 2
	var chunk_size := 512
	var offset := randi() % maxi(w * h, 1)

	for _i in range(chunk_size):
		var idx := (offset + _i) % (w * h)
		var x := idx % w
		var y := idx / w
		var depth := water.water_depth[idx]

		if depth < 0.05:
			continue

		var temp := water.water_temp[idx]
		var lat_dist := float(y - equator_y) / float(equator_y)

		# Warm water rises and flows poleward
		var thermal_vy := -signf(lat_dist) * temp * THERMAL_CURRENT_STRENGTH
		water.flow_vy[idx] += thermal_vy

		# Temperature diffusion with neighbors
		var temp_avg := 0.0
		var count := 0
		for n in grid.get_neighbors_4(x, y):
			var ni := water.get_index(n.x, n.y)
			if water.water_depth[ni] > MIN_DEPTH:
				temp_avg += water.water_temp[ni]
				count += 1
		if count > 0:
			temp_avg /= float(count)
			water.water_temp[idx] = lerpf(temp, temp_avg, 0.1)

		# Latitude-based temperature tendency
		var lat_temp := 1.0 - absf(lat_dist)
		water.water_temp[idx] = lerpf(water.water_temp[idx], lat_temp, 0.02)

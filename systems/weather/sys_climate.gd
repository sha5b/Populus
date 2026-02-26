extends System
class_name SysClimate

var grid: TorusGrid = null
var projector: PlanetProjector = null
var base_temperature_map: PackedFloat32Array
var base_moisture_map: PackedFloat32Array

var _chunk_offset: int = 0
var _timer: float = 0.0

const CHUNK_SIZE := 4096
const TICK_INTERVAL := 0.5

var _noise_t_lo: FastNoiseLite
var _noise_t_hi: FastNoiseLite
var _noise_m_lo: FastNoiseLite
var _noise_m_hi: FastNoiseLite
var _seed: int

var _distance_to_water: PackedFloat32Array
var _dist_update_timer: float = 0.0


func setup(g: TorusGrid, proj: PlanetProjector, base_temp: PackedFloat32Array, base_moist: PackedFloat32Array, world_seed: int) -> void:
	grid = g
	projector = proj
	base_temperature_map = base_temp
	base_moisture_map = base_moist
	_seed = world_seed
	
	_noise_t_lo = FastNoiseLite.new()
	_noise_t_lo.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_t_lo.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_t_lo.fractal_octaves = 3
	_noise_t_lo.frequency = 0.02
	_noise_t_lo.seed = _seed + 2000

	_noise_t_hi = FastNoiseLite.new()
	_noise_t_hi.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_t_hi.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_t_hi.fractal_octaves = 2
	_noise_t_hi.frequency = 0.06
	_noise_t_hi.seed = _seed + 2100

	_noise_m_lo = FastNoiseLite.new()
	_noise_m_lo.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_m_lo.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_m_lo.fractal_octaves = 4
	_noise_m_lo.frequency = 0.025
	_noise_m_lo.seed = _seed + 3000

	_noise_m_hi = FastNoiseLite.new()
	_noise_m_hi.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_m_hi.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_m_hi.fractal_octaves = 2
	_noise_m_hi.frequency = 0.07
	_noise_m_hi.seed = _seed + 3100
	
	_distance_to_water = PackedFloat32Array()
	_distance_to_water.resize(g.width * g.height)
	_update_water_distance()


func update(_world: Node, delta: float) -> void:
	if grid == null:
		return
		
	_dist_update_timer += delta
	if _dist_update_timer > 10.0:
		_dist_update_timer = 0.0
		_update_water_distance()
		
	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer -= TICK_INTERVAL
	
	_process_chunk()


func _update_water_distance() -> void:
	var w := grid.width
	var h := grid.height
	var max_water_dist := maxf(float(w) * 0.4, 50.0)
	_distance_to_water.fill(999.0)

	var queue: Array[Vector2i] = []
	for y in range(h):
		for x in range(w):
			if grid.get_tile_center_height(x, y) < GameConfig.SEA_LEVEL:
				_distance_to_water[y * w + x] = 0.0
				queue.append(Vector2i(x, y))

	var head := 0
	while head < queue.size():
		var pos := queue[head]
		head += 1
		var current_dist := _distance_to_water[pos.y * w + pos.x]
		if current_dist > max_water_dist:
			continue
		for neighbor in grid.get_neighbors_4(pos.x, pos.y):
			var ni := neighbor.y * w + neighbor.x
			var new_dist := current_dist + 1.0
			if new_dist < _distance_to_water[ni]:
				_distance_to_water[ni] = new_dist
				queue.append(neighbor)


func _process_chunk() -> void:
	var w := grid.width
	var h := grid.height
	var total := w * h
	var end_idx := mini(_chunk_offset + CHUNK_SIZE, total)
	var max_water_dist := maxf(float(w) * 0.4, 50.0)
	
	for i in range(_chunk_offset, end_idx):
		var x := i % w
		var y := int(float(i) / float(w))
		
		var altitude := grid.get_height(x, y)
		
		var latitude_factor: float
		var noise_var_t: float
		var noise_var_m: float
		var wind_bias: float
		var itcz_boost := 0.0
		var rain_shadow := 0.0
		var orographic := 0.0
		
		if projector:
			var wp := projector.grid_to_sphere(float(x), float(y)).normalized()
			var abs_lat := asin(clampf(absf(wp.y), 0.0, 1.0)) / (PI * 0.5)
			latitude_factor = 1.0 - abs_lat
			var sp := wp * 50.0
			noise_var_t = _noise_t_lo.get_noise_3d(sp.x, sp.y, sp.z) * 0.12 + _noise_t_hi.get_noise_3d(sp.x, sp.y, sp.z) * 0.06
			noise_var_m = _noise_m_lo.get_noise_3d(sp.x, sp.y, sp.z) * 0.18 + _noise_m_hi.get_noise_3d(sp.x, sp.y, sp.z) * 0.08 + 0.08
			wind_bias = wp.x * 0.06
			
			var abs_lat_m := absf(wp.y)
			itcz_boost = clampf(1.0 - abs_lat_m / 0.2, 0.0, 1.0) * 0.25
			
			if altitude > 0.2:
				var slope := _get_slope(x, y)
				var windward := clampf(slope * wp.x, 0.0, 1.0)
				orographic = windward * 0.15
				var leeward := clampf(-slope * wp.x, 0.0, 1.0)
				rain_shadow = -leeward * 0.2
		else:
			latitude_factor = 1.0 - abs((float(y) / float(h)) * 2.0 - 1.0)
			noise_var_t = _noise_t_lo.get_noise_2d(float(x), float(y)) * 0.12
			noise_var_m = _noise_m_lo.get_noise_2d(float(x), float(y)) * 0.18 + 0.08
			wind_bias = sin(float(x) / float(w) * TAU) * 0.06
			var lat_frac := absf(float(y) / float(h) * 2.0 - 1.0)
			itcz_boost = clampf(1.0 - lat_frac / 0.15, 0.0, 1.0) * 0.25
			
		# Temperature
		var base_temp: float = latitude_factor
		var altitude_cooling := maxf(altitude, 0.0) * 0.5
		var ocean_warming := 0.0
		if altitude < GameConfig.SEA_LEVEL:
			ocean_warming = 0.06 * clampf(latitude_factor, 0.2, 0.8)
		var target_temp := clampf(base_temp - altitude_cooling + noise_var_t + ocean_warming, 0.0, 1.0)
		
		# Moisture
		var dist := _distance_to_water[i]
		var water_proximity := clampf(1.0 - dist / max_water_dist, 0.0, 1.0)
		var target_moist := clampf(water_proximity * 0.55 + noise_var_m + wind_bias + itcz_boost + orographic + rain_shadow, 0.0, 1.0)
		
		# Slowly blend base climate towards target
		base_temperature_map[i] = lerpf(base_temperature_map[i], target_temp, 0.05)
		base_moisture_map[i] = lerpf(base_moisture_map[i], target_moist, 0.05)

	_chunk_offset = end_idx if end_idx < total else 0


func _get_slope(x: int, y: int) -> float:
	var left := grid.get_height(grid.wrap_x(x - 1), y)
	var right := grid.get_height(grid.wrap_x(x + 1), y)
	return right - left

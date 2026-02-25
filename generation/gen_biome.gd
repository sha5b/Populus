class_name GenBiome

var _seed: int


func _init(world_seed: int = 0) -> void:
	_seed = world_seed


func generate(grid: TorusGrid, temperature_map: PackedFloat32Array, moisture_map: PackedFloat32Array, proj: PlanetProjector = null) -> void:
	_generate_temperature(grid, temperature_map, proj)
	_generate_moisture(grid, moisture_map, proj)
	# Diagnostic: verify map distributions
	var t_min := 1.0; var t_max := 0.0; var t_sum := 0.0
	var m_min := 1.0; var m_max := 0.0; var m_sum := 0.0
	for i in range(temperature_map.size()):
		t_min = minf(t_min, temperature_map[i]); t_max = maxf(t_max, temperature_map[i]); t_sum += temperature_map[i]
		m_min = minf(m_min, moisture_map[i]); m_max = maxf(m_max, moisture_map[i]); m_sum += moisture_map[i]
	var n := float(temperature_map.size())
	print("Biome maps (%dx%d): temp=[%.2f, %.2f] avg=%.2f | moist=[%.2f, %.2f] avg=%.2f" % [
		grid.width, grid.height, t_min, t_max, t_sum / n, m_min, m_max, m_sum / n
	])


func _generate_temperature(grid: TorusGrid, temp_map: PackedFloat32Array, proj: PlanetProjector = null) -> void:
	var noise_lo := FastNoiseLite.new()
	noise_lo.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_lo.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_lo.fractal_octaves = 3
	noise_lo.frequency = 0.02
	noise_lo.seed = _seed + 2000

	var noise_hi := FastNoiseLite.new()
	noise_hi.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_hi.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_hi.fractal_octaves = 2
	noise_hi.frequency = 0.06
	noise_hi.seed = _seed + 2100

	var w := grid.width
	var h := grid.height

	for y in range(h):
		for x in range(w):
			var latitude_factor: float
			var noise_var: float

			if proj:
				var wp := proj.grid_to_sphere(float(x), float(y)).normalized()
				var abs_lat := asin(clampf(absf(wp.y), 0.0, 1.0)) / (PI * 0.5)
				latitude_factor = 1.0 - abs_lat
				var sp := wp * 50.0
				noise_var = noise_lo.get_noise_3d(sp.x, sp.y, sp.z) * 0.12 + noise_hi.get_noise_3d(sp.x, sp.y, sp.z) * 0.06
			else:
				latitude_factor = 1.0 - abs((float(y) / float(h)) * 2.0 - 1.0)
				noise_var = noise_lo.get_noise_2d(float(x), float(y)) * 0.12

			var base_temp: float = latitude_factor
			var altitude := grid.get_height(x, y)
			var altitude_cooling := maxf(altitude, 0.0) * 0.5
			var ocean_warming := 0.0
			if altitude < GameConfig.SEA_LEVEL:
				ocean_warming = 0.06 * clampf(latitude_factor, 0.2, 0.8)
			var temp := clampf(base_temp - altitude_cooling + noise_var + ocean_warming, 0.0, 1.0)
			temp_map[y * w + x] = temp


func _generate_moisture(grid: TorusGrid, moist_map: PackedFloat32Array, proj: PlanetProjector = null) -> void:
	var w := grid.width
	var h := grid.height

	# Max distance scales with grid size so interior moisture stays consistent
	var max_water_dist := maxf(float(w) * 0.4, 50.0)

	var distance_to_water := PackedFloat32Array()
	distance_to_water.resize(w * h)
	distance_to_water.fill(999.0)

	var queue: Array[Vector2i] = []
	for y in range(h):
		for x in range(w):
			if grid.get_tile_center_height(x, y) < GameConfig.SEA_LEVEL:
				distance_to_water[y * w + x] = 0.0
				queue.append(Vector2i(x, y))

	var head := 0
	while head < queue.size():
		var pos := queue[head]
		head += 1
		var current_dist := distance_to_water[pos.y * w + pos.x]
		if current_dist > max_water_dist:
			continue
		for neighbor in grid.get_neighbors_4(pos.x, pos.y):
			var ni := neighbor.y * w + neighbor.x
			var new_dist := current_dist + 1.0
			if new_dist < distance_to_water[ni]:
				distance_to_water[ni] = new_dist
				queue.append(neighbor)

	var noise_lo := FastNoiseLite.new()
	noise_lo.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_lo.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_lo.fractal_octaves = 4
	noise_lo.frequency = 0.025
	noise_lo.seed = _seed + 3000

	var noise_hi := FastNoiseLite.new()
	noise_hi.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_hi.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_hi.fractal_octaves = 2
	noise_hi.frequency = 0.07
	noise_hi.seed = _seed + 3100

	for y in range(h):
		for x in range(w):
			var dist := distance_to_water[y * w + x]
			var water_proximity := clampf(1.0 - dist / max_water_dist, 0.0, 1.0)

			var noise_var: float
			var wind_bias: float
			var itcz_boost := 0.0
			var rain_shadow := 0.0
			var orographic := 0.0

			if proj:
				var wp := proj.grid_to_sphere(float(x), float(y)).normalized()
				var sp := wp * 50.0
				noise_var = noise_lo.get_noise_3d(sp.x, sp.y, sp.z) * 0.18 + noise_hi.get_noise_3d(sp.x, sp.y, sp.z) * 0.08 + 0.08
				wind_bias = wp.x * 0.06

				var abs_lat := absf(wp.y)
				itcz_boost = clampf(1.0 - abs_lat / 0.2, 0.0, 1.0) * 0.25

				var altitude := grid.get_height(x, y)
				if altitude > 0.2:
					var slope := _get_slope(grid, x, y)
					var windward := clampf(slope * wp.x, 0.0, 1.0)
					orographic = windward * 0.15
					var leeward := clampf(-slope * wp.x, 0.0, 1.0)
					rain_shadow = -leeward * 0.2
			else:
				noise_var = noise_lo.get_noise_2d(float(x), float(y)) * 0.18 + 0.08
				wind_bias = sin(float(x) / float(w) * TAU) * 0.06
				var lat_frac := absf(float(y) / float(h) * 2.0 - 1.0)
				itcz_boost = clampf(1.0 - lat_frac / 0.15, 0.0, 1.0) * 0.25

			var moist := clampf(water_proximity * 0.55 + noise_var + wind_bias + itcz_boost + orographic + rain_shadow, 0.0, 1.0)
			moist_map[y * w + x] = moist


func _get_slope(grid: TorusGrid, x: int, y: int) -> float:
	var left := grid.get_height(grid.wrap_x(x - 1), y)
	var right := grid.get_height(grid.wrap_x(x + 1), y)
	return right - left

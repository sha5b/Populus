class_name GenBiome

var _seed: int


func _init(world_seed: int = 0) -> void:
	_seed = world_seed


func generate(grid: TorusGrid, temperature_map: PackedFloat32Array, moisture_map: PackedFloat32Array, proj: PlanetProjector = null) -> void:
	_generate_temperature(grid, temperature_map, proj)
	_generate_moisture(grid, moisture_map, proj)
	print("Generated biome data: temperature + moisture maps.")


func _generate_temperature(grid: TorusGrid, temp_map: PackedFloat32Array, proj: PlanetProjector = null) -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.03
	noise.seed = _seed + 2000

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
				noise_var = noise.get_noise_3d(wp.x * 50.0, wp.y * 50.0, wp.z * 50.0) * 0.15
			else:
				latitude_factor = 1.0 - abs((float(y) / float(h)) * 2.0 - 1.0)
				noise_var = noise.get_noise_2d(float(x), float(y)) * 0.15

			var base_temp: float = latitude_factor
			var altitude := grid.get_height(x, y)
			var altitude_cooling := maxf(altitude, 0.0) * 0.4
			var temp := clampf(base_temp - altitude_cooling + noise_var, 0.0, 1.0)
			temp_map[y * w + x] = temp


func _generate_moisture(grid: TorusGrid, moist_map: PackedFloat32Array, proj: PlanetProjector = null) -> void:
	var w := grid.width
	var h := grid.height

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
		if current_dist > 30.0:
			continue
		for neighbor in grid.get_neighbors_4(pos.x, pos.y):
			var ni := neighbor.y * w + neighbor.x
			var new_dist := current_dist + 1.0
			if new_dist < distance_to_water[ni]:
				distance_to_water[ni] = new_dist
				queue.append(neighbor)

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.04
	noise.seed = _seed + 3000

	for y in range(h):
		for x in range(w):
			var dist := distance_to_water[y * w + x]
			var water_proximity := clampf(1.0 - dist / 30.0, 0.0, 1.0)

			var noise_var: float
			var wind_bias: float
			if proj:
				var wp := proj.grid_to_sphere(float(x), float(y)).normalized()
				noise_var = noise.get_noise_3d(wp.x * 50.0, wp.y * 50.0, wp.z * 50.0) * 0.2 + 0.1
				wind_bias = wp.x * 0.08
			else:
				noise_var = noise.get_noise_2d(float(x), float(y)) * 0.2 + 0.1
				wind_bias = sin(float(x) / float(w) * TAU) * 0.08

			var moist := clampf(water_proximity * 0.7 + noise_var + wind_bias, 0.0, 1.0)
			moist_map[y * w + x] = moist

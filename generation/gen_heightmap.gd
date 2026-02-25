class_name GenHeightmap

var _seed: int


func _init(world_seed: int = 0) -> void:
	if world_seed == 0:
		_seed = randi()
	else:
		_seed = world_seed


func generate(grid: TorusGrid) -> void:
	var continental := FastNoiseLite.new()
	continental.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	continental.fractal_type = FastNoiseLite.FRACTAL_FBM
	continental.frequency = 0.015
	continental.fractal_octaves = 6
	continental.fractal_lacunarity = 2.0
	continental.fractal_gain = 0.5
	continental.seed = _seed

	var detail := FastNoiseLite.new()
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail.frequency = 0.08
	detail.fractal_octaves = 4
	detail.fractal_lacunarity = 2.0
	detail.fractal_gain = 0.5
	detail.seed = _seed + 1000

	var w := grid.width
	var h := grid.height

	var min_h := 999.0
	var max_h := -999.0

	for y in range(h):
		for x in range(w):
			var c := continental.get_noise_2d(float(x), float(y))
			var d := detail.get_noise_2d(float(x), float(y))
			var raw := c + d * 0.3
			grid.set_height(x, y, raw)
			min_h = minf(min_h, raw)
			max_h = maxf(max_h, raw)

	_normalize(grid, min_h, max_h)

	var land_count := 0
	var total := w * h
	for y in range(h):
		for x in range(w):
			if grid.get_tile_center_height(x, y) >= GameConfig.SEA_LEVEL:
				land_count += 1

	var land_pct := float(land_count) / float(total) * 100.0
	print("Generated heightmap (seed=%d). Land: %.0f%%, Water: %.0f%%" % [
		_seed, land_pct, 100.0 - land_pct
	])


func _normalize(grid: TorusGrid, min_h: float, max_h: float) -> void:
	var range_h := max_h - min_h
	if range_h < 0.001:
		return

	var w := grid.width
	var h := grid.height
	var target_water := 0.45

	var all_heights: Array[float] = []
	all_heights.resize(w * h)
	for y in range(h):
		for x in range(w):
			var normalized := (grid.get_height(x, y) - min_h) / range_h
			all_heights[y * w + x] = normalized

	all_heights.sort()
	var sea_threshold := all_heights[int(float(all_heights.size()) * target_water)]

	for y in range(h):
		for x in range(w):
			var normalized := (grid.get_height(x, y) - min_h) / range_h
			var shifted := normalized - sea_threshold
			grid.set_height(x, y, shifted)

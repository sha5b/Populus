class_name GenHeightmap

var _seed: int

var continentalness_map: PackedFloat32Array
var erosion_map: PackedFloat32Array
var peaks_valleys_map: PackedFloat32Array
var weirdness_map: PackedFloat32Array


func _init(world_seed: int = 0) -> void:
	if world_seed == 0:
		_seed = randi()
	else:
		_seed = world_seed


func generate(grid: TorusGrid, proj: PlanetProjector = null) -> void:
	var w := grid.width
	var h := grid.height
	var total := w * h

	continentalness_map = PackedFloat32Array()
	continentalness_map.resize(total)
	erosion_map = PackedFloat32Array()
	erosion_map.resize(total)
	peaks_valleys_map = PackedFloat32Array()
	peaks_valleys_map.resize(total)
	weirdness_map = PackedFloat32Array()
	weirdness_map.resize(total)

	var continental := _make_noise(_seed, 0.012, 6, FastNoiseLite.FRACTAL_FBM)
	var erosion_noise := _make_noise(_seed + 1000, 0.02, 5, FastNoiseLite.FRACTAL_FBM)
	var pv_noise := _make_noise(_seed + 2000, 0.035, 4, FastNoiseLite.FRACTAL_RIDGED)
	var detail := _make_noise(_seed + 3000, 0.1, 3, FastNoiseLite.FRACTAL_FBM)
	var weird_noise := _make_noise(_seed + 4000, 0.025, 3, FastNoiseLite.FRACTAL_FBM)

	var min_h := 999.0
	var max_h := -999.0

	for y in range(h):
		for x in range(w):
			var idx := y * w + x

			var sx: float
			var sy: float
			var sz: float
			if proj:
				var wp := proj.grid_to_sphere(float(x), float(y)).normalized()
				sx = wp.x * 50.0
				sy = wp.y * 50.0
				sz = wp.z * 50.0
			else:
				sx = float(x)
				sy = float(y)
				sz = 0.0

			var c := (continental.get_noise_3d(sx, sy, sz) + 1.0) * 0.5
			var e := (erosion_noise.get_noise_3d(sx, sy, sz) + 1.0) * 0.5
			var pv := (pv_noise.get_noise_3d(sx, sy, sz) + 1.0) * 0.5
			var d := detail.get_noise_3d(sx, sy, sz)
			var weird := (weird_noise.get_noise_3d(sx, sy, sz) + 1.0) * 0.5

			continentalness_map[idx] = c
			erosion_map[idx] = e
			peaks_valleys_map[idx] = pv
			weirdness_map[idx] = weird

			var base_h := _continental_spline(c)
			var variance := _erosion_spline(1.0 - e)
			var raw := base_h + pv * variance * 0.6 + d * 0.08

			grid.set_height(x, y, raw)
			min_h = minf(min_h, raw)
			max_h = maxf(max_h, raw)

	_normalize(grid, min_h, max_h)

	var land_count := 0
	for y in range(h):
		for x in range(w):
			if grid.get_tile_center_height(x, y) >= GameConfig.SEA_LEVEL:
				land_count += 1

	var land_pct := float(land_count) / float(total) * 100.0
	print("Generated heightmap (5 noise maps, seed=%d). Land: %.0f%%, Water: %.0f%%" % [
		_seed, land_pct, 100.0 - land_pct
	])


func _make_noise(seed_val: int, freq: float, octaves: int, fractal: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = fractal
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_lacunarity = 2.0
	n.fractal_gain = 0.5
	n.seed = seed_val
	return n


func _continental_spline(c: float) -> float:
	if c < 0.3:
		return lerpf(-0.5, -0.1, c / 0.3)
	elif c < 0.45:
		return lerpf(-0.1, 0.05, (c - 0.3) / 0.15)
	elif c < 0.55:
		return lerpf(0.05, 0.15, (c - 0.45) / 0.1)
	elif c < 0.75:
		return lerpf(0.15, 0.35, (c - 0.55) / 0.2)
	else:
		return lerpf(0.35, 0.7, (c - 0.75) / 0.25)


func _erosion_spline(inv_erosion: float) -> float:
	if inv_erosion < 0.2:
		return 0.02
	elif inv_erosion < 0.5:
		return lerpf(0.02, 0.15, (inv_erosion - 0.2) / 0.3)
	elif inv_erosion < 0.8:
		return lerpf(0.15, 0.4, (inv_erosion - 0.5) / 0.3)
	else:
		return lerpf(0.4, 0.65, (inv_erosion - 0.8) / 0.2)


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

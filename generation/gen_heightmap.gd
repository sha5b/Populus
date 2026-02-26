class_name GenHeightmap

var _seed: int

var continentalness_map: PackedFloat32Array
var erosion_map: PackedFloat32Array
var peaks_valleys_map: PackedFloat32Array
var weirdness_map: PackedFloat32Array

const NUM_PLATES := 12
const PLATE_BOUNDARY_WIDTH := 0.14
const MOUNTAIN_RIDGE_STRENGTH := 0.85
const RIFT_DEPTH := 0.35
const POLAR_DAMPING_START := 0.7
const VOLCANIC_STRENGTH := 0.5
const SHELF_DROP := 0.18

var _plate_centers: Array[Vector3] = []
var _plate_is_continental: Array[bool] = []


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

	_generate_plates()

	var continental := _make_noise(_seed, 0.012, 6, FastNoiseLite.FRACTAL_FBM)
	var erosion_noise := _make_noise(_seed + 1000, 0.02, 5, FastNoiseLite.FRACTAL_FBM)
	var ridge_noise := _make_noise(_seed + 2000, 0.035, 5, FastNoiseLite.FRACTAL_RIDGED)
	var ridge_detail := _make_noise(_seed + 2500, 0.07, 4, FastNoiseLite.FRACTAL_RIDGED)
	var detail := _make_noise(_seed + 3000, 0.08, 4, FastNoiseLite.FRACTAL_FBM)
	var micro_detail := _make_noise(_seed + 3500, 0.16, 3, FastNoiseLite.FRACTAL_FBM)
	var weird_noise := _make_noise(_seed + 4000, 0.018, 4, FastNoiseLite.FRACTAL_FBM)
	var warp_noise := _make_noise(_seed + 5000, 0.025, 3, FastNoiseLite.FRACTAL_FBM)
	var warp_noise2 := _make_noise(_seed + 5500, 0.04, 2, FastNoiseLite.FRACTAL_FBM)
	var volcano_noise := _make_noise(_seed + 6000, 0.06, 3, FastNoiseLite.FRACTAL_FBM)

	# Ocean floor detail noises
	var ocean_ridge := _make_noise(_seed + 7000, 0.045, 4, FastNoiseLite.FRACTAL_RIDGED)
	var ocean_trench := _make_noise(_seed + 7500, 0.03, 3, FastNoiseLite.FRACTAL_FBM)
	var ocean_seamount := _make_noise(_seed + 8000, 0.08, 3, FastNoiseLite.FRACTAL_FBM)
	var ocean_stones := _make_noise(_seed + 8500, 0.2, 2, FastNoiseLite.FRACTAL_FBM)

	var min_h := 999.0
	var max_h := -999.0

	for y in range(h):
		for x in range(w):
			var map_idx := y * w + x

			var dir: Vector3
			if proj:
				dir = proj.grid_to_sphere(float(x), float(y)).normalized()
			else:
				var lon := float(x) / float(w) * TAU
				var lat := float(y) / float(h) * PI - PI * 0.5
				dir = Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))

			var sp := dir * 50.0

			var warp_x := warp_noise.get_noise_3d(sp.x, sp.y, sp.z) * 4.5
			var warp_y := warp_noise2.get_noise_3d(sp.x + 200.0, sp.y + 200.0, sp.z) * 3.0
			var warp_z := warp_noise.get_noise_3d(sp.x + 100.0, sp.y + 100.0, sp.z + 100.0) * 4.5
			var warped := Vector3(sp.x + warp_x, sp.y + warp_y, sp.z + warp_z)

			var c := (continental.get_noise_3d(warped.x, warped.y, warped.z) + 1.0) * 0.5
			var e := (erosion_noise.get_noise_3d(warped.x, warped.y, warped.z) + 1.0) * 0.5
			var ridge := (ridge_noise.get_noise_3d(warped.x, warped.y, warped.z) + 1.0) * 0.5
			var ridge2 := (ridge_detail.get_noise_3d(warped.x * 1.3, warped.y * 1.3, warped.z * 1.3) + 1.0) * 0.5
			var d := detail.get_noise_3d(sp.x * 1.5, sp.y * 1.5, sp.z * 1.5)
			var md := micro_detail.get_noise_3d(sp.x * 2.0, sp.y * 2.0, sp.z * 2.0)
			var weird := (weird_noise.get_noise_3d(warped.x, warped.y, warped.z) + 1.0) * 0.5
			var volc := (volcano_noise.get_noise_3d(warped.x, warped.y, warped.z) + 1.0) * 0.5

			var plate_info := _get_plate_info(dir)
			var boundary_factor: float = plate_info[0]
			var is_convergent: bool = plate_info[1]
			var plate_continental: bool = plate_info[2]

			continentalness_map[map_idx] = c
			erosion_map[map_idx] = e
			peaks_valleys_map[map_idx] = ridge
			weirdness_map[map_idx] = weird

			var base_h := _continental_spline(c)

			if plate_continental:
				base_h += 0.08

			var tectonic_h := 0.0
			if boundary_factor > 0.0:
				if is_convergent:
					tectonic_h = boundary_factor * MOUNTAIN_RIDGE_STRENGTH * ridge
					if volc > 0.7 and boundary_factor > 0.5:
						tectonic_h += (volc - 0.7) * VOLCANIC_STRENGTH * 3.0
				else:
					tectonic_h = -boundary_factor * RIFT_DEPTH

			var variance := _erosion_spline(1.0 - e)
			var mountain_h := (ridge * 0.6 + ridge2 * 0.4) * variance * 0.35 * (1.0 - boundary_factor * 0.5)

			var shelf_h := 0.0
			if base_h > -0.05 and base_h < 0.08:
				shelf_h = -SHELF_DROP * clampf(1.0 - absf(base_h) / 0.08, 0.0, 1.0) * e

			var abs_lat := absf(dir.y)
			var polar_damp := 1.0
			if abs_lat > POLAR_DAMPING_START:
				polar_damp = 1.0 - (abs_lat - POLAR_DAMPING_START) / (1.0 - POLAR_DAMPING_START)
				polar_damp = clampf(polar_damp, 0.1, 1.0)

			var raw := base_h + (tectonic_h + mountain_h + shelf_h) * polar_damp + d * 0.1 + md * 0.04

			# Ocean floor detail: ridges, trenches, seamounts, stones
			if raw < 0.0:
				var ocean_depth := absf(raw)
				var or_val := (ocean_ridge.get_noise_3d(warped.x, warped.y, warped.z) + 1.0) * 0.5
				var ot_val := ocean_trench.get_noise_3d(warped.x, warped.y, warped.z)
				var os_val := (ocean_seamount.get_noise_3d(sp.x, sp.y, sp.z) + 1.0) * 0.5
				var stone_val := ocean_stones.get_noise_3d(sp.x * 2.0, sp.y * 2.0, sp.z * 2.0)

				# Mid-ocean ridges — raised spines on deep ocean floor
				var ridge_h := or_val * or_val * 0.30 * clampf(ocean_depth / 0.3, 0.0, 1.0)
				# Extra ridge at divergent plate boundaries
				if boundary_factor > 0.3 and not is_convergent:
					ridge_h += boundary_factor * 0.20 * or_val

				# Deep trenches — narrow deep cuts
				var trench_h := 0.0
				if ot_val > 0.5:
					trench_h = -(ot_val - 0.5) * 0.8 * boundary_factor

				# Seamounts — isolated underwater peaks
				var seamount_h := 0.0
				if os_val > 0.70:
					seamount_h = (os_val - 0.70) * 1.2 * clampf(ocean_depth / 0.2, 0.0, 1.0)

				# Small stone/rock variation across ocean floor
				var stone_h := stone_val * 0.06

				raw += ridge_h + trench_h + seamount_h + stone_h

			# Initialize strata
			# We give a base sediment layer everywhere, deeper in valleys and oceans
			var sediment := 0.02 + clampf(1.0 - ridge, 0.0, 1.0) * 0.05
			if raw < 0.0:
				sediment += absf(raw) * 0.1 # More sediment in oceans
			
			var bedrock := raw - sediment

			grid.set_bedrock(x, y, bedrock)
			grid.set_sediment(x, y, sediment)
			
			min_h = minf(min_h, raw)
			max_h = maxf(max_h, raw)

	# Normalize operates on bedrock since it's the structural base
	_normalize_bedrock(grid, min_h, max_h)

	var land_count := 0
	for y in range(h):
		for x in range(w):
			if grid.get_tile_center_height(x, y) >= GameConfig.SEA_LEVEL:
				land_count += 1

	var land_pct := float(land_count) / float(total) * 100.0
	print("Generated heightmap (tectonic + 6 noise, seed=%d, %d plates). Land: %.0f%%, Water: %.0f%%" % [
		_seed, NUM_PLATES, land_pct, 100.0 - land_pct
	])


func _generate_plates() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 7777

	_plate_centers.clear()
	_plate_is_continental.clear()

	for i in range(NUM_PLATES):
		var theta := rng.randf() * TAU
		var phi := acos(rng.randf_range(-0.85, 0.85))
		var center := Vector3(
			sin(phi) * cos(theta),
			cos(phi),
			sin(phi) * sin(theta)
		).normalized()
		_plate_centers.append(center)
		_plate_is_continental.append(rng.randf() < 0.55)


func _get_plate_info(dir: Vector3) -> Array:
	var closest_dist := 999.0
	var closest_idx := 0
	var second_dist := 999.0
	var second_idx := 0

	for i in range(_plate_centers.size()):
		var dist := dir.distance_to(_plate_centers[i])
		if dist < closest_dist:
			second_dist = closest_dist
			second_idx = closest_idx
			closest_dist = dist
			closest_idx = i
		elif dist < second_dist:
			second_dist = dist
			second_idx = i

	var boundary_dist := second_dist - closest_dist
	var max_boundary := PLATE_BOUNDARY_WIDTH * 2.0
	var boundary_factor := clampf(1.0 - boundary_dist / max_boundary, 0.0, 1.0)
	boundary_factor = boundary_factor * boundary_factor

	var both_continental := _plate_is_continental[closest_idx] and _plate_is_continental[second_idx]
	var both_oceanic := not _plate_is_continental[closest_idx] and not _plate_is_continental[second_idx]
	var is_convergent := both_continental or (not both_oceanic and boundary_factor > 0.3)

	return [boundary_factor, is_convergent, _plate_is_continental[closest_idx]]


func _make_noise(seed_val: int, freq: float, octaves: int, fractal: FastNoiseLite.FractalType) -> FastNoiseLite:
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
		return lerpf(-0.7, -0.15, c / 0.3)
	elif c < 0.42:
		return lerpf(-0.15, 0.05, (c - 0.3) / 0.12)
	elif c < 0.55:
		return lerpf(0.05, 0.2, (c - 0.42) / 0.13)
	elif c < 0.75:
		return lerpf(0.2, 0.5, (c - 0.55) / 0.2)
	else:
		return lerpf(0.5, 0.95, (c - 0.75) / 0.25)


func _erosion_spline(inv_erosion: float) -> float:
	if inv_erosion < 0.2:
		return 0.04
	elif inv_erosion < 0.5:
		return lerpf(0.04, 0.25, (inv_erosion - 0.2) / 0.3)
	elif inv_erosion < 0.8:
		return lerpf(0.25, 0.6, (inv_erosion - 0.5) / 0.3)
	else:
		return lerpf(0.6, 0.9, (inv_erosion - 0.8) / 0.2)


func _normalize_bedrock(grid: TorusGrid, min_h: float, max_h: float) -> void:
	if absf(max_h - min_h) < 0.001:
		return
	var w := grid.width
	var h := grid.height
	var range_h := max_h - min_h
	
	# Determine sea level threshold based on desired land percentage (~35%)
	var all_h: Array[float] = []
	for y in range(h):
		for x in range(w):
			all_h.append(grid.get_bedrock(x, y) + grid.get_sediment(x, y))
	all_h.sort()
	var sea_threshold_idx := int(float(all_h.size()) * 0.65)
	var sea_threshold: float = (all_h[sea_threshold_idx] - min_h) / range_h

	for y in range(h):
		for x in range(w):
			var bedrock := grid.get_bedrock(x, y)
			var sediment := grid.get_sediment(x, y)
			var total_h := bedrock + sediment
			
			var normalized_total := (total_h - min_h) / range_h
			var shifted_total := normalized_total - sea_threshold
			
			if shifted_total < GameConfig.SEA_LEVEL:
				var depth := GameConfig.SEA_LEVEL - shifted_total
				depth = pow(depth, GameConfig.OCEAN_DEPTH_POWER) * GameConfig.OCEAN_DEPTH_MULT
				shifted_total = GameConfig.SEA_LEVEL - depth
				
			# Keep sediment absolute depth, push the rest into bedrock
			grid.set_bedrock(x, y, shifted_total - sediment)

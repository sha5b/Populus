extends System
class_name SysMicroBiome

var grid: TorusGrid
var projector: PlanetProjector
var temperature_map: PackedFloat32Array
var moisture_map: PackedFloat32Array
var biome_map: PackedInt32Array
var river_map: PackedFloat32Array
var micro_biome_map: PackedInt32Array

var _reassign_timer: float = 0.0
const TICK_INTERVAL := 3.0
const CHUNK_SIZE := 4096

var _is_updating: bool = false
var _thread_task_id: int = -1

# Spatial coherence noise — modulates thresholds so nearby tiles agree
var _coherence_noise: FastNoiseLite
# Cached smoothed slope/curvature for less noisy classification
var _smooth_slope: PackedFloat32Array
var _smooth_curvature: PackedFloat32Array


func setup(
	g: TorusGrid,
	proj: PlanetProjector,
	temp: PackedFloat32Array,
	moist: PackedFloat32Array,
	bmap: PackedInt32Array,
	rmap: PackedFloat32Array
) -> void:
	grid = g
	projector = proj
	temperature_map = temp
	moisture_map = moist
	biome_map = bmap
	river_map = rmap
	var total := g.width * g.height
	micro_biome_map = PackedInt32Array()
	micro_biome_map.resize(total)
	micro_biome_map.fill(DefMicroBiomes.MicroBiomeType.STANDARD)

	var freq_scale := float(GameConfig.GRID_WIDTH) / float(g.width)
	_coherence_noise = FastNoiseLite.new()
	_coherence_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_coherence_noise.frequency = 0.06 * freq_scale
	_coherence_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_coherence_noise.fractal_octaves = 3
	_coherence_noise.seed = 9999

	_precompute_smooth_terrain()
	assign_all()


func update(_world: Node, delta: float) -> void:
	if _is_updating:
		if _thread_task_id != -1 and WorkerThreadPool.is_task_completed(_thread_task_id):
			WorkerThreadPool.wait_for_task_completion(_thread_task_id)
			_thread_task_id = -1
			_is_updating = false
			grid.is_dirty = true
		return

	_reassign_timer += delta
	if _reassign_timer < TICK_INTERVAL:
		return
	_reassign_timer -= TICK_INTERVAL
	
	_is_updating = true
	_thread_task_id = WorkerThreadPool.add_task(_assign_thread.bind(), true, "MicroBiomeReassign")


func _assign_thread() -> void:
	_precompute_smooth_terrain()
	var w := grid.width
	var total := w * grid.height
	for i in range(total):
		var x := i % w
		@warning_ignore("integer_division")
		var y := i / w
		micro_biome_map[i] = _classify_tile(x, y)
	_majority_filter()


func assign_all() -> void:
	_precompute_smooth_terrain()
	var w := grid.width
	var h := grid.height
	for y in range(h):
		for x in range(w):
			micro_biome_map[y * w + x] = _classify_tile(x, y)


func _precompute_smooth_terrain() -> void:
	var w := grid.width
	var h := grid.height
	var total := w * h
	_smooth_slope = PackedFloat32Array()
	_smooth_slope.resize(total)
	_smooth_curvature = PackedFloat32Array()
	_smooth_curvature.resize(total)

	# First pass: raw slope + curvature
	for y in range(h):
		for x in range(w):
			_smooth_slope[y * w + x] = _calc_slope(x, y)
			_smooth_curvature[y * w + x] = _calc_curvature(x, y)

	# Second pass: 3x3 box blur for spatial smoothing
	var slope_copy := _smooth_slope.duplicate()
	var curv_copy := _smooth_curvature.duplicate()
	for y in range(h):
		for x in range(w):
			var s_sum := 0.0
			var c_sum := 0.0
			var count := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := grid.wrap_x(x + dx)
					var ny := grid.wrap_y(y + dy)
					var ni := ny * w + nx
					s_sum += slope_copy[ni]
					c_sum += curv_copy[ni]
					count += 1
			var idx := y * w + x
			_smooth_slope[idx] = s_sum / float(count)
			_smooth_curvature[idx] = c_sum / float(count)


func _majority_filter() -> void:
	var w := grid.width
	var h := grid.height
	var temp_map := micro_biome_map.duplicate()

	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			var center := temp_map[idx]
			if center == DefMicroBiomes.MicroBiomeType.STANDARD:
				continue
			if center == DefMicroBiomes.MicroBiomeType.RIPARIAN:
				continue

			# Count how many of the 8 neighbors share this micro-biome
			var same := 0
			var _neighbor_count := 0
			for n in grid.get_neighbors_8(x, y):
				var ni := n.y * w + n.x
				if temp_map[ni] == center:
					same += 1
				_neighbor_count += 1
			
			if same < 3: # Isolated, revert to standard
				micro_biome_map[idx] = DefMicroBiomes.MicroBiomeType.STANDARD


func _classify_tile(x: int, y: int) -> int:
	var w := grid.width
	var idx := y * w + x
	var height := grid.get_height(x, y)

	if height < GameConfig.SEA_LEVEL:
		return DefMicroBiomes.MicroBiomeType.STANDARD

	# Use smoothed terrain metrics instead of raw per-tile values
	var slope := _smooth_slope[idx] if idx < _smooth_slope.size() else _calc_slope(x, y)
	var curvature := _smooth_curvature[idx] if idx < _smooth_curvature.size() else _calc_curvature(x, y)
	var aspect := _calc_aspect(x, y)
	var moist := moisture_map[idx] if idx < moisture_map.size() else 0.5

	# Spatial coherence: noise shifts thresholds ±15% so nearby tiles agree
	var cn := _coherence_noise.get_noise_2d(float(x), float(y)) * 0.15

	var is_river := false
	if river_map.size() > idx:
		is_river = river_map[idx] > 0.0
	var river_dist := _river_proximity(x, y)

	# RIPARIAN: rivers and immediate banks (always consistent — rivers are linear)
	if is_river or river_dist < 2.0:
		return DefMicroBiomes.MicroBiomeType.RIPARIAN

	# Concave + wet → basins, floodplains, wetlands
	if curvature < (-0.018 + cn * 0.005) and moist > (0.45 + cn * 0.1):
		if height < 0.06:
			return DefMicroBiomes.MicroBiomeType.FLOOD_PLAIN
		return DefMicroBiomes.MicroBiomeType.FERTILE_BASIN

	if curvature < (-0.012 + cn * 0.004) and moist > (0.6 + cn * 0.08):
		return DefMicroBiomes.MicroBiomeType.WETLAND

	# Steep slopes → ridges, sun/shade faces
	var slope_thresh := 0.13 + cn * 0.03
	if slope > slope_thresh:
		if curvature > (0.015 + cn * 0.005):
			return DefMicroBiomes.MicroBiomeType.RIDGE_EXPOSED
		if aspect > 0.005:
			return DefMicroBiomes.MicroBiomeType.SUN_SLOPE
		elif aspect < -0.005:
			return DefMicroBiomes.MicroBiomeType.SHADE_SLOPE

	# Altitude bands
	if height > (0.33 + cn * 0.03) and height < (0.47 + cn * 0.03):
		if slope > 0.04:
			return DefMicroBiomes.MicroBiomeType.TREELINE_EDGE

	if height > (0.44 + cn * 0.03) and slope < (0.08 + cn * 0.02):
		return DefMicroBiomes.MicroBiomeType.ALPINE_MEADOW

	# Wind-exposed + dry
	if slope > (0.08 + cn * 0.02) and moist < (0.28 + cn * 0.05):
		return DefMicroBiomes.MicroBiomeType.WINDSWEPT

	# Rocky outcrops — convex + steep
	if slope > (0.1 + cn * 0.02) and curvature > (0.012 + cn * 0.004):
		return DefMicroBiomes.MicroBiomeType.ROCKY_OUTCROP

	# Sheltered valleys — concave + flat
	if curvature < (-0.008 + cn * 0.003) and slope < (0.05 + cn * 0.01):
		return DefMicroBiomes.MicroBiomeType.VALLEY_SHELTERED

	# Ecotone: multiple biomes meeting (only if 2+ distinct neighbors)
	var neighbor_biomes := _count_neighbor_biomes(x, y)
	if neighbor_biomes >= 2:
		return DefMicroBiomes.MicroBiomeType.ECOTONE

	return DefMicroBiomes.MicroBiomeType.STANDARD


func _calc_slope(x: int, y: int) -> float:
	var h_l := grid.get_height(grid.wrap_x(x - 1), y)
	var h_r := grid.get_height(grid.wrap_x(x + 1), y)
	var h_u := grid.get_height(x, grid.wrap_y(y - 1))
	var h_d := grid.get_height(x, grid.wrap_y(y + 1))
	var dx := (h_r - h_l) * 0.5
	var dy := (h_d - h_u) * 0.5
	return sqrt(dx * dx + dy * dy)


func _calc_aspect(x: int, y: int) -> float:
	var h_l := grid.get_height(grid.wrap_x(x - 1), y)
	var h_r := grid.get_height(grid.wrap_x(x + 1), y)
	return h_r - h_l


func _calc_curvature(x: int, y: int) -> float:
	var h_c := grid.get_height(x, y)
	var h_l := grid.get_height(grid.wrap_x(x - 1), y)
	var h_r := grid.get_height(grid.wrap_x(x + 1), y)
	var h_u := grid.get_height(x, grid.wrap_y(y - 1))
	var h_d := grid.get_height(x, grid.wrap_y(y + 1))
	return (h_l + h_r + h_u + h_d) * 0.25 - h_c


func _river_proximity(x: int, y: int) -> float:
	if river_map.size() == 0:
		return 999.0
	var w := grid.width
	var best := 999.0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var nx := grid.wrap_x(x + dx)
			var ny := grid.wrap_y(y + dy)
			var ni := ny * w + nx
			if ni < river_map.size() and river_map[ni] > 0.0:
				var dist := sqrt(float(dx * dx + dy * dy))
				best = minf(best, dist)
	return best


func _count_neighbor_biomes(x: int, y: int) -> int:
	var w := grid.width
	var center_biome := biome_map[y * w + x] if (y * w + x) < biome_map.size() else -1
	var unique := {}
	for n in grid.get_neighbors_8(x, y):
		var ni := n.y * w + n.x
		if ni < biome_map.size():
			var b := biome_map[ni]
			if b != center_biome:
				unique[b] = true
	return unique.size()

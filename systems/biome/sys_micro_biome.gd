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
var _chunk_offset: int = 0
const TICK_INTERVAL := 3.0
const CHUNK_SIZE := 1024


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
	assign_all()


func update(_world: Node, delta: float) -> void:
	_reassign_timer += delta
	if _reassign_timer < TICK_INTERVAL:
		return
	_reassign_timer -= TICK_INTERVAL
	_assign_chunk()


func _assign_chunk() -> void:
	var w := grid.width
	var total := w * grid.height
	var end_idx := mini(_chunk_offset + CHUNK_SIZE, total)
	for i in range(_chunk_offset, end_idx):
		micro_biome_map[i] = _classify_tile(i % w, i / w)
	_chunk_offset = end_idx if end_idx < total else 0


func assign_all() -> void:
	var w := grid.width
	var h := grid.height
	for y in range(h):
		for x in range(w):
			micro_biome_map[y * w + x] = _classify_tile(x, y)


func _classify_tile(x: int, y: int) -> int:
	var w := grid.width
	var idx := y * w + x
	var height := grid.get_height(x, y)

	if height < GameConfig.SEA_LEVEL:
		return DefMicroBiomes.MicroBiomeType.STANDARD

	var biome: int = biome_map[idx] if idx < biome_map.size() else 0
	var slope := _calc_slope(x, y)
	var aspect := _calc_aspect(x, y)
	var curvature := _calc_curvature(x, y)
	var river_dist := _river_proximity(x, y)
	var moist := moisture_map[idx] if idx < moisture_map.size() else 0.5
	var is_river := false
	if river_map.size() > idx:
		is_river = river_map[idx] > 0.0
	var neighbor_biomes := _count_neighbor_biomes(x, y)

	if is_river or river_dist < 2.0:
		return DefMicroBiomes.MicroBiomeType.RIPARIAN

	if curvature < -0.02 and moist > 0.5:
		if height < 0.05:
			return DefMicroBiomes.MicroBiomeType.FLOOD_PLAIN
		return DefMicroBiomes.MicroBiomeType.FERTILE_BASIN

	if curvature < -0.015 and moist > 0.65:
		return DefMicroBiomes.MicroBiomeType.WETLAND

	if slope > 0.15:
		if curvature > 0.02:
			return DefMicroBiomes.MicroBiomeType.RIDGE_EXPOSED
		if aspect > 0.0:
			return DefMicroBiomes.MicroBiomeType.SUN_SLOPE
		else:
			return DefMicroBiomes.MicroBiomeType.SHADE_SLOPE

	if height > 0.35 and height < 0.45:
		return DefMicroBiomes.MicroBiomeType.TREELINE_EDGE

	if height > 0.45 and slope < 0.08:
		return DefMicroBiomes.MicroBiomeType.ALPINE_MEADOW

	if slope > 0.1 and moist < 0.25:
		return DefMicroBiomes.MicroBiomeType.WINDSWEPT

	if slope > 0.12 and curvature > 0.015:
		return DefMicroBiomes.MicroBiomeType.ROCKY_OUTCROP

	if curvature < -0.01 and slope < 0.05:
		return DefMicroBiomes.MicroBiomeType.VALLEY_SHELTERED

	if neighbor_biomes > 1:
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

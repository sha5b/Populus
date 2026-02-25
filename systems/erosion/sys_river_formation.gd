extends System
class_name SysRiverFormation

var grid: TorusGrid = null
var moisture_map: PackedFloat32Array
var river_map: PackedFloat32Array
var time_system: SysTime = null

var river_carve_rate: float = 0.005
var river_moisture_boost: float = 0.3
var river_moisture_radius: int = 3

var _last_season: int = -1
var _river_count: int = 0
var _lake_count: int = 0


func setup(g: TorusGrid, ts: SysTime, moist: PackedFloat32Array) -> void:
	grid = g
	time_system = ts
	moisture_map = moist
	river_map = PackedFloat32Array()
	river_map.resize(g.width * g.height)
	river_map.fill(0.0)


func update(_world: Node, _delta: float) -> void:
	if grid == null or time_system == null:
		return

	if time_system.season == _last_season:
		return
	_last_season = time_system.season

	_recalculate_rivers()


func _recalculate_rivers() -> void:
	var w := grid.width
	var h := grid.height

	river_map.fill(0.0)
	_river_count = 0
	_lake_count = 0

	var flow_accumulation := PackedFloat32Array()
	flow_accumulation.resize(w * h)
	flow_accumulation.fill(1.0)

	var sorted_tiles: Array[Vector2i] = []
	var height_pairs: Array[float] = []

	for y in range(h):
		for x in range(w):
			var ch := grid.get_tile_center_height(x, y)
			if ch > GameConfig.SEA_LEVEL:
				sorted_tiles.append(Vector2i(x, y))
				height_pairs.append(ch)

	var indices: Array[int] = []
	indices.resize(sorted_tiles.size())
	for i in range(indices.size()):
		indices[i] = i
	indices.sort_custom(func(a: int, b: int) -> bool: return height_pairs[a] > height_pairs[b])

	for idx in indices:
		var pos := sorted_tiles[idx]
		var x := pos.x
		var y := pos.y
		var current_h := grid.get_height(x, y)

		var lowest_n := Vector2i(-1, -1)
		var lowest_h := current_h
		for neighbor in grid.get_neighbors_4(x, y):
			var nh := grid.get_height(neighbor.x, neighbor.y)
			if nh < lowest_h:
				lowest_h = nh
				lowest_n = neighbor

		if lowest_n.x < 0:
			var tile_idx := y * w + x
			if flow_accumulation[tile_idx] > 10.0:
				_lake_count += 1
			continue

		var src_idx := y * w + x
		var dst_idx := lowest_n.y * w + lowest_n.x
		flow_accumulation[dst_idx] += flow_accumulation[src_idx]

	var river_threshold := 15.0
	for y2 in range(h):
		for x2 in range(w):
			var tile_idx := y2 * w + x2
			var flow := flow_accumulation[tile_idx]
			if flow >= river_threshold and grid.get_height(x2, y2) > GameConfig.SEA_LEVEL:
				river_map[tile_idx] = minf(flow / 100.0, 1.0)
				grid.set_height(x2, y2, grid.get_height(x2, y2) - river_carve_rate)

				for dy in range(-river_moisture_radius, river_moisture_radius + 1):
					for dx in range(-river_moisture_radius, river_moisture_radius + 1):
						var dist := sqrt(float(dx * dx + dy * dy))
						if dist <= float(river_moisture_radius):
							var mx := grid.wrap_x(x2 + dx)
							var my := grid.wrap_y(y2 + dy)
							var mi := my * w + mx
							if mi < moisture_map.size():
								var boost := river_moisture_boost * (1.0 - dist / float(river_moisture_radius))
								moisture_map[mi] = clampf(moisture_map[mi] + boost, 0.0, 1.0)

	for y3 in range(h):
		for x3 in range(w):
			if river_map[y3 * w + x3] > 0.0:
				_river_count += 1

	print("Rivers recalculated: %d river tiles, %d lakes" % [_river_count, _lake_count])


func is_river(x: int, y: int) -> bool:
	var idx := grid.wrap_y(y) * grid.width + grid.wrap_x(x)
	if idx < river_map.size():
		return river_map[idx] > 0.0
	return false

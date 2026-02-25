extends System
class_name SysRiverFormation

var grid: TorusGrid = null
var moisture_map: PackedFloat32Array
var river_map: PackedFloat32Array
var flow_map: PackedFloat32Array
var time_system: SysTime = null

const RIVER_THRESHOLD := 8.0
const CANYON_THRESHOLD := 40.0
const BASE_CARVE_RATE := 0.015
const CANYON_CARVE_RATE := 0.04
const CARVE_PASSES := 3
const RIVER_MOISTURE_BOOST := 0.25
const RIVER_MOISTURE_RADIUS := 4

var _last_season: int = -1
var _river_count: int = 0
var _lake_count: int = 0


func setup(g: TorusGrid, ts: SysTime, moist: PackedFloat32Array) -> void:
	grid = g
	time_system = ts
	moisture_map = moist
	var total := g.width * g.height
	river_map = PackedFloat32Array()
	river_map.resize(total)
	river_map.fill(0.0)
	flow_map = PackedFloat32Array()
	flow_map.resize(total)
	flow_map.fill(0.0)
	_run_initial_rivers()


func _run_initial_rivers() -> void:
	for _pass in range(CARVE_PASSES):
		_recalculate_rivers()
	print("Initial river carving: %d passes, %d river tiles, %d lakes" % [CARVE_PASSES, _river_count, _lake_count])


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
	var total := w * h

	var flow_accumulation := PackedFloat32Array()
	flow_accumulation.resize(total)
	var flow_dir := PackedInt32Array()
	flow_dir.resize(total)
	flow_dir.fill(-1)

	for i in range(total):
		var ht := grid.get_height(i % w, i / w)
		flow_accumulation[i] = 1.0 + maxf(moisture_map[i] if i < moisture_map.size() else 0.5, 0.0)

	var sorted_indices: Array[int] = []
	sorted_indices.resize(total)
	for i in range(total):
		sorted_indices[i] = i
	sorted_indices.sort_custom(func(a: int, b: int) -> bool:
		return grid.get_height(a % w, a / w) > grid.get_height(b % w, b / w)
	)

	_lake_count = 0
	for idx in sorted_indices:
		var x := idx % w
		var y := idx / w
		var current_h := grid.get_height(x, y)

		if current_h <= GameConfig.SEA_LEVEL:
			continue

		var best_n := -1
		var best_h := current_h
		for neighbor in grid.get_neighbors_8(x, y):
			var nh := grid.get_height(neighbor.x, neighbor.y)
			if nh < best_h:
				best_h = nh
				best_n = neighbor.y * w + neighbor.x

		if best_n < 0:
			if flow_accumulation[idx] > 10.0:
				_lake_count += 1
			continue

		flow_dir[idx] = best_n
		flow_accumulation[best_n] += flow_accumulation[idx]

	river_map.fill(0.0)
	_river_count = 0

	for i in range(total):
		var flow := flow_accumulation[i]
		var x := i % w
		var y := i / w
		var ht := grid.get_height(x, y)

		if ht <= GameConfig.SEA_LEVEL:
			continue

		if flow >= RIVER_THRESHOLD:
			var strength := clampf(flow / 80.0, 0.1, 1.0)
			river_map[i] = strength
			_river_count += 1

			var carve := BASE_CARVE_RATE * clampf(flow / 30.0, 0.5, 3.0)
			if flow >= CANYON_THRESHOLD:
				carve = CANYON_CARVE_RATE * clampf(flow / 60.0, 1.0, 4.0)
				_widen_canyon(x, y, clampf(flow / 100.0, 0.3, 0.8))
			grid.set_height(x, y, maxf(ht - carve, GameConfig.SEA_LEVEL + 0.001))

	flow_map = flow_accumulation
	_apply_moisture_boost(w, h)


func _widen_canyon(cx: int, cy: int, depth: float) -> void:
	for neighbor in grid.get_neighbors_8(cx, cy):
		var nh := grid.get_height(neighbor.x, neighbor.y)
		if nh > GameConfig.SEA_LEVEL:
			var side_carve := depth * 0.3
			grid.set_height(neighbor.x, neighbor.y, maxf(nh - side_carve, GameConfig.SEA_LEVEL + 0.001))


func _apply_moisture_boost(w: int, h: int) -> void:
	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			if river_map[idx] <= 0.0:
				continue
			for dy in range(-RIVER_MOISTURE_RADIUS, RIVER_MOISTURE_RADIUS + 1):
				for dx in range(-RIVER_MOISTURE_RADIUS, RIVER_MOISTURE_RADIUS + 1):
					var dist := sqrt(float(dx * dx + dy * dy))
					if dist <= float(RIVER_MOISTURE_RADIUS):
						var mx := grid.wrap_x(x + dx)
						var my := grid.wrap_y(y + dy)
						var mi := my * w + mx
						if mi < moisture_map.size():
							var boost := RIVER_MOISTURE_BOOST * (1.0 - dist / float(RIVER_MOISTURE_RADIUS))
							moisture_map[mi] = clampf(moisture_map[mi] + boost, 0.0, 1.0)


func is_river(x: int, y: int) -> bool:
	var idx := grid.wrap_y(y) * grid.width + grid.wrap_x(x)
	if idx < river_map.size():
		return river_map[idx] > 0.0
	return false

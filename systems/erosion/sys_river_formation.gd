extends System
class_name SysRiverFormation

var grid: TorusGrid = null
var moisture_map: PackedFloat32Array
var river_map: PackedFloat32Array
var flow_map: PackedFloat32Array
var time_system: SysTime = null

const BASE_RIVER_THRESHOLD := GameConfig.RIVER_BASE_RIVER_THRESHOLD
const BASE_CANYON_THRESHOLD := GameConfig.RIVER_BASE_CANYON_THRESHOLD
const BASE_CARVE_RATE := GameConfig.RIVER_BASE_CARVE_RATE
const CANYON_CARVE_RATE := GameConfig.RIVER_CANYON_CARVE_RATE
const CARVE_PASSES := GameConfig.RIVER_CARVE_PASSES
const RIVER_MOISTURE_BOOST := GameConfig.RIVER_MOISTURE_BOOST
const RIVER_MOISTURE_RADIUS := GameConfig.RIVER_MOISTURE_RADIUS

# These get computed in setup() based on grid size
var RIVER_THRESHOLD := 25.0
var CANYON_THRESHOLD := 80.0

var _last_season: int = -1
var _river_count: int = 0
var _lake_count: int = 0


func setup(g: TorusGrid, ts: SysTime, moist: PackedFloat32Array) -> void:
	grid = g
	time_system = ts
	moisture_map = moist
	var total := g.width * g.height

	# Scale thresholds with grid size — flow accumulation grows with more upstream tiles
	var scale_factor := float(g.width) / 128.0
	RIVER_THRESHOLD = BASE_RIVER_THRESHOLD * scale_factor
	CANYON_THRESHOLD = BASE_CANYON_THRESHOLD * scale_factor
	print("River thresholds scaled for %dx%d: river=%.0f, canyon=%.0f" % [g.width, g.height, RIVER_THRESHOLD, CANYON_THRESHOLD])

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

	# --- Phase 1: Compute flow direction and accumulation ---
	var flow_accumulation := PackedFloat32Array()
	flow_accumulation.resize(total)
	var flow_dir := PackedInt32Array()
	flow_dir.resize(total)
	flow_dir.fill(-1)

	for i in range(total):
		flow_accumulation[i] = 1.0 + maxf(moisture_map[i] if i < moisture_map.size() else 0.5, 0.0)

	# Sort tiles high-to-low so flow propagates downhill
	var sorted_indices: Array[int] = []
	sorted_indices.resize(total)
	for i in range(total):
		sorted_indices[i] = i
	sorted_indices.sort_custom(func(a: int, b: int) -> bool:
		return grid.get_height(a % w, int(float(a) / float(w))) > grid.get_height(b % w, int(float(b) / float(w)))
	)

	_lake_count = 0
	for idx in sorted_indices:
		var x := idx % w
		var y := int(float(idx) / float(w))
		var current_h := grid.get_height(x, y)

		if current_h <= GameConfig.SEA_LEVEL:
			continue

		var best_n := -1
		var best_h := current_h
		var lowest_n := -1
		var lowest_h := 999.0
		for neighbor in grid.get_neighbors_8(x, y):
			var nh := grid.get_height(neighbor.x, neighbor.y)
			if nh < best_h:
				best_h = nh
				best_n = neighbor.y * w + neighbor.x
			if nh < lowest_h:
				lowest_h = nh
				lowest_n = neighbor.y * w + neighbor.x

		if best_n < 0:
			# Pit fill: if no downhill neighbor, carve through the lowest rim
			if lowest_n >= 0 and flow_accumulation[idx] > 5.0:
				var lx := lowest_n % w
				var ly := int(float(lowest_n) / float(w))
				var spill_h := current_h - 0.001
				grid.set_height(lx, ly, minf(lowest_h, spill_h))
				best_n = lowest_n
			else:
				if flow_accumulation[idx] > 10.0:
					_lake_count += 1
				continue

		flow_dir[idx] = best_n
		flow_accumulation[best_n] += flow_accumulation[idx]

	# --- Phase 2: Trace continuous river paths from sources to ocean ---
	river_map.fill(0.0)
	_river_count = 0

	# Collect river source tiles (high flow accumulation above land)
	var sources: Array[int] = []
	for i in range(total):
		if flow_accumulation[i] >= RIVER_THRESHOLD:
			var ht := grid.get_height(i % w, int(float(i) / float(w)))
			if ht > GameConfig.SEA_LEVEL:
				sources.append(i)

	# Sort sources by flow descending — trace biggest rivers first
	sources.sort_custom(func(a: int, b: int) -> bool:
		return flow_accumulation[a] > flow_accumulation[b]
	)

	# Trace each source downstream until ocean or loop
	for src in sources:
		_trace_river_path(src, flow_dir, flow_accumulation, w)

	_smooth_river_map(w, h)

	flow_map = flow_accumulation
	_apply_moisture_boost(w, h)


func _smooth_river_map(w: int, h: int) -> void:
	var total := w * h
	if river_map.size() != total:
		return
	var tmp := PackedFloat32Array()
	tmp.resize(total)

	for i in range(total):
		tmp[i] = river_map[i]

	for _pass in range(2):
		for y in range(h):
			for x in range(w):
				var idx := y * w + x
				var s := tmp[idx]
				var max_n := s
				for n in grid.get_neighbors_4(x, y):
					var ni := n.y * w + n.x
					max_n = maxf(max_n, tmp[ni] * 0.85)
				river_map[idx] = maxf(river_map[idx], max_n)
		for i in range(total):
			tmp[i] = river_map[i]


func _trace_river_path(start_idx: int, flow_dir: PackedInt32Array, flow_acc: PackedFloat32Array, w: int) -> void:
	var idx := start_idx
	var max_steps := grid.width + grid.height
	var step := 0
	# Strength normalization scales with grid — bigger grid = higher flow values
	var strength_divisor := RIVER_THRESHOLD * 5.0

	while step < max_steps:
		step += 1
		var x := idx % w
		var y := int(float(idx) / float(w))
		var ht := grid.get_height(x, y)

		# Stop at ocean
		if ht <= GameConfig.SEA_LEVEL:
			break

		# Mark this tile as river with strength based on flow
		var flow := flow_acc[idx]
		var strength := clampf((flow - RIVER_THRESHOLD * 0.5) / strength_divisor, 0.1, 1.0)

		# If already marked with equal or stronger river, stop (merged into existing)
		if river_map[idx] >= strength:
			break

		river_map[idx] = maxf(river_map[idx], strength)
		_river_count += 1

		# Carve the river channel (divisors scale with threshold to stay consistent)
		var carve := BASE_CARVE_RATE * clampf(flow / (RIVER_THRESHOLD * 1.6), 0.5, 2.0)
		if flow >= CANYON_THRESHOLD:
			carve = CANYON_CARVE_RATE * clampf(flow / (CANYON_THRESHOLD * 1.0), 1.0, 3.0)
			_widen_canyon(x, y, clampf(flow / (CANYON_THRESHOLD * 2.0), 0.2, 0.5))
		grid.set_height(x, y, maxf(ht - carve, GameConfig.SEA_LEVEL + 0.001))

		# Follow flow direction downstream
		var next := flow_dir[idx]
		if next < 0 or next == idx:
			break
		idx = next


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

extends System
class_name SysCoastalErosion

var grid: TorusGrid = null
var wind_system: SysWind = null
var time_system: SysTime = null

var wave_erosion_rate: float = 0.002
var coastal_max_height: float = 0.1

var _game_hours_acc: float = 0.0
var _run_interval_hours: float = 12.0


func setup(g: TorusGrid, ws: SysWind, ts: SysTime) -> void:
	grid = g
	wind_system = ws
	time_system = ts


func update(_world: Node, delta: float) -> void:
	if grid == null or time_system == null:
		return

	_game_hours_acc += delta * GameConfig.TIME_SCALE / 60.0
	if _game_hours_acc < _run_interval_hours:
		return
	_game_hours_acc -= _run_interval_hours

	_run_batch()


func _run_batch() -> void:
	var w := grid.width
	var h := grid.height
	var eroded := 0
	var wind_speed := wind_system.speed if wind_system else 1.0

	for y in range(h):
		for x in range(w):
			var center_h := grid.get_height(x, y)
			if center_h <= GameConfig.SEA_LEVEL or center_h > coastal_max_height:
				continue

			var is_coastal := false
			for neighbor in grid.get_neighbors_4(x, y):
				if grid.get_tile_center_height(neighbor.x, neighbor.y) < GameConfig.SEA_LEVEL:
					is_coastal = true
					break

			if not is_coastal:
				continue

			var erosion := wave_erosion_rate * wind_speed
			grid.set_height(x, y, center_h - erosion)

			var deepest_neighbor := Vector2i(-1, -1)
			var deepest_h := 999.0
			for neighbor in grid.get_neighbors_4(x, y):
				var nh := grid.get_height(neighbor.x, neighbor.y)
				if nh < deepest_h:
					deepest_h = nh
					deepest_neighbor = neighbor

			if deepest_neighbor.x >= 0 and deepest_h < GameConfig.SEA_LEVEL:
				grid.set_height(deepest_neighbor.x, deepest_neighbor.y, deepest_h + erosion * 0.5)

			eroded += 1

	if eroded > 0:
		print("Coastal erosion: %d tiles eroded" % eroded)

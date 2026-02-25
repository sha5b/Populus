extends System
class_name SysThermalErosion

var grid: TorusGrid = null
var time_system: SysTime = null

var talus_angle: float = 0.3
var base_thermal_rate: float = 0.01
var thermal_rate: float = 0.01

var _game_hours_acc: float = 0.0
var _run_interval_hours: float = 6.0


func setup(g: TorusGrid, ts: SysTime) -> void:
	grid = g
	time_system = ts


func update(_world: Node, delta: float) -> void:
	if grid == null or time_system == null:
		return

	_game_hours_acc += delta * GameConfig.TIME_SCALE / 60.0
	if _game_hours_acc < _run_interval_hours:
		return
	_game_hours_acc -= _run_interval_hours

	_apply_season_modifiers()
	_run_batch()


func _run_batch() -> void:
	var w := grid.width
	var h := grid.height
	var transfers := 0

	for y in range(h):
		for x in range(w):
			var center_h := grid.get_height(x, y)
			if center_h <= GameConfig.SEA_LEVEL:
				continue

			for neighbor in grid.get_neighbors_4(x, y):
				var nx := neighbor.x
				var ny := neighbor.y
				var neighbor_h := grid.get_height(nx, ny)
				var diff := center_h - neighbor_h

				if diff > talus_angle:
					var transfer := (diff - talus_angle) * thermal_rate
					grid.set_height(x, y, grid.get_height(x, y) - transfer)
					grid.set_height(nx, ny, grid.get_height(nx, ny) + transfer)
					transfers += 1

	if transfers > 0:
		print("Thermal erosion: %d transfers" % transfers)


func _apply_season_modifiers() -> void:
	if time_system == null:
		thermal_rate = base_thermal_rate
		return

	var season := time_system.season
	match season:
		DefEnums.Season.WINTER:
			thermal_rate = base_thermal_rate * 2.5
		DefEnums.Season.SPRING:
			thermal_rate = base_thermal_rate * 1.8
		DefEnums.Season.AUTUMN:
			thermal_rate = base_thermal_rate * 1.3
		_:
			thermal_rate = base_thermal_rate * 0.8

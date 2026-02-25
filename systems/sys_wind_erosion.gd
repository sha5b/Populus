extends System
class_name SysWindErosion

var grid: TorusGrid = null
var wind_system: SysWind = null
var moisture_map: PackedFloat32Array

var wind_erosion_rate: float = 0.001
var moisture_threshold: float = 0.2

var _game_hours_acc: float = 0.0
var _run_interval_hours: float = 12.0


func setup(g: TorusGrid, ws: SysWind, moist: PackedFloat32Array) -> void:
	grid = g
	wind_system = ws
	moisture_map = moist


func update(_world: Node, delta: float) -> void:
	if grid == null or wind_system == null:
		return

	_game_hours_acc += delta * GameConfig.TIME_SCALE / 60.0
	if _game_hours_acc < _run_interval_hours:
		return
	_game_hours_acc -= _run_interval_hours

	_run_batch()


func _run_batch() -> void:
	var w := grid.width
	var h := grid.height
	var moved := 0
	var wind_dir := wind_system.direction
	var wind_spd := wind_system.speed

	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			if moisture_map.size() <= idx:
				continue
			if moisture_map[idx] >= moisture_threshold:
				continue

			var center_h := grid.get_height(x, y)
			if center_h <= GameConfig.SEA_LEVEL:
				continue

			var dryness := 1.0 - moisture_map[idx] / moisture_threshold
			var pickup := wind_erosion_rate * wind_spd * dryness

			grid.set_height(x, y, center_h - pickup)

			var deposit_x := grid.wrap_x(x + int(round(wind_dir.x)))
			var deposit_y := grid.wrap_y(y + int(round(wind_dir.y)))
			var deposit_h := grid.get_height(deposit_x, deposit_y)
			grid.set_height(deposit_x, deposit_y, deposit_h + pickup * 0.8)

			moved += 1

	if moved > 100:
		print("Wind erosion: %d tiles affected" % moved)

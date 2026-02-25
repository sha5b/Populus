extends System
class_name SysWindErosion

var grid: TorusGrid = null
var wind_system: SysWind = null
var weather_system: SysWeather = null
var moisture_map: PackedFloat32Array

var base_wind_erosion_rate: float = 0.001
var wind_erosion_rate: float = 0.001
var moisture_threshold: float = 0.2

var _game_hours_acc: float = 0.0
var _run_interval_hours: float = 12.0


func setup(g: TorusGrid, ws: SysWind, moist: PackedFloat32Array, wea: SysWeather = null) -> void:
	grid = g
	wind_system = ws
	moisture_map = moist
	weather_system = wea


func update(_world: Node, delta: float) -> void:
	if grid == null or wind_system == null:
		return

	_game_hours_acc += delta * GameConfig.TIME_SCALE / 60.0
	if _game_hours_acc < _run_interval_hours:
		return
	_game_hours_acc -= _run_interval_hours

	_apply_weather_modifiers()
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


func _apply_weather_modifiers() -> void:
	if weather_system == null:
		wind_erosion_rate = base_wind_erosion_rate
		return

	var state := weather_system.current_state
	match state:
		DefEnums.WeatherState.STORM:
			wind_erosion_rate = base_wind_erosion_rate * 3.0
		DefEnums.WeatherState.RAIN:
			wind_erosion_rate = base_wind_erosion_rate * 0.5
		_:
			wind_erosion_rate = base_wind_erosion_rate

extends System
class_name SysPrecipitation

var weather_system: SysWeather = null
var grid: TorusGrid = null
var moisture_map: PackedFloat32Array
var temperature_map: PackedFloat32Array

var _rain_rate: float = 0.001
var _storm_rate: float = 0.003
var _lightning_timer: float = 0.0
var _lightning_interval: float = 5.0


func setup(
	ws: SysWeather,
	g: TorusGrid,
	moist: PackedFloat32Array,
	temp: PackedFloat32Array
) -> void:
	weather_system = ws
	grid = g
	moisture_map = moist
	temperature_map = temp


func update(_world: Node, delta: float) -> void:
	if weather_system == null or grid == null:
		return

	var state := weather_system.current_state
	var game_delta := delta * GameConfig.TIME_SCALE

	if state == DefEnums.WeatherState.RAIN or state == DefEnums.WeatherState.STORM:
		var rate := _storm_rate if state == DefEnums.WeatherState.STORM else _rain_rate
		_apply_precipitation(game_delta, rate)

	if state == DefEnums.WeatherState.STORM:
		_lightning_timer += game_delta
		if _lightning_timer >= _lightning_interval:
			_lightning_timer -= _lightning_interval
			_lightning_strike()


func _apply_precipitation(game_delta: float, rate: float) -> void:
	var w := grid.width
	var h := grid.height
	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			if grid.get_tile_center_height(x, y) >= GameConfig.SEA_LEVEL:
				moisture_map[idx] = clampf(moisture_map[idx] + rate * game_delta, 0.0, 1.0)


func _lightning_strike() -> void:
	if grid == null:
		return
	var w := grid.width
	var h := grid.height
	var tx := randi() % w
	var ty := randi() % h

	if grid.get_tile_center_height(tx, ty) >= GameConfig.SEA_LEVEL:
		print("Lightning strike at (%d, %d)!" % [tx, ty])

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

const PATCH_SIZE := 16


func setup(g: TorusGrid, ws: SysWind, moist: PackedFloat32Array, wea: SysWeather = null) -> void:
	grid = g
	wind_system = ws
	moisture_map = moist
	weather_system = wea


func update(_world: Node, delta: float) -> void:
	if grid == null or wind_system == null:
		return
	_game_hours_acc += delta * GameConfig.TIME_SCALE / 60.0
	if _game_hours_acc >= _run_interval_hours:
		_game_hours_acc -= _run_interval_hours
		_apply_weather_modifiers()


func process_chunk(px: int, py: int, size: int) -> void:
	if grid == null:
		return
	_erode_patch(px, py, size)


func _erode_patch(px: int, py: int, size: int) -> void:
	var w := grid.width
	var wind_dir := wind_system.direction if wind_system else Vector2.RIGHT
	var wind_spd := wind_system.speed if wind_system else 1.0
	for dy in range(size):
		for dx in range(size):
			var x := grid.wrap_x(px + dx)
			var y := grid.wrap_y(py + dy)
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

			var sed_here := grid.get_sediment(x, y)
			if sed_here < pickup:
				var bedrock_erode := (pickup - sed_here) * 0.1 # Wind erodes bedrock extremely slowly
				grid.set_bedrock(x, y, grid.get_bedrock(x, y) - bedrock_erode)
				grid.set_sediment(x, y, 0.0)
				pickup = sed_here + bedrock_erode
			else:
				grid.set_sediment(x, y, sed_here - pickup)

			var deposit_x := grid.wrap_x(x + int(round(wind_dir.x)))
			var deposit_y := grid.wrap_y(y + int(round(wind_dir.y)))
			grid.set_sediment(deposit_x, deposit_y, grid.get_sediment(deposit_x, deposit_y) + pickup * 0.8)


func run_full_pass() -> void:
	for py in range(0, grid.height, PATCH_SIZE):
		for px in range(0, grid.width, PATCH_SIZE):
			_erode_patch(px, py, PATCH_SIZE)


func _apply_weather_modifiers() -> void:
	if weather_system == null:
		wind_erosion_rate = base_wind_erosion_rate
		return

	var state := weather_system.current_state
	match state:
		DefEnums.WeatherState.HURRICANE:
			wind_erosion_rate = base_wind_erosion_rate * 8.0
		DefEnums.WeatherState.BLIZZARD:
			wind_erosion_rate = base_wind_erosion_rate * 5.0
		DefEnums.WeatherState.STORM:
			wind_erosion_rate = base_wind_erosion_rate * 3.0
		DefEnums.WeatherState.HEATWAVE:
			wind_erosion_rate = base_wind_erosion_rate * 2.0
		DefEnums.WeatherState.RAIN:
			wind_erosion_rate = base_wind_erosion_rate * 0.5
		_:
			wind_erosion_rate = base_wind_erosion_rate

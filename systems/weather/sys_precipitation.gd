extends System
class_name SysPrecipitation

var weather_system: SysWeather = null
var grid: TorusGrid = null
var moisture_map: PackedFloat32Array
var temperature_map: PackedFloat32Array
var fire_spread: SysFireSpread = null

var _rain_rate: float = GameConfig.PRECIP_RAIN_RATE
var _storm_rate: float = GameConfig.PRECIP_STORM_RATE
var _timer: float = 0.0
var _chunk_offset: int = 0


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

	_timer += delta
	if _timer < GameConfig.PRECIP_TICK_INTERVAL:
		return
	_timer -= GameConfig.PRECIP_TICK_INTERVAL

	var state := weather_system.current_state

	var precip_states := [
		DefEnums.WeatherState.RAIN, DefEnums.WeatherState.STORM,
		DefEnums.WeatherState.SNOW, DefEnums.WeatherState.BLIZZARD,
		DefEnums.WeatherState.HURRICANE,
	]
	if state in precip_states:
		var rate := _rain_rate
		match state:
			DefEnums.WeatherState.HURRICANE:
				rate = _storm_rate * 2.0
			DefEnums.WeatherState.STORM:
				rate = _storm_rate
			DefEnums.WeatherState.BLIZZARD:
				rate = _rain_rate * 0.5
		_apply_precipitation_chunk(rate)

	# Evaporation during clear/hot weather
	if state == DefEnums.WeatherState.CLEAR or state == DefEnums.WeatherState.HEATWAVE:
		var evap_mult := GameConfig.PRECIP_HEATWAVE_EVAP_MULT if state == DefEnums.WeatherState.HEATWAVE else 1.0
		_apply_evaporation_chunk(evap_mult)


func _apply_precipitation_chunk(rate: float) -> void:
	var w := grid.width
	var total := w * grid.height
	var end_idx := mini(_chunk_offset + GameConfig.PRECIP_CHUNK_SIZE, total)

	for i in range(_chunk_offset, end_idx):
		var x := i % w
		var y := int(float(i) / float(w))
		if grid.get_height(x, y) >= GameConfig.SEA_LEVEL:
			moisture_map[i] = clampf(moisture_map[i] + rate * GameConfig.PRECIP_TICK_INTERVAL, 0.0, 1.0)

	_chunk_offset = end_idx if end_idx < total else 0


func _apply_evaporation_chunk(multiplier: float = 1.0) -> void:
	var w := grid.width
	var total := w * grid.height
	var end_idx := mini(_chunk_offset + GameConfig.PRECIP_CHUNK_SIZE, total)

	for i in range(_chunk_offset, end_idx):
		var temp := temperature_map[i] if i < temperature_map.size() else 0.5
		var evap_rate := GameConfig.PRECIP_EVAP_RATE_BASE * (0.5 + temp) * multiplier
		moisture_map[i] = maxf(moisture_map[i] - evap_rate * GameConfig.PRECIP_TICK_INTERVAL, 0.0)

	_chunk_offset = end_idx if end_idx < total else 0

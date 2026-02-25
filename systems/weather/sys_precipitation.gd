extends System
class_name SysPrecipitation

var weather_system: SysWeather = null
var grid: TorusGrid = null
var moisture_map: PackedFloat32Array
var temperature_map: PackedFloat32Array
var fire_spread: SysFireSpread = null

var _rain_rate: float = 0.001
var _storm_rate: float = 0.003
var _timer: float = 0.0
var _chunk_offset: int = 0

const TICK_INTERVAL := 2.0
const CHUNK_SIZE := 2048


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
	if _timer < TICK_INTERVAL:
		return
	_timer -= TICK_INTERVAL

	var state := weather_system.current_state

	if state == DefEnums.WeatherState.RAIN or state == DefEnums.WeatherState.STORM:
		var rate := _storm_rate if state == DefEnums.WeatherState.STORM else _rain_rate
		_apply_precipitation_chunk(rate)

	# Evaporation during clear/hot weather
	if state == DefEnums.WeatherState.CLEAR:
		_apply_evaporation_chunk()


func _apply_precipitation_chunk(rate: float) -> void:
	var w := grid.width
	var total := w * grid.height
	var end_idx := mini(_chunk_offset + CHUNK_SIZE, total)

	for i in range(_chunk_offset, end_idx):
		var x := i % w
		var y := i / w
		if grid.get_height(x, y) >= GameConfig.SEA_LEVEL:
			moisture_map[i] = clampf(moisture_map[i] + rate * TICK_INTERVAL, 0.0, 1.0)

	_chunk_offset = end_idx if end_idx < total else 0


func _apply_evaporation_chunk() -> void:
	var w := grid.width
	var total := w * grid.height
	var end_idx := mini(_chunk_offset + CHUNK_SIZE, total)

	for i in range(_chunk_offset, end_idx):
		var temp := temperature_map[i] if i < temperature_map.size() else 0.5
		var evap_rate := 0.0002 * (0.5 + temp)
		moisture_map[i] = maxf(moisture_map[i] - evap_rate * TICK_INTERVAL, 0.0)

	_chunk_offset = end_idx if end_idx < total else 0

extends System
class_name SysDiurnalTemperature

var time_system: SysTime = null
var weather_system: SysWeather = null
var grid: TorusGrid = null

var temperature_map: PackedFloat32Array
var base_temperature_map: PackedFloat32Array

var _timer: float = 0.0
var _chunk_offset: int = 0

const TICK_INTERVAL := GameConfig.DIURNAL_TICK_INTERVAL
const CHUNK_SIZE := GameConfig.DIURNAL_CHUNK_SIZE

const LAND_SWING := GameConfig.DIURNAL_LAND_SWING
const OCEAN_SWING := GameConfig.DIURNAL_OCEAN_SWING


func setup(
	ts: SysTime,
	ws: SysWeather,
	g: TorusGrid,
	temp: PackedFloat32Array,
	base_temp: PackedFloat32Array
) -> void:
	time_system = ts
	weather_system = ws
	grid = g
	temperature_map = temp
	base_temperature_map = base_temp


func update(_world: Node, delta: float) -> void:
	if time_system == null or grid == null:
		return
	if base_temperature_map.is_empty() or temperature_map.is_empty():
		return

	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer -= TICK_INTERVAL

	_apply_chunk()


func _apply_chunk() -> void:
	var w := grid.width
	var total := w * grid.height
	var end_idx := mini(_chunk_offset + CHUNK_SIZE, total)

	var sun_dir := Vector3(0, -1, 0)
	if time_system:
		sun_dir = time_system.sun_direction
	if sun_dir.length_squared() < 0.0001:
		sun_dir = Vector3(0, -1, 0)
	sun_dir = sun_dir.normalized()

	var season_offset: float = SysSeason.SEASON_TEMP_OFFSET.get(time_system.season, 0.0)
	var cloudiness := _get_cloudiness()
	var cloud_atten := 1.0 - cloudiness * 0.6

	for i in range(_chunk_offset, end_idx):
		var x := i % w
		var y := int(float(i) / float(w))

		var lon := (float(x) / float(w)) * TAU
		var lat := (float(y) / float(grid.height)) * PI - PI * 0.5
		var tile_dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)).normalized()

		# Incoming sunlight points along sun_dir (directional light rays).
		# Surface receives energy when facing against the ray direction.
		var insolation := maxf(tile_dir.dot(-sun_dir), 0.0)
		var diurnal := clampf(insolation * 2.0 - 1.0, -1.0, 1.0)

		var terrain_h := grid.get_height(x, y)
		var swing := OCEAN_SWING if terrain_h < GameConfig.SEA_LEVEL else LAND_SWING

		var base_temp := base_temperature_map[i] + season_offset
		var temp := base_temp + diurnal * swing * cloud_atten
		temperature_map[i] = clampf(temp, 0.0, 1.0)

	_chunk_offset = end_idx if end_idx < total else 0


func _get_cloudiness() -> float:
	if weather_system == null:
		return 0.0

	match weather_system.current_state:
		DefEnums.WeatherState.CLEAR:
			return 0.0
		DefEnums.WeatherState.CLOUDY:
			return 0.4
		DefEnums.WeatherState.FOG:
			return 0.35
		DefEnums.WeatherState.RAIN:
			return 0.6
		DefEnums.WeatherState.STORM:
			return 0.8
		DefEnums.WeatherState.SNOW:
			return 0.55
		DefEnums.WeatherState.BLIZZARD:
			return 0.9
		DefEnums.WeatherState.HURRICANE:
			return 0.85
		DefEnums.WeatherState.HEATWAVE:
			return 0.05
	return 0.0

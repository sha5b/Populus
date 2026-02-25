extends System
class_name SysWind

var direction: Vector2 = Vector2.RIGHT
var speed: float = 1.0

var weather_system: SysWeather = null

var _noise: FastNoiseLite
var _time_acc: float = 0.0


func _init() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.1
	_noise.seed = randi()


func update(_world: Node, delta: float) -> void:
	_time_acc += delta * GameConfig.TIME_SCALE * 0.01

	var angle := _noise.get_noise_1d(_time_acc) * TAU
	direction = Vector2(cos(angle), sin(angle))

	var base_speed := 1.0 + _noise.get_noise_1d(_time_acc + 100.0) * 0.5
	if weather_system:
		match weather_system.current_state:
			DefEnums.WeatherState.STORM:
				base_speed += 4.0
			DefEnums.WeatherState.RAIN:
				base_speed += 1.5
			DefEnums.WeatherState.CLOUDY:
				base_speed += 0.5

	speed = maxf(base_speed, 0.1)


func get_wind_string() -> String:
	var compass := _direction_to_compass()
	return "%s %.1f m/s" % [compass, speed]


func _direction_to_compass() -> String:
	var angle := atan2(direction.y, direction.x)
	if angle < 0:
		angle += TAU
	var idx := int(round(angle / (TAU / 8.0))) % 8
	var names := ["E", "NE", "N", "NW", "W", "SW", "S", "SE"]
	return names[idx]

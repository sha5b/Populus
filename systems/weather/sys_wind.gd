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
	_noise.frequency = GameConfig.WIND_NOISE_FREQUENCY
	_noise.seed = randi()


var _hurricane_angle: float = 0.0

func update(_world: Node, delta: float) -> void:
	_time_acc += delta * GameConfig.TIME_SCALE * GameConfig.WIND_TIME_ACC_SCALE

	var perturbation := _noise.get_noise_1d(_time_acc) * GameConfig.WIND_PERTURBATION_STRENGTH
	var base_angle := 0.0 + perturbation

	var base_speed := GameConfig.WIND_BASE_SPEED + _noise.get_noise_1d(_time_acc + 100.0) * GameConfig.WIND_BASE_SPEED_NOISE
	if weather_system:
		match weather_system.current_state:
			DefEnums.WeatherState.HURRICANE:
				# Hurricane: rotating wind that accelerates over time
				_hurricane_angle += delta * 2.5
				base_angle += _hurricane_angle
				base_speed += 8.0
				# Gusts
				base_speed += _noise.get_noise_1d(_time_acc * 5.0 + 200.0) * 3.0
			DefEnums.WeatherState.BLIZZARD:
				# Blizzard: strong, erratic wind with rapid direction shifts
				base_angle += _noise.get_noise_1d(_time_acc * 3.0 + 50.0) * 1.2
				base_speed += 5.0
				base_speed += absf(_noise.get_noise_1d(_time_acc * 4.0 + 300.0)) * 2.0
			DefEnums.WeatherState.STORM:
				base_speed += 3.0
			DefEnums.WeatherState.RAIN:
				base_speed += 1.0
			DefEnums.WeatherState.CLOUDY:
				base_speed += 0.3
			DefEnums.WeatherState.HEATWAVE:
				# Heatwave: very still air, occasional hot gusts
				base_speed *= 0.3
				base_speed += absf(_noise.get_noise_1d(_time_acc * 2.0 + 400.0)) * 0.5

	if weather_system and weather_system.current_state != DefEnums.WeatherState.HURRICANE:
		_hurricane_angle = 0.0

	direction = Vector2(cos(base_angle), sin(base_angle))
	speed = maxf(base_speed, GameConfig.WIND_MIN_SPEED)


func get_wind_at_latitude(lat_fraction: float) -> Vector2:
	var lat := (lat_fraction - 0.5) * 2.0
	var abs_lat := absf(lat)
	var band_dir: float
	var band_speed: float

	if abs_lat < 0.25:
		band_dir = -1.0
		band_speed = 0.8
	elif abs_lat < 0.5:
		band_dir = 1.0
		band_speed = 1.5
	elif abs_lat < 0.75:
		band_dir = 1.0
		band_speed = 1.0
	else:
		band_dir = -1.0
		band_speed = 0.5

	var meridional := 0.0
	if lat > 0:
		meridional = -0.2
	else:
		meridional = 0.2

	return Vector2(band_dir * band_speed, meridional) + direction * speed * 0.1


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

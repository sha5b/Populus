extends System
class_name SysWeatherVisuals

var weather_system: SysWeather = null
var wind_system: SysWind = null
var time_system: SysTime = null

var cloud_layer: PlanetCloudLayer = null
var atmosphere_shell: PlanetAtmosphere = null
var rain_particles: GPUParticles3D = null
var snow_particles: GPUParticles3D = null
var environment: Environment = null
var sun_light: DirectionalLight3D = null

var _target_coverage: float = 0.1
var _current_coverage: float = 0.1
var _target_fog_density: float = 0.0
var _current_fog_density: float = 0.0

var _lightning_timer: float = 0.0
var _lightning_interval: float = 5.0
var _lightning_flash_timer: float = 0.0
var _base_sun_energy: float = 0.0

const COVERAGE_MAP := {
	DefEnums.WeatherState.CLEAR: 0.1,
	DefEnums.WeatherState.CLOUDY: 0.5,
	DefEnums.WeatherState.RAIN: 0.7,
	DefEnums.WeatherState.STORM: 0.9,
	DefEnums.WeatherState.FOG: 0.3,
	DefEnums.WeatherState.SNOW: 0.6,
}

const FOG_MAP := {
	DefEnums.WeatherState.CLEAR: 0.0,
	DefEnums.WeatherState.CLOUDY: 0.0,
	DefEnums.WeatherState.RAIN: 0.002,
	DefEnums.WeatherState.STORM: 0.003,
	DefEnums.WeatherState.FOG: 0.008,
	DefEnums.WeatherState.SNOW: 0.002,
}


func update(_world: Node, delta: float) -> void:
	if weather_system == null:
		return

	var state := weather_system.current_state
	_target_coverage = COVERAGE_MAP.get(state, 0.1)
	_target_fog_density = FOG_MAP.get(state, 0.0)

	_current_coverage = lerpf(_current_coverage, _target_coverage, delta * 0.5)
	_current_fog_density = lerpf(_current_fog_density, _target_fog_density, delta * 0.3)

	_update_clouds(delta)
	_update_atmosphere()
	_update_fog()
	_update_particles(state)
	_update_lightning(state, delta)


func _update_clouds(delta: float) -> void:
	if cloud_layer == null:
		return
	cloud_layer.set_coverage(_current_coverage)

	if wind_system:
		cloud_layer.set_wind(wind_system.direction, wind_system.speed)

	var brightness := 1.0
	if time_system:
		var hour := float(time_system.hour)
		if hour >= 7.0 and hour < 18.0:
			brightness = 1.0
		elif hour >= 5.0 and hour < 7.0:
			brightness = lerpf(0.3, 1.0, (hour - 5.0) / 2.0)
		elif hour >= 18.0 and hour < 20.0:
			brightness = lerpf(1.0, 0.3, (hour - 18.0) / 2.0)
		else:
			brightness = 0.3
	cloud_layer.set_brightness(brightness)


func _update_atmosphere() -> void:
	if atmosphere_shell == null or time_system == null:
		return
	atmosphere_shell.set_time_of_day(float(time_system.hour))
	var density := 1.0
	if weather_system.current_state == DefEnums.WeatherState.FOG:
		density = 1.5
	elif weather_system.current_state == DefEnums.WeatherState.RAIN:
		density = 1.2
	atmosphere_shell.set_density(density)


func _update_fog() -> void:
	if environment == null:
		return
	environment.fog_enabled = _current_fog_density > 0.0005
	if environment.fog_enabled:
		environment.fog_density = _current_fog_density


func _update_particles(state: int) -> void:
	var is_raining := state == DefEnums.WeatherState.RAIN or state == DefEnums.WeatherState.STORM
	var is_cold := false
	if time_system:
		is_cold = time_system.season == DefEnums.Season.WINTER

	if rain_particles:
		rain_particles.emitting = is_raining and not is_cold
		if state == DefEnums.WeatherState.STORM and rain_particles.emitting:
			rain_particles.amount = 2000
		elif rain_particles.emitting:
			rain_particles.amount = 500

	if snow_particles:
		snow_particles.emitting = is_raining and is_cold


func _update_lightning(state: int, delta: float) -> void:
	if state != DefEnums.WeatherState.STORM:
		_lightning_timer = 0.0
		return

	_lightning_timer += delta
	if _lightning_timer >= _lightning_interval:
		_lightning_timer = 0.0
		_lightning_interval = randf_range(3.0, 10.0)
		_trigger_flash()

	if _lightning_flash_timer > 0.0:
		_lightning_flash_timer -= delta
		if sun_light and _base_sun_energy > 0.0:
			var flash_intensity := _lightning_flash_timer / 0.2
			sun_light.light_energy = _base_sun_energy + flash_intensity * 3.0
			if _lightning_flash_timer <= 0.0:
				_lightning_flash_timer = 0.0


func _trigger_flash() -> void:
	_lightning_flash_timer = 0.2
	if sun_light:
		_base_sun_energy = sun_light.light_energy

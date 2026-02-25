extends System
class_name SysWeatherVisuals

var weather_system: SysWeather = null
var wind_system: SysWind = null
var time_system: SysTime = null

var cloud_layer: PlanetCloudLayer = null
var atmosphere_shell: PlanetAtmosphere = null
var planet_rain: PlanetRain = null
var atmo_grid: AtmosphereGrid = null
var sun_light: DirectionalLight3D = null

var _lightning_timer: float = 0.0
var _lightning_interval: float = 8.0
var _lightning_flash_timer: float = 0.0

const COVERAGE_MAP := {
	DefEnums.WeatherState.CLEAR: 0.0,
	DefEnums.WeatherState.CLOUDY: 0.4,
	DefEnums.WeatherState.RAIN: 0.6,
	DefEnums.WeatherState.STORM: 0.8,
	DefEnums.WeatherState.FOG: 0.15,
	DefEnums.WeatherState.SNOW: 0.5,
	DefEnums.WeatherState.BLIZZARD: 0.95,
	DefEnums.WeatherState.HURRICANE: 0.9,
	DefEnums.WeatherState.HEATWAVE: 0.05,
}


func update(_world: Node, delta: float) -> void:
	if weather_system == null:
		return

	var state := weather_system.current_state
	_update_clouds(delta, state)
	_update_rain(state)
	_update_lightning(state, delta)


func _update_clouds(delta: float, state: int) -> void:
	if cloud_layer == null:
		return

	var coverage: float = COVERAGE_MAP.get(state, 0.0)
	cloud_layer.set_global_coverage(coverage)

	# Cloud darkness: storms/hurricanes get dark menacing clouds
	var darkness := 0.0
	match state:
		DefEnums.WeatherState.HURRICANE:
			darkness = 0.75
		DefEnums.WeatherState.BLIZZARD:
			darkness = 0.55
		DefEnums.WeatherState.STORM:
			darkness = 0.5
		DefEnums.WeatherState.RAIN:
			darkness = 0.25
	cloud_layer.set_weather_darkness(darkness)

	var wind_dir := Vector2.RIGHT
	var wind_speed := 1.0
	if wind_system:
		wind_dir = wind_system.direction
		wind_speed = wind_system.speed

	if atmo_grid:
		atmo_grid.advance_wind(delta, wind_dir, wind_speed)

	cloud_layer.update_clouds_rolling(delta)
	cloud_layer.update_wind_drift(delta, wind_dir, wind_speed)


func _update_rain(state: int) -> void:
	if planet_rain == null:
		return

	var is_precip := state in [
		DefEnums.WeatherState.RAIN, DefEnums.WeatherState.STORM,
		DefEnums.WeatherState.SNOW, DefEnums.WeatherState.BLIZZARD,
		DefEnums.WeatherState.HURRICANE,
	]
	var is_cold := false
	if time_system:
		is_cold = time_system.season == DefEnums.Season.WINTER

	var is_snow := is_cold or state == DefEnums.WeatherState.SNOW or state == DefEnums.WeatherState.BLIZZARD

	if is_precip:
		planet_rain.set_raining(true, is_snow)
		var is_intense := state in [DefEnums.WeatherState.STORM, DefEnums.WeatherState.HURRICANE, DefEnums.WeatherState.BLIZZARD]
		planet_rain.set_storm(is_intense)
	else:
		planet_rain.set_raining(false)

	var show_fog := state in [
		DefEnums.WeatherState.FOG, DefEnums.WeatherState.RAIN,
		DefEnums.WeatherState.STORM, DefEnums.WeatherState.BLIZZARD,
		DefEnums.WeatherState.HURRICANE,
	]
	planet_rain.set_fog(show_fog)
	planet_rain.update_positions()


func _update_lightning(state: int, delta: float) -> void:
	if _lightning_flash_timer > 0.0:
		_lightning_flash_timer -= delta
		if sun_light:
			# Read current day/night energy from time system, add flash on top
			var base_energy := 1.2
			if time_system:
				base_energy = time_system.day_night_energy
			var flash_boost := maxf(_lightning_flash_timer / 0.15, 0.0) * 3.0
			if state == DefEnums.WeatherState.HURRICANE:
				flash_boost *= 2.0
			sun_light.light_energy = base_energy + flash_boost

	var has_lightning := state in [DefEnums.WeatherState.STORM, DefEnums.WeatherState.HURRICANE, DefEnums.WeatherState.BLIZZARD]
	if not has_lightning:
		_lightning_timer = 0.0
		return

	_lightning_timer += delta

	# Hurricane: frequent lightning. Blizzard: rare thundersnow. Storm: normal.
	var interval_min := 3.0
	var interval_max := 8.0
	match state:
		DefEnums.WeatherState.HURRICANE:
			interval_min = 1.0
			interval_max = 4.0
		DefEnums.WeatherState.BLIZZARD:
			interval_min = 6.0
			interval_max = 15.0

	if _lightning_timer >= _lightning_interval:
		_lightning_timer = 0.0
		_lightning_interval = randf_range(interval_min, interval_max)
		_lightning_flash_timer = 0.25
		if planet_rain:
			planet_rain.trigger_lightning()

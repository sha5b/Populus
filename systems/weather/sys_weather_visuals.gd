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
var _base_sun_energy: float = 1.2
var _cloud_rebuild_timer: float = 0.0
const CLOUD_REBUILD_INTERVAL := 0.25

const COVERAGE_MAP := {
	DefEnums.WeatherState.CLEAR: 0.0,
	DefEnums.WeatherState.CLOUDY: 0.4,
	DefEnums.WeatherState.RAIN: 0.6,
	DefEnums.WeatherState.STORM: 0.8,
	DefEnums.WeatherState.FOG: 0.15,
	DefEnums.WeatherState.SNOW: 0.5,
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

	var wind_dir := Vector2.RIGHT
	var wind_speed := 1.0
	if wind_system:
		wind_dir = wind_system.direction
		wind_speed = wind_system.speed

	if atmo_grid:
		atmo_grid.advance_wind(delta, wind_dir, wind_speed)

	_cloud_rebuild_timer += delta
	if _cloud_rebuild_timer >= CLOUD_REBUILD_INTERVAL:
		cloud_layer.update_clouds_rolling(_cloud_rebuild_timer)
		_cloud_rebuild_timer = 0.0
	cloud_layer.update_wind_drift(delta, wind_dir, wind_speed)


func _update_rain(state: int) -> void:
	if planet_rain == null:
		return

	var is_precip := state == DefEnums.WeatherState.RAIN or state == DefEnums.WeatherState.STORM or state == DefEnums.WeatherState.SNOW
	var is_cold := false
	if time_system:
		is_cold = time_system.season == DefEnums.Season.WINTER

	if is_precip or (state == DefEnums.WeatherState.SNOW):
		planet_rain.set_raining(true, is_cold or state == DefEnums.WeatherState.SNOW)
		planet_rain.set_storm(state == DefEnums.WeatherState.STORM)
	else:
		planet_rain.set_raining(false)

	var show_fog := state == DefEnums.WeatherState.FOG or state == DefEnums.WeatherState.RAIN or state == DefEnums.WeatherState.STORM
	planet_rain.set_fog(show_fog)
	planet_rain.update_positions()


func _update_lightning(state: int, delta: float) -> void:
	if _lightning_flash_timer > 0.0:
		_lightning_flash_timer -= delta
		if sun_light:
			var flash_boost := maxf(_lightning_flash_timer / 0.15, 0.0) * 3.0
			sun_light.light_energy += flash_boost

	if state != DefEnums.WeatherState.STORM:
		_lightning_timer = 0.0
		return

	_lightning_timer += delta
	if _lightning_timer >= _lightning_interval:
		_lightning_timer = 0.0
		_lightning_interval = randf_range(3.0, 8.0)
		_lightning_flash_timer = 0.25
		if planet_rain:
			planet_rain.trigger_lightning()

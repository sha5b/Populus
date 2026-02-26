extends System
class_name SysTime

var game_time: float = 0.0
var hour: int = 6
var day: int = 0
var season: int = DefEnums.Season.SPRING
var year: int = 0

var _prev_hour: int = 6
var _prev_day: int = 0
var _prev_season: int = DefEnums.Season.SPRING

var sun_light: DirectionalLight3D = null
var day_night_energy: float = 1.2
var sun_direction: Vector3 = Vector3(0, -1, 0)
var is_night: bool = false


func update(world: Node, delta: float) -> void:
	game_time += delta * GameConfig.TIME_SCALE

	var total_hours := int(game_time / 60.0)
	hour = total_hours % GameConfig.HOURS_PER_DAY
	day = int(total_hours / GameConfig.HOURS_PER_DAY)
	var season_index := int(day / GameConfig.DAYS_PER_SEASON) % GameConfig.SEASONS_PER_YEAR
	season = season_index
	year = int(day / (GameConfig.DAYS_PER_SEASON * GameConfig.SEASONS_PER_YEAR))

	if hour != _prev_hour:
		_prev_hour = hour

	if day != _prev_day:
		_prev_day = day

	if season != _prev_season:
		var old_name := _season_name(_prev_season)
		var new_name := _season_name(season)
		print("Season changed: %s -> %s (Year %d)" % [old_name, new_name, year])
		_prev_season = season

	_update_day_night()


func _update_day_night() -> void:
	if sun_light == null:
		return

	var hour_frac := float(hour) + fmod(game_time / 60.0, 1.0)
	var days_per_year := float(GameConfig.DAYS_PER_SEASON * GameConfig.SEASONS_PER_YEAR)
	var day_of_year := float(day % int(days_per_year))
	var year_phase := (day_of_year / days_per_year) * TAU

	# Sun elevation: 0h = nadir (-90°), 6h = horizon (0°), 12h = zenith (90°), 18h = horizon (0°)
	# Maps 0-24h to a full rotation on X axis
	var elevation_deg := (hour_frac / 24.0) * 360.0 - 90.0
	var axial_tilt_deg := 23.0
	var seasonal_declination_deg := axial_tilt_deg * sin(year_phase)
	sun_light.rotation_degrees = Vector3(elevation_deg, 30.0, seasonal_declination_deg)

	# Dawn/dusk coloring, night dimming
	var day_t := 0.0
	if hour_frac > 6.0 and hour_frac < 7.0:
		day_t = (hour_frac - 6.0)
	elif hour_frac >= 7.0 and hour_frac <= 19.0:
		day_t = 1.0
	elif hour_frac > 19.0 and hour_frac < 20.0:
		day_t = 1.0 - (hour_frac - 19.0)

	day_night_energy = 1.2
	sun_light.light_energy = 1.2

	sun_direction = -sun_light.global_transform.basis.z
	is_night = day_t <= 0.001

	sun_light.light_color = Color(1.0, 0.98, 0.95)


func _season_name(s: int) -> String:
	match s:
		DefEnums.Season.SPRING: return "Spring"
		DefEnums.Season.SUMMER: return "Summer"
		DefEnums.Season.AUTUMN: return "Autumn"
		DefEnums.Season.WINTER: return "Winter"
	return "Unknown"


func get_time_string() -> String:
	return "Day %d, %02d:00, %s, Year %d" % [day, hour, _season_name(season), year]

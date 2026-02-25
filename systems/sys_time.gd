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


func update(world: Node, delta: float) -> void:
	game_time += delta * GameConfig.TIME_SCALE

	var total_hours := int(game_time / 60.0)
	hour = total_hours % GameConfig.HOURS_PER_DAY
	day = total_hours / GameConfig.HOURS_PER_DAY
	var season_index := (day / GameConfig.DAYS_PER_SEASON) % GameConfig.SEASONS_PER_YEAR
	season = season_index
	year = day / (GameConfig.DAYS_PER_SEASON * GameConfig.SEASONS_PER_YEAR)

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
	var sun_angle := (hour_frac / 24.0) * 360.0 - 90.0
	sun_light.rotation_degrees.x = sun_angle

	var intensity: float
	var color: Color

	if hour_frac >= 7.0 and hour_frac < 18.0:
		intensity = 1.2
		color = Color(1.0, 0.98, 0.95)
	elif hour_frac >= 5.0 and hour_frac < 7.0:
		var t := (hour_frac - 5.0) / 2.0
		intensity = lerpf(0.15, 1.2, t)
		color = Color(1.0, 0.6, 0.3).lerp(Color(1.0, 0.98, 0.95), t)
	elif hour_frac >= 18.0 and hour_frac < 20.0:
		var t := (hour_frac - 18.0) / 2.0
		intensity = lerpf(1.2, 0.15, t)
		color = Color(1.0, 0.98, 0.95).lerp(Color(0.3, 0.3, 0.6), t)
	else:
		intensity = 0.15
		color = Color(0.2, 0.2, 0.4)

	sun_light.light_energy = intensity
	sun_light.light_color = color


func _season_name(s: int) -> String:
	match s:
		DefEnums.Season.SPRING: return "Spring"
		DefEnums.Season.SUMMER: return "Summer"
		DefEnums.Season.AUTUMN: return "Autumn"
		DefEnums.Season.WINTER: return "Winter"
	return "Unknown"


func get_time_string() -> String:
	return "Day %d, %02d:00, %s, Year %d" % [day, hour, _season_name(season), year]

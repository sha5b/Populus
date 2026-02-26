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
var moon_light: DirectionalLight3D = null
var environment: Environment = null
var day_night_energy: float = 1.2
var sun_direction: Vector3 = Vector3(0, -1, 0)
var is_night: bool = false


func update(_world: Node, delta: float) -> void:
	game_time += delta * GameConfig.TIME_SCALE

	var total_hours := int(game_time / 60.0)
	hour = total_hours % GameConfig.HOURS_PER_DAY
	day = int(float(total_hours) / float(GameConfig.HOURS_PER_DAY))
	var season_index := int(float(day) / float(GameConfig.DAYS_PER_SEASON)) % GameConfig.SEASONS_PER_YEAR
	season = season_index
	year = int(float(day) / float(GameConfig.DAYS_PER_SEASON * GameConfig.SEASONS_PER_YEAR))

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
	var sun_elevation_deg := (hour_frac / 24.0) * 360.0 - 90.0
	var axial_tilt_deg := 23.0
	var seasonal_declination_deg := axial_tilt_deg * sin(year_phase)
	sun_light.rotation_degrees = Vector3(sun_elevation_deg, 30.0, seasonal_declination_deg)
	
	if moon_light:
		# Moon is opposite to the sun (simple implementation for now)
		var moon_elevation_deg := sun_elevation_deg + 180.0
		moon_light.rotation_degrees = Vector3(moon_elevation_deg, 30.0, -seasonal_declination_deg)

	# Dawn/dusk coloring, night dimming
	var day_t := 0.0
	if hour_frac > 5.5 and hour_frac < 7.0: # Dawn
		day_t = (hour_frac - 5.5) / 1.5
	elif hour_frac >= 7.0 and hour_frac <= 17.5: # Day
		day_t = 1.0
	elif hour_frac > 17.5 and hour_frac < 19.0: # Dusk
		day_t = 1.0 - ((hour_frac - 17.5) / 1.5)
		
	# Smooth easing
	day_t = smoothstep(0.0, 1.0, day_t)

	day_night_energy = lerpf(0.01, 1.2, day_t)
	sun_light.light_energy = day_night_energy
	
	if moon_light:
		var moon_energy := lerpf(0.05, 0.0, day_t)
		moon_light.light_energy = moon_energy

	sun_direction = -sun_light.global_transform.basis.z
	is_night = day_t <= 0.01
	
	# Color variations
	var dusk_dawn_color := Color(1.0, 0.6, 0.3)
	var noon_color := Color(1.0, 0.98, 0.95)
	
	var color_t := 1.0
	if hour_frac > 5.5 and hour_frac < 8.0:
		color_t = (hour_frac - 5.5) / 2.5
	elif hour_frac > 16.5 and hour_frac < 19.0:
		color_t = 1.0 - ((hour_frac - 16.5) / 2.5)
	
	color_t = smoothstep(0.0, 1.0, color_t)
	sun_light.light_color = dusk_dawn_color.lerp(noon_color, color_t)
	
	if environment:
		var day_ambient := Color(0.15, 0.15, 0.2)
		var night_ambient := Color(0.02, 0.03, 0.06)
		environment.ambient_light_color = night_ambient.lerp(day_ambient, day_t)
		
		var day_bg := Color(0.02, 0.02, 0.05)
		var night_bg := Color(0.005, 0.005, 0.01)
		environment.background_color = night_bg.lerp(day_bg, day_t)


func _season_name(s: int) -> String:
	match s:
		DefEnums.Season.SPRING: return "Spring"
		DefEnums.Season.SUMMER: return "Summer"
		DefEnums.Season.AUTUMN: return "Autumn"
		DefEnums.Season.WINTER: return "Winter"
	return "Unknown"


func get_time_string() -> String:
	return "Day %d, %02d:00, %s, Year %d" % [day, hour, _season_name(season), year]

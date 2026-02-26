extends System
class_name SysWeather

var current_state: int = DefEnums.WeatherState.RAIN
var time_system: SysTime = null

var grid: TorusGrid = null
var temperature_map: PackedFloat32Array
var moisture_map: PackedFloat32Array

var _climate_sample_offset: int = 0

var _transition_timer: float = 0.0
var _next_check: float = GameConfig.WEATHER_INITIAL_CHECK

const TRANSITION_TABLE := {
	DefEnums.WeatherState.CLEAR: {
		DefEnums.WeatherState.CLOUDY: 0.40,
		DefEnums.WeatherState.FOG: 0.08,
		DefEnums.WeatherState.HEATWAVE: 0.06,
	},
	DefEnums.WeatherState.CLOUDY: {
		DefEnums.WeatherState.CLEAR: 0.2,
		DefEnums.WeatherState.RAIN: 0.45,
		DefEnums.WeatherState.FOG: 0.08,
	},
	DefEnums.WeatherState.RAIN: {
		DefEnums.WeatherState.STORM: 0.3,
		DefEnums.WeatherState.CLOUDY: 0.25,
		DefEnums.WeatherState.SNOW: 0.1,
	},
	DefEnums.WeatherState.STORM: {
		DefEnums.WeatherState.RAIN: 0.35,
		DefEnums.WeatherState.CLOUDY: 0.2,
		DefEnums.WeatherState.HURRICANE: 0.12,
		DefEnums.WeatherState.BLIZZARD: 0.08,
	},
	DefEnums.WeatherState.SNOW: {
		DefEnums.WeatherState.CLOUDY: 0.3,
		DefEnums.WeatherState.CLEAR: 0.15,
		DefEnums.WeatherState.BLIZZARD: 0.15,
	},
	DefEnums.WeatherState.FOG: {
		DefEnums.WeatherState.CLEAR: 0.3,
		DefEnums.WeatherState.CLOUDY: 0.4,
		DefEnums.WeatherState.RAIN: 0.1,
	},
	DefEnums.WeatherState.BLIZZARD: {
		DefEnums.WeatherState.SNOW: 0.4,
		DefEnums.WeatherState.STORM: 0.2,
		DefEnums.WeatherState.CLOUDY: 0.15,
	},
	DefEnums.WeatherState.HURRICANE: {
		DefEnums.WeatherState.STORM: 0.45,
		DefEnums.WeatherState.RAIN: 0.25,
		DefEnums.WeatherState.CLOUDY: 0.1,
	},
	DefEnums.WeatherState.HEATWAVE: {
		DefEnums.WeatherState.CLEAR: 0.3,
		DefEnums.WeatherState.CLOUDY: 0.25,
		DefEnums.WeatherState.STORM: 0.15,
	},
}

const SEASON_RAIN_BONUS := {
	DefEnums.Season.SPRING: 0.15,
	DefEnums.Season.SUMMER: -0.1,
	DefEnums.Season.AUTUMN: 0.05,
	DefEnums.Season.WINTER: 0.0,
}


func setup(ts: SysTime, g: TorusGrid, temp: PackedFloat32Array, moist: PackedFloat32Array) -> void:
	time_system = ts
	grid = g
	temperature_map = temp
	moisture_map = moist


func update(_world: Node, delta: float) -> void:
	_transition_timer += delta * GameConfig.TIME_SCALE
	if _transition_timer < _next_check:
		return
	_transition_timer = 0.0
	_next_check = randf_range(GameConfig.WEATHER_CHECK_MIN, GameConfig.WEATHER_CHECK_MAX)
	_try_transition()


func _try_transition() -> void:
	if not TRANSITION_TABLE.has(current_state):
		return

	var transitions: Dictionary = TRANSITION_TABLE[current_state]
	var climate := _sample_global_climate()
	var avg_temp: float = climate["avg_temp"]
	var avg_moist: float = climate["avg_moist"]
	var is_night := _is_night()
	var night_factor := 1.0 if is_night else 0.0

	var season_bonus: float = 0.0
	if time_system:
		season_bonus = SEASON_RAIN_BONUS.get(time_system.season, 0.0)

	var roll := randf()
	var cumulative := 0.0

	var is_winter := time_system and time_system.season == DefEnums.Season.WINTER
	var is_summer := time_system and time_system.season == DefEnums.Season.SUMMER
	var is_dry := avg_moist < 0.45
	var is_moist := avg_moist > 0.55
	var is_hot := avg_temp > 0.65
	var is_cold := avg_temp < 0.35

	for target_state in transitions.keys():
		var prob: float = transitions[target_state]
		if target_state == DefEnums.WeatherState.RAIN or target_state == DefEnums.WeatherState.STORM:
			prob += season_bonus
			prob += (avg_moist - 0.5) * 0.25
			prob += night_factor * 0.03
		# Blizzard more likely in winter
		if target_state == DefEnums.WeatherState.BLIZZARD:
			prob += 0.10 if is_winter else -0.04
			prob += 0.12 if is_cold else -0.02
			prob += night_factor * 0.02
		# Hurricane more likely in summer
		if target_state == DefEnums.WeatherState.HURRICANE:
			prob += 0.08 if is_summer else -0.04
			prob += 0.10 if (is_hot and is_moist) else -0.03
		# Heatwave more likely in summer
		if target_state == DefEnums.WeatherState.HEATWAVE:
			prob += 0.10 if is_summer else -0.03
			prob += 0.12 if (is_hot and is_dry) else -0.04
		# Snow more likely in winter
		if target_state == DefEnums.WeatherState.SNOW:
			prob += 0.10 if is_winter else 0.0
			prob += 0.10 if is_cold else -0.02
		# Fog prefers moist, cool nights
		if target_state == DefEnums.WeatherState.FOG:
			prob += night_factor * 0.06
			prob += (avg_moist - 0.5) * 0.12
			prob += 0.05 if (avg_temp < 0.55) else -0.02
		cumulative += maxf(prob, 0.0)
		if roll < cumulative:
			var old_name := _state_name(current_state)
			current_state = target_state
			var new_name := _state_name(current_state)
			print("Weather changed: %s -> %s" % [old_name, new_name])
			return


func _is_night() -> bool:
	if time_system == null:
		return false
	return time_system.is_night


func _sample_global_climate() -> Dictionary:
	if grid == null:
		return {"avg_temp": 0.5, "avg_moist": 0.5}
	var w := grid.width
	var total := w * grid.height
	if total <= 0:
		return {"avg_temp": 0.5, "avg_moist": 0.5}
	if temperature_map.is_empty() or moisture_map.is_empty():
		return {"avg_temp": 0.5, "avg_moist": 0.5}

	var samples := mini(GameConfig.WEATHER_CLIMATE_SAMPLE_COUNT, total)
	var step := maxi(int(float(total) / float(samples)), 1)
	_climate_sample_offset = (_climate_sample_offset + 7919) % step

	var sum_t := 0.0
	var sum_m := 0.0
	var count := 0
	var idx := _climate_sample_offset

	while idx < total and count < samples:
		sum_t += temperature_map[idx]
		sum_m += moisture_map[idx]
		count += 1
		idx += step

	if count <= 0:
		return {"avg_temp": 0.5, "avg_moist": 0.5}
	return {"avg_temp": sum_t / float(count), "avg_moist": sum_m / float(count)}


func _state_name(s: int) -> String:
	match s:
		DefEnums.WeatherState.CLEAR: return "Clear"
		DefEnums.WeatherState.CLOUDY: return "Cloudy"
		DefEnums.WeatherState.RAIN: return "Rain"
		DefEnums.WeatherState.STORM: return "Storm"
		DefEnums.WeatherState.SNOW: return "Snow"
		DefEnums.WeatherState.FOG: return "Fog"
		DefEnums.WeatherState.BLIZZARD: return "Blizzard"
		DefEnums.WeatherState.HURRICANE: return "Hurricane"
		DefEnums.WeatherState.HEATWAVE: return "Heatwave"
	return "Unknown"


func is_extreme() -> bool:
	return current_state in [DefEnums.WeatherState.BLIZZARD, DefEnums.WeatherState.HURRICANE, DefEnums.WeatherState.HEATWAVE]


func is_precipitation() -> bool:
	return current_state in [DefEnums.WeatherState.RAIN, DefEnums.WeatherState.STORM, DefEnums.WeatherState.SNOW, DefEnums.WeatherState.BLIZZARD, DefEnums.WeatherState.HURRICANE]


func is_stormy() -> bool:
	return current_state in [DefEnums.WeatherState.STORM, DefEnums.WeatherState.BLIZZARD, DefEnums.WeatherState.HURRICANE]


func get_state_string() -> String:
	return _state_name(current_state)

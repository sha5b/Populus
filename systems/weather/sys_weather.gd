extends System
class_name SysWeather

var current_state: int = DefEnums.WeatherState.CLEAR
var time_system: SysTime = null

var _transition_timer: float = 0.0
var _next_check: float = 40.0

const TRANSITION_TABLE := {
	DefEnums.WeatherState.CLEAR: {
		DefEnums.WeatherState.CLOUDY: 0.45,
		DefEnums.WeatherState.FOG: 0.08,
	},
	DefEnums.WeatherState.CLOUDY: {
		DefEnums.WeatherState.CLEAR: 0.2,
		DefEnums.WeatherState.RAIN: 0.5,
		DefEnums.WeatherState.FOG: 0.08,
	},
	DefEnums.WeatherState.RAIN: {
		DefEnums.WeatherState.STORM: 0.3,
		DefEnums.WeatherState.CLOUDY: 0.3,
		DefEnums.WeatherState.SNOW: 0.1,
	},
	DefEnums.WeatherState.STORM: {
		DefEnums.WeatherState.RAIN: 0.5,
		DefEnums.WeatherState.CLOUDY: 0.3,
	},
	DefEnums.WeatherState.SNOW: {
		DefEnums.WeatherState.CLOUDY: 0.4,
		DefEnums.WeatherState.CLEAR: 0.2,
	},
	DefEnums.WeatherState.FOG: {
		DefEnums.WeatherState.CLEAR: 0.3,
		DefEnums.WeatherState.CLOUDY: 0.4,
		DefEnums.WeatherState.RAIN: 0.1,
	},
}

const SEASON_RAIN_BONUS := {
	DefEnums.Season.SPRING: 0.15,
	DefEnums.Season.SUMMER: -0.1,
	DefEnums.Season.AUTUMN: 0.05,
	DefEnums.Season.WINTER: 0.0,
}


func update(_world: Node, delta: float) -> void:
	_transition_timer += delta * GameConfig.TIME_SCALE
	if _transition_timer < _next_check:
		return
	_transition_timer = 0.0
	_next_check = randf_range(40.0, 100.0)
	_try_transition()


func _try_transition() -> void:
	if not TRANSITION_TABLE.has(current_state):
		return

	var transitions: Dictionary = TRANSITION_TABLE[current_state]
	var season_bonus: float = 0.0
	if time_system:
		season_bonus = SEASON_RAIN_BONUS.get(time_system.season, 0.0)

	var roll := randf()
	var cumulative := 0.0

	for target_state in transitions.keys():
		var prob: float = transitions[target_state]
		if target_state == DefEnums.WeatherState.RAIN or target_state == DefEnums.WeatherState.STORM:
			prob += season_bonus
		cumulative += maxf(prob, 0.0)
		if roll < cumulative:
			var old_name := _state_name(current_state)
			current_state = target_state
			var new_name := _state_name(current_state)
			print("Weather changed: %s -> %s" % [old_name, new_name])
			return


func _state_name(s: int) -> String:
	match s:
		DefEnums.WeatherState.CLEAR: return "Clear"
		DefEnums.WeatherState.CLOUDY: return "Cloudy"
		DefEnums.WeatherState.RAIN: return "Rain"
		DefEnums.WeatherState.STORM: return "Storm"
		DefEnums.WeatherState.SNOW: return "Snow"
		DefEnums.WeatherState.FOG: return "Fog"
	return "Unknown"


func get_state_string() -> String:
	return _state_name(current_state)

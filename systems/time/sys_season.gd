extends System
class_name SysSeason

var time_system: SysTime = null
var temperature_map: PackedFloat32Array
var moisture_map: PackedFloat32Array
var base_temperature_map: PackedFloat32Array
var base_moisture_map: PackedFloat32Array

var _last_season: int = -1

const SEASON_TEMP_OFFSET := {
	DefEnums.Season.SPRING: 0.0,
	DefEnums.Season.SUMMER: 0.15,
	DefEnums.Season.AUTUMN: -0.05,
	DefEnums.Season.WINTER: -0.2,
}

const SEASON_MOIST_OFFSET := {
	DefEnums.Season.SPRING: 0.1,
	DefEnums.Season.SUMMER: 0.0,
	DefEnums.Season.AUTUMN: 0.0,
	DefEnums.Season.WINTER: -0.1,
}


func setup(
	ts: SysTime,
	temp: PackedFloat32Array,
	moist: PackedFloat32Array,
	base_temp: PackedFloat32Array,
	base_moist: PackedFloat32Array
) -> void:
	time_system = ts
	temperature_map = temp
	moisture_map = moist
	base_temperature_map = base_temp
	base_moisture_map = base_moist


var _is_updating: bool = false
var _thread_task_id: int = -1

func update(_world: Node, _delta: float) -> void:
	if time_system == null:
		return
	
	if _is_updating:
		if _thread_task_id != -1 and WorkerThreadPool.is_task_completed(_thread_task_id):
			WorkerThreadPool.wait_for_task_completion(_thread_task_id)
			_thread_task_id = -1
			_is_updating = false
			print("Season modifiers applied via thread.")
		return
		
	if time_system.season == _last_season:
		return
	_last_season = time_system.season
	_apply_season_modifiers()


func _apply_season_modifiers() -> void:
	var temp_offset: float = SEASON_TEMP_OFFSET.get(time_system.season, 0.0)
	var moist_offset: float = SEASON_MOIST_OFFSET.get(time_system.season, 0.0)
	
	_is_updating = true
	_thread_task_id = WorkerThreadPool.add_task(_apply_modifiers_thread.bind(temp_offset, moist_offset), true, "SeasonUpdate")


func _apply_modifiers_thread(temp_offset: float, moist_offset: float) -> void:
	for i in range(base_temperature_map.size()):
		temperature_map[i] = clampf(base_temperature_map[i] + temp_offset, 0.0, 1.0)
		moisture_map[i] = clampf(base_moisture_map[i] + moist_offset, 0.0, 1.0)

extends System
class_name SysTest

var _elapsed: float = 0.0
var _tick_interval: float = 1.0
var _tick_count: int = 0


func get_type() -> String:
	return "SysTest"


func update(world: Node, delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _tick_interval:
		_elapsed -= _tick_interval
		_tick_count += 1
		print("Test system tick #%d | Entities: %d" % [_tick_count, world.get_entity_count()])

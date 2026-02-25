extends Component
class_name ComTask

var task_type: int = DefEnums.TaskType.NONE
var target_position: Vector2i = Vector2i.ZERO
var target_entity: int = -1
var priority: int = 0


func get_type() -> String:
	return "ComTask"

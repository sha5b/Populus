extends Component
class_name ComPosition

var grid_x: int = 0
var grid_y: int = 0
var world_pos: Vector3 = Vector3.ZERO
var prev_world_pos: Vector3 = Vector3.ZERO
var lerp_t: float = 1.0


func get_type() -> String:
	return "ComPosition"

extends Component
class_name ComFollower

var role: int = DefEnums.RoleType.BRAVE
var tribe_id: int = DefEnums.TribeId.NEUTRAL
var state: int = DefEnums.AIState.IDLE
var target_entity: int = -1
var target_pos := Vector2i(-1, -1)


func get_type() -> String:
	return "ComFollower"

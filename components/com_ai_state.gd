extends Component
class_name ComAiState

var current_state: int = DefEnums.AIState.IDLE
var previous_state: int = DefEnums.AIState.IDLE
var state_timer: float = 0.0


func get_type() -> String:
	return "ComAiState"

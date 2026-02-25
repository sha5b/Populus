extends Component
class_name ComFlammable

var flammability: float = 0.4
var is_burning: bool = false
var burn_timer: float = 0.0


func get_type() -> String:
	return "ComFlammable"

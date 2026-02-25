extends Component
class_name ComConstruction

var progress: float = 0.0
var required_wood: int = 3
var consumed_wood: int = 0
var builders: Array[int] = []


func get_type() -> String:
	return "ComConstruction"

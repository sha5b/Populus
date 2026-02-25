extends Component
class_name ComSchedule

var wake_hour: int = 6
var sleep_hour: int = 22
var is_active: bool = true


func get_type() -> String:
	return "ComSchedule"

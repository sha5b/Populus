extends Component
class_name ComEnergy

var current: float = 80.0
var max_energy: float = 100.0
var drain_rate: float = 2.0
var rest_rate: float = 8.0


func get_type() -> String:
	return "ComEnergy"

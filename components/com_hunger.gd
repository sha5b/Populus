extends Component
class_name ComHunger

var current: float = 0.0
var max_hunger: float = 100.0
var hunger_rate: float = 0.5
var starvation_rate: float = 5.0
var eat_rate: float = 30.0


func get_type() -> String:
	return "ComHunger"

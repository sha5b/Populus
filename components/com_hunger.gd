extends Component
class_name ComHunger

var current: float = 0.0
var max_hunger: float = 100.0
var hunger_rate: float = 0.5
var starvation_rate: float = 5.0
var eat_rate: float = 30.0

var current_thirst: float = 0.0
var max_thirst: float = 100.0
var thirst_rate: float = 1.0
var dehydration_rate: float = 8.0
var drink_rate: float = 50.0

func get_type() -> String:
	return "ComHunger"

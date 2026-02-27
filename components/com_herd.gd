extends Component
class_name ComHerd

var herd_id: int = -1
var count: int = 1 # Number of animals in this herd
var radius: float = 3.0 # Radius in grid units
var separation_dist: float = 2.0
var cohesion_dist: float = 10.0


func get_type() -> String:
	return "ComHerd"

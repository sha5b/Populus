extends Component
class_name ComTile

var grid_x: int = 0
var grid_y: int = 0
var is_flat: bool = false
var is_water: bool = false
var occupant_id: int = -1


func get_type() -> String:
	return "ComTile"

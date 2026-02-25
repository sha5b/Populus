extends Component
class_name ComDisguise

var disguised_as_tribe: int = DefEnums.TribeId.NEUTRAL
var is_active: bool = false
var detection_chance: float = 0.1


func get_type() -> String:
	return "ComDisguise"

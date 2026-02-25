extends Component
class_name ComProduction

var production_type: int = DefEnums.RoleType.BRAVE
var timer: float = 0.0
var interval: float = 10.0


func get_type() -> String:
	return "ComProduction"

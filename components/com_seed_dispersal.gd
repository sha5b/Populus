extends Component
class_name ComSeedDispersal

var method: int = DefEnums.SeedMethod.WIND
var seed_range: int = 5
var timer: float = 0.0
var interval: float = 60.0


func get_type() -> String:
	return "ComSeedDispersal"

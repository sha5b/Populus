extends Component
class_name ComFaunaSpecies

var species_key: String = ""
var diet: int = DefEnums.DietType.HERBIVORE
var speed: float = 3.0
var preferred_biomes: Array[int] = []
var is_aquatic: bool = false
var is_flying: bool = false
var max_age: float = 300.0
var age: float = 0.0


func get_type() -> String:
	return "ComFaunaSpecies"

extends Component
class_name ComSpecies

var species_name: String = ""
var diet_type: int = DefEnums.DietType.HERBIVORE
var preferred_biomes: Array[int] = []


func get_type() -> String:
	return "ComSpecies"

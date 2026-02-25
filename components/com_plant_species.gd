extends Component
class_name ComPlantSpecies

var species_name: String = ""
var preferred_biomes: Array[int] = []
var water_need: float = 0.3
var light_need: float = 0.5


func get_type() -> String:
	return "ComPlantSpecies"

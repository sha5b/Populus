extends Component
class_name ComBiome

var biome_type: int = DefEnums.BiomeType.GRASSLAND
var temperature: float = 0.5
var moisture: float = 0.5
var fertility: float = 0.5


func get_type() -> String:
	return "ComBiome"

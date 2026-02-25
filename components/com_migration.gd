extends Component
class_name ComMigration

var preferred_biome: int = DefEnums.BiomeType.GRASSLAND
var migration_threshold: float = 0.3
var target: Vector2i = Vector2i(-1, -1)


func get_type() -> String:
	return "ComMigration"

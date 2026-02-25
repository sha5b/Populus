extends Component
class_name ComBuilding

var building_type: int = DefEnums.BuildingType.HUT_SMALL
var tribe_id: int = DefEnums.TribeId.NEUTRAL
var size: Vector2i = Vector2i(2, 2)


func get_type() -> String:
	return "ComBuilding"

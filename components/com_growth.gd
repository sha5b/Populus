extends Component
class_name ComGrowth

var stage: int = DefEnums.GrowthStage.SEED
var growth_rate: float = 0.01
var growth_progress: float = 0.0
var age: float = 0.0
var max_age: float = 500.0


func get_type() -> String:
	return "ComGrowth"

extends Component
class_name ComSpellCharge

var spell_type: int = DefEnums.SpellType.BLAST
var charges: int = 0
var max_charges: int = 10
var recharge_timer: float = 0.0


func get_type() -> String:
	return "ComSpellCharge"

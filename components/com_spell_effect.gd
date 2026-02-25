extends Component
class_name ComSpellEffect

var spell_type: int = DefEnums.SpellType.BLAST
var position: Vector2i = Vector2i.ZERO
var radius: float = 3.0
var duration: float = 0.0
var timer: float = 0.0


func get_type() -> String:
	return "ComSpellEffect"

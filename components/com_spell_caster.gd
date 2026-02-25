extends Component
class_name ComSpellCaster

var known_spells: Array[int] = []
var active_spell: int = -1
var cast_timer: float = 0.0


func get_type() -> String:
	return "ComSpellCaster"

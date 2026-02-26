extends Component
class_name ComIntelligence

var iq: float = 0.5
var is_leader: bool = false
var leader_eid: int = -1

# IQ Tiers
# < 0.3: Basic instinct (flee, solitary forage, mindless flock)
# 0.3 - 0.7: Herd behavior, follows leader, simple needs
# > 0.7: Fission-fusion, complex needs, promotes new leaders

func get_type() -> String:
	return "ComIntelligence"

extends System
class_name SysCombat

var grid: TorusGrid

var _timer: float = 0.0
const TICK_INTERVAL := 1.0


func setup(g: TorusGrid) -> void:
	grid = g


func update(world: Node, delta: float) -> void:
	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer -= TICK_INTERVAL

	var ecs := world as EcsWorld
	if ecs == null:
		return

	var combatants := ecs.query(["ComCombat", "ComHealth", "ComPosition"])
	var followers := ecs.get_components("ComFollower")

	# Process attacks
	for eid in combatants:
		var health: ComHealth = ecs.get_component(eid, "ComHealth")
		if health.current_hp <= 0.0:
			continue
			
		var follower: ComFollower = followers.get(eid)
		if not follower or follower.state != DefEnums.AIState.ATTACKING:
			continue
			
		var target_eid := follower.target_entity
		if target_eid < 0:
			follower.state = DefEnums.AIState.IDLE
			continue
			
		var target_health: ComHealth = ecs.get_component(target_eid, "ComHealth")
		if not target_health or target_health.current_hp <= 0.0:
			follower.state = DefEnums.AIState.IDLE
			follower.target_entity = -1
			continue
			
		var my_pos: ComPosition = ecs.get_component(eid, "ComPosition")
		var target_pos: ComPosition = ecs.get_component(target_eid, "ComPosition")
		if not my_pos or not target_pos:
			continue
			
		var dist := absi(my_pos.grid_x - target_pos.grid_x) + absi(my_pos.grid_y - target_pos.grid_y)
		var combat: ComCombat = ecs.get_component(eid, "ComCombat")
		
		if float(dist) <= combat.attack_range:
			# In range, attack!
			var target_combat: ComCombat = ecs.get_component(target_eid, "ComCombat")
			var armor := target_combat.armor if target_combat else 0.0
			var damage := maxf(1.0, combat.attack_damage - armor)
			target_health.current_hp -= damage * combat.attack_speed * TICK_INTERVAL
			
			# If target dies, return to IDLE
			if target_health.current_hp <= 0.0:
				follower.state = DefEnums.AIState.IDLE
				follower.target_entity = -1
				
				# Remove target entity (handled by a death system or here if simple)
				ecs.remove_entity(target_eid)

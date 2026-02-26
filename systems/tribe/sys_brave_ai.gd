extends System
class_name SysBraveAi

const ComFollowerScript = preload("res://components/com_follower.gd")

var grid: TorusGrid

var _timer: float = 0.0
const TICK_INTERVAL := 0.5


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

	var followers := ecs.get_components("ComFollower")
	var positions := ecs.get_components("ComPosition")
	var tribes := ecs.get_components("ComTribe")

	for eid in followers.keys():
		var f = followers[eid]
		if f.role != DefEnums.RoleType.BRAVE:
			continue

		if not positions.has(eid):
			continue
		var _p: ComPosition = positions[eid]

		var inv: ComInventory = null
		# Find tribe entity to access inventory
		for t_eid in tribes.keys():
			if tribes[t_eid].tribe_id == f.tribe_id:
				inv = ecs.get_component(t_eid, "ComInventory") as ComInventory
				break

		match f.state:
			DefEnums.AIState.IDLE:
				# Random wander for now until Tribal AI assigns tasks
				if randf() < 0.1:
					f.state = DefEnums.AIState.WANDERING
					f.target_pos = Vector2i(
						grid.wrap_x(_p.grid_x + randi_range(-3, 3)),
						grid.wrap_y(_p.grid_y + randi_range(-3, 3))
					)
					
			DefEnums.AIState.PLANNING_BUILD:
				f.state = DefEnums.AIState.IDLE # Tribal AI places ghost, brave is just assigned BUILD
				
			DefEnums.AIState.BUILDING:
				if f.target_entity >= 0:
					var t_pos: ComPosition = ecs.get_component(f.target_entity, "ComPosition")
					if t_pos:
						var dist: int = absi(_p.grid_x - t_pos.grid_x) + absi(_p.grid_y - t_pos.grid_y)
						if dist <= 1:
							# Reached construction site
							var constr: ComConstruction = ecs.get_component(f.target_entity, "ComConstruction")
							if constr and inv and inv.wood > 0:
								# Deposit wood
								var amount := mini(inv.wood, constr.required_wood - constr.consumed_wood)
								inv.wood -= amount
								constr.consumed_wood += amount
								if constr.consumed_wood >= constr.required_wood:
									f.state = DefEnums.AIState.IDLE
								# Actual building progress will be handled by SysConstruction
							else:
								# No wood, need to harvest
								f.state = DefEnums.AIState.IDLE
						else:
							# Move closer
							var dx := signi(t_pos.grid_x - _p.grid_x)
							var dy := signi(t_pos.grid_y - _p.grid_y)
							_p.grid_x = grid.wrap_x(_p.grid_x + dx)
							_p.grid_y = grid.wrap_y(_p.grid_y + dy)
					else:
						f.state = DefEnums.AIState.IDLE
				else:
					f.state = DefEnums.AIState.IDLE
					
			DefEnums.AIState.HARVESTING:
				if f.target_entity >= 0:
					var t_pos: ComPosition = ecs.get_component(f.target_entity, "ComPosition")
					if t_pos:
						var dist: int = absi(_p.grid_x - t_pos.grid_x) + absi(_p.grid_y - t_pos.grid_y)
						if dist <= 1:
							# Reached tree
							var resource: ComResource = ecs.get_component(f.target_entity, "ComResource")
							if resource and inv:
								inv.wood += resource.wood_yield
								# Destroy tree
								ecs.remove_entity(f.target_entity)
								f.target_entity = -1
								f.state = DefEnums.AIState.IDLE
						else:
							# Move closer
							var dx := signi(t_pos.grid_x - _p.grid_x)
							var dy := signi(t_pos.grid_y - _p.grid_y)
							_p.grid_x = grid.wrap_x(_p.grid_x + dx)
							_p.grid_y = grid.wrap_y(_p.grid_y + dy)
					else:
						f.state = DefEnums.AIState.IDLE
				else:
					f.state = DefEnums.AIState.IDLE

			DefEnums.AIState.ATTACKING:
				if f.target_entity >= 0:
					var t_pos: ComPosition = ecs.get_component(f.target_entity, "ComPosition")
					if t_pos:
						var dist: int = absi(_p.grid_x - t_pos.grid_x) + absi(_p.grid_y - t_pos.grid_y)
						var combat: ComCombat = ecs.get_component(eid, "ComCombat")
						var attack_range := combat.attack_range if combat else 2.0
						
						if float(dist) <= attack_range:
							# Reached attack range, let SysCombat handle the damage
							pass
						else:
							# Move closer
							var dx := signi(t_pos.grid_x - _p.grid_x)
							var dy := signi(t_pos.grid_y - _p.grid_y)
							_p.grid_x = grid.wrap_x(_p.grid_x + dx)
							_p.grid_y = grid.wrap_y(_p.grid_y + dy)
					else:
						f.state = DefEnums.AIState.IDLE
				else:
					f.state = DefEnums.AIState.IDLE

			DefEnums.AIState.WANDERING:
				if _p.grid_x == f.target_pos.x and _p.grid_y == f.target_pos.y:
					f.state = DefEnums.AIState.IDLE
				else:
					# Basic movement towards target
					var dx := signi(f.target_pos.x - _p.grid_x)
					var dy := signi(f.target_pos.y - _p.grid_y)
					_p.grid_x = grid.wrap_x(_p.grid_x + dx)
					_p.grid_y = grid.wrap_y(_p.grid_y + dy)

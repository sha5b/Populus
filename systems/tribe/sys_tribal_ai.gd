extends System
class_name SysTribalAi

var grid: TorusGrid
var projector: PlanetProjector

var _timer: float = 0.0
const TICK_INTERVAL := 2.0


func setup(g: TorusGrid, proj: PlanetProjector) -> void:
	grid = g
	projector = proj


func update(world: Node, delta: float) -> void:
	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer -= TICK_INTERVAL

	var ecs := world as EcsWorld
	if ecs == null:
		return

	# Right now this is a minimal stub to coordinate Braves:
	# E.g. find all IDLE braves, find nearest buildable spot, assign build order.
	_assign_combat_tasks(ecs)
	_assign_build_tasks(ecs)


func _assign_combat_tasks(ecs: EcsWorld) -> void:
	var tribes := ecs.get_components("ComTribe")
	var followers := ecs.get_components("ComFollower")
	var positions := ecs.get_components("ComPosition")

	for t_eid in tribes.keys():
		var t: ComTribe = tribes[t_eid]
		
		# Get our braves
		var our_braves := []
		for f_eid in followers.keys():
			var f: ComFollower = followers[f_eid]
			if f.tribe_id == t.tribe_id and f.role == DefEnums.RoleType.BRAVE:
				our_braves.append(f_eid)
				
		if our_braves.is_empty():
			continue
			
		# Find enemy followers
		var enemy_eids := []
		for f_eid in followers.keys():
			var f: ComFollower = followers[f_eid]
			if f.tribe_id != t.tribe_id and f.tribe_id != DefEnums.TribeId.NEUTRAL:
				enemy_eids.append(f_eid)
				
		if enemy_eids.is_empty():
			continue
			
		for brave_eid in our_braves:
			var f: ComFollower = followers[brave_eid]
			if f.state == DefEnums.AIState.IDLE or f.state == DefEnums.AIState.WANDERING or f.state == DefEnums.AIState.HARVESTING:
				var p: ComPosition = positions.get(brave_eid)
				if not p:
					continue
				
				var best_dist := 9999
				var best_enemy := -1
				for enemy_eid in enemy_eids:
					var ep: ComPosition = positions.get(enemy_eid)
					if ep:
						var dist: int = absi(p.grid_x - ep.grid_x) + absi(p.grid_y - ep.grid_y)
						if dist < best_dist:
							best_dist = dist
							best_enemy = enemy_eid
							
				if best_enemy != -1 and best_dist < 15: # Aggro radius
					f.state = DefEnums.AIState.ATTACKING
					f.target_entity = best_enemy


func _assign_build_tasks(ecs: EcsWorld) -> void:
	var tribes := ecs.get_components("ComTribe")
	var followers := ecs.get_components("ComFollower")
	var positions := ecs.get_components("ComPosition")
	var constructions := ecs.get_components("ComConstruction")

	for t_eid in tribes.keys():
		var t: ComTribe = tribes[t_eid]
		var inv: ComInventory = ecs.get_component(t_eid, "ComInventory")
		
		# Find idle braves for this tribe
		var idle_braves := []
		var gathering_braves := []
		var building_braves := []
		for f_eid in followers.keys():
			var f: ComFollower = followers[f_eid]
			if f.tribe_id == t.tribe_id and f.role == DefEnums.RoleType.BRAVE:
				if f.state == DefEnums.AIState.IDLE:
					idle_braves.append(f_eid)
				elif f.state == DefEnums.AIState.HARVESTING:
					gathering_braves.append(f_eid)
				elif f.state == DefEnums.AIState.BUILDING:
					building_braves.append(f_eid)

		if idle_braves.is_empty():
			continue
			
		# Find active constructions for this tribe
		var active_constructions := []
		for c_eid in constructions.keys():
			var bldg: ComBuilding = ecs.get_component(c_eid, "ComBuilding")
			if bldg and bldg.tribe_id == t.tribe_id:
				var c: ComConstruction = constructions[c_eid]
				if c.progress < 1.0:
					active_constructions.append(c_eid)
					
		# Logic: 
		# 1. If we have constructions, assign braves to build if we have wood.
		# 2. If we need wood, assign braves to gather.
		# 3. If we have plenty of wood and few buildings, spawn a new construction.
		
		var total_wood: int = inv.wood if inv else 0
		
		for f_eid in idle_braves:
			var f: ComFollower = followers[f_eid]
			var p: ComPosition = positions.get(f_eid)
			if not p:
				continue
				
			if not active_constructions.is_empty() and total_wood > 0:
				# Assign to build
				var c_eid: int = active_constructions[0]
				f.state = DefEnums.AIState.BUILDING
				f.target_entity = c_eid
				total_wood -= 1 # Prevent over-assigning if we only have 1 wood
			elif total_wood < 10 or gathering_braves.size() < 2:
				# Gather wood
				var tree_eid := _find_nearest_tree(ecs, p.grid_x, p.grid_y)
				if tree_eid >= 0:
					f.state = DefEnums.AIState.HARVESTING
					f.target_entity = tree_eid
					gathering_braves.append(f_eid)
			elif active_constructions.is_empty() and total_wood >= 3:
				# Start a new building
				var spot := _find_flat_spot(p.grid_x, p.grid_y)
				if spot != Vector2i(-1, -1):
					var c_eid := _spawn_construction_ghost(ecs, t.tribe_id, spot.x, spot.y)
					active_constructions.append(c_eid)
					f.state = DefEnums.AIState.BUILDING
					f.target_entity = c_eid
					total_wood -= 3
					
					
func _find_nearest_tree(ecs: EcsWorld, cx: int, cy: int) -> int:
	var plants := ecs.get_components("ComPlantSpecies")
	var positions := ecs.get_components("ComPosition")
	
	var best_dist := 9999
	var best_eid := -1
	
	for eid in plants.keys():
		var sp: ComPlantSpecies = plants[eid]
		if sp.species_name in DefFlora.SPECIES_DATA:
			var data: Dictionary = DefFlora.SPECIES_DATA[sp.species_name]
			if data.get("flora_type", -1) == DefFlora.FloraType.TREE:
				var p: ComPosition = positions.get(eid)
				if p:
					var dist: int = absi(p.grid_x - cx) + absi(p.grid_y - cy)
					if dist < best_dist:
						best_dist = dist
						best_eid = eid
						if best_dist < 5:
							break # Good enough
							
	return best_eid
	
	
func _find_flat_spot(cx: int, cy: int) -> Vector2i:
	# Search in a spiral or random offsets
	for _i in range(10):
		var nx := grid.wrap_x(cx + randi_range(-8, 8))
		var ny := grid.wrap_y(cy + randi_range(-8, 8))
		if grid.get_height(nx, ny) > GameConfig.SEA_LEVEL and grid.is_flat(nx, ny, 0.05):
			return Vector2i(nx, ny)
	return Vector2i(-1, -1)
	
	
func _spawn_construction_ghost(ecs: EcsWorld, tribe_id: int, cx: int, cy: int) -> int:
	var eid := ecs.create_entity()
	
	var pos := ComPosition.new()
	pos.grid_x = cx
	pos.grid_y = cy
	if projector:
		var dir := projector.grid_to_sphere(float(cx), float(cy)).normalized()
		var h := maxf(grid.get_height(cx, cy), GameConfig.SEA_LEVEL)
		pos.world_pos = dir * (projector.radius + h * projector.height_scale)
	ecs.add_component(eid, pos)
	
	var bldg := ComBuilding.new()
	bldg.building_type = DefEnums.BuildingType.HUT_SMALL
	bldg.tribe_id = tribe_id
	bldg.size = Vector2i(2, 2)
	ecs.add_component(eid, bldg)
	
	var constr := ComConstruction.new()
	constr.required_wood = 3
	constr.consumed_wood = 0
	constr.progress = 0.0
	ecs.add_component(eid, constr)
	
	return eid.id

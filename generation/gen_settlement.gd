class_name GenSettlement

static func generate(world: EcsWorld, grid: TorusGrid, _projector: PlanetProjector) -> void:
	var w := grid.width
	var h := grid.height
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.WORLD_SEED + 888

	var tribes_to_spawn := 2
	var spawned := 0
	
	for _attempt in range(50):
		if spawned >= tribes_to_spawn:
			break
			
		var cx := rng.randi() % w
		var cy := rng.randi() % h
		
		# Need flat, dry land
		if grid.get_height(cx, cy) <= GameConfig.SEA_LEVEL:
			continue
		if not grid.is_flat(cx, cy, 0.05):
			continue
			
		_spawn_tribe(world, grid, cx, cy, spawned)
		spawned += 1


static func _spawn_tribe(world: EcsWorld, grid: TorusGrid, cx: int, cy: int, index: int) -> void:
	var tribe_id := DefEnums.TribeId.BLUE if index == 0 else DefEnums.TribeId.RED
	var tribe_color := Color(0.2, 0.4, 0.9) if index == 0 else Color(0.8, 0.2, 0.2)
	
	var tribe_eid := world.create_entity()
	
	var com_tribe := ComTribe.new()
	com_tribe.tribe_id = tribe_id
	com_tribe.tribe_color = tribe_color
	world.add_component(tribe_eid, com_tribe)
	
	var inv := ComInventory.new()
	inv.wood = 5 # Start with some wood to get going
	world.add_component(tribe_eid, inv)
	
	# Spawn a starting hut
	var hut_eid := world.create_entity()
	var hut_pos := ComPosition.new()
	hut_pos.grid_x = cx
	hut_pos.grid_y = cy
	world.add_component(hut_eid, hut_pos)
	
	var com_bldg := ComBuilding.new()
	com_bldg.building_type = DefEnums.BuildingType.HUT_SMALL
	com_bldg.tribe_id = tribe_id
	com_bldg.size = Vector2i(2, 2)
	world.add_component(hut_eid, com_bldg)
	
	# Spawn a few braves
	for _i in range(3):
		var brave_eid := world.create_entity()
		var brave_pos := ComPosition.new()
		brave_pos.grid_x = grid.wrap_x(cx + randi_range(-2, 2))
		brave_pos.grid_y = grid.wrap_y(cy + randi_range(-2, 2))
		world.add_component(brave_eid, brave_pos)
		
		var brave_f := ComFollower.new()
		brave_f.tribe_id = tribe_id
		brave_f.role = DefEnums.RoleType.BRAVE
		brave_f.state = DefEnums.AIState.IDLE
		world.add_component(brave_eid, brave_f)
		
		var brave_combat := ComCombat.new()
		brave_combat.attack_damage = 10.0
		brave_combat.attack_range = 2.0
		world.add_component(brave_eid, brave_combat)
		
		var brave_health := ComHealth.new()
		brave_health.max_hp = 50.0
		brave_health.current_hp = 50.0
		world.add_component(brave_eid, brave_health)

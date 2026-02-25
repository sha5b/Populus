extends System
class_name SysSeedDispersal

var grid: TorusGrid = null
var projector: PlanetProjector = null
var wind_system: SysWind = null
var moisture_map: PackedFloat32Array

var _accumulator: float = 0.0
const TICK_INTERVAL := 3.0
const MAX_SEEDS_PER_TICK := 20
const MAX_FLORA_PER_TILE := 1


func setup(p_grid: TorusGrid, p_proj: PlanetProjector, p_wind: SysWind, p_moisture: PackedFloat32Array) -> void:
	grid = p_grid
	projector = p_proj
	wind_system = p_wind
	moisture_map = p_moisture


func update(_world: Node, delta: float) -> void:
	_accumulator += delta
	if _accumulator < TICK_INTERVAL:
		return
	_accumulator = 0.0

	var ecs := _world as EcsWorld
	if ecs == null or grid == null:
		return

	var entities := ecs.query(["ComPlantSpecies", "ComGrowth", "ComSeedDispersal", "ComPosition"])
	var seeds_spawned := 0
	var occupied := _build_occupancy_map(ecs)

	for eid in entities:
		if seeds_spawned >= MAX_SEEDS_PER_TICK:
			break

		var growth: ComGrowth = ecs.get_component(eid, "ComGrowth") as ComGrowth
		if growth.stage != DefEnums.GrowthStage.MATURE and growth.stage != DefEnums.GrowthStage.OLD:
			continue

		var seed_comp: ComSeedDispersal = ecs.get_component(eid, "ComSeedDispersal") as ComSeedDispersal
		var secs_per_year := float(GameConfig.HOURS_PER_DAY * GameConfig.DAYS_PER_SEASON * GameConfig.SEASONS_PER_YEAR) * 60.0
		var years_per_tick := (TICK_INTERVAL * GameConfig.TIME_SCALE) / secs_per_year
		seed_comp.timer -= years_per_tick
		if seed_comp.timer > 0.0:
			continue
		seed_comp.timer = seed_comp.interval

		var pos: ComPosition = ecs.get_component(eid, "ComPosition") as ComPosition
		var plant: ComPlantSpecies = ecs.get_component(eid, "ComPlantSpecies") as ComPlantSpecies
		var target := _find_seed_target(pos, seed_comp, plant)
		if target.x < 0:
			continue

		var tile_key := target.y * grid.width + target.x
		if occupied.has(tile_key):
			continue

		_spawn_seed(ecs, target, plant, seed_comp)
		occupied[tile_key] = true
		seeds_spawned += 1


func _find_seed_target(pos: ComPosition, seed_comp: ComSeedDispersal, plant: ComPlantSpecies) -> Vector2i:
	var rng_val := randi()
	var range_val := seed_comp.seed_range
	var w := grid.width
	var h := grid.height

	for _attempt in range(5):
		var ox := (rng_val % (range_val * 2 + 1)) - range_val
		rng_val = rng_val * 1103515245 + 12345
		var oy := (rng_val % (range_val * 2 + 1)) - range_val
		rng_val = rng_val * 1103515245 + 12345

		if seed_comp.method == DefEnums.SeedMethod.WIND and wind_system:
			ox += int(wind_system.direction.x * 2.0)
			oy += int(wind_system.direction.y * 2.0)

		var tx := (pos.grid_x + ox) % w
		if tx < 0:
			tx += w
		var ty := clampi(pos.grid_y + oy, 0, h - 1)

		if grid.get_height(tx, ty) < GameConfig.SEA_LEVEL:
			if seed_comp.method != DefEnums.SeedMethod.WATER:
				continue

		var biome := grid.get_biome(tx, ty)
		if biome in plant.preferred_biomes:
			return Vector2i(tx, ty)

	return Vector2i(-1, -1)


func _spawn_seed(ecs: EcsWorld, target: Vector2i, parent_plant: ComPlantSpecies, _parent_seed: ComSeedDispersal) -> void:
	var species_data: Dictionary = DefFlora.SPECIES_DATA.get(parent_plant.species_name, {})
	if species_data.is_empty():
		return

	var entity := ecs.create_entity()
	var height := grid.get_height(target.x, target.y)

	var pos := ComPosition.new()
	pos.grid_x = target.x
	pos.grid_y = target.y
	if projector:
		var base := projector.grid_to_sphere(float(target.x) + 0.5, float(target.y) + 0.5)
		var fi := projector.world_to_cube_face(base)
		pos.world_pos = projector.cube_sphere_point(fi[0], fi[1], fi[2], height * projector.height_scale)
	ecs.add_component(entity, pos)

	var plant := ComPlantSpecies.new()
	plant.species_name = parent_plant.species_name
	plant.preferred_biomes = parent_plant.preferred_biomes.duplicate()
	plant.water_need = parent_plant.water_need
	plant.light_need = parent_plant.light_need
	ecs.add_component(entity, plant)

	var growth := ComGrowth.new()
	growth.stage = DefEnums.GrowthStage.SEED
	growth.growth_rate = species_data["growth_rate"]
	growth.growth_progress = 0.0
	growth.age = 0.0
	growth.max_age = species_data["max_age"]
	ecs.add_component(entity, growth)

	var seed_comp := ComSeedDispersal.new()
	seed_comp.method = species_data["seed_method"]
	seed_comp.seed_range = species_data["seed_range"]
	seed_comp.interval = species_data["seed_interval"]
	seed_comp.timer = seed_comp.interval
	ecs.add_component(entity, seed_comp)

	var flammable := ComFlammable.new()
	flammable.flammability = species_data["flammability"]
	ecs.add_component(entity, flammable)

	var resource := ComResource.new()
	resource.wood_yield = species_data["wood_yield"]
	resource.food_yield = species_data["food_yield"]
	ecs.add_component(entity, resource)


func _build_occupancy_map(ecs: EcsWorld) -> Dictionary:
	var occupied := {}
	var positions := ecs.get_components("ComPosition")
	var plants := ecs.get_components("ComPlantSpecies")
	for eid in plants.keys():
		if positions.has(eid):
			var p: ComPosition = positions[eid]
			var key := p.grid_y * grid.width + p.grid_x
			occupied[key] = true
	return occupied

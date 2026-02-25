extends System
class_name SysReproduction

var grid: TorusGrid = null
var projector: PlanetProjector = null

const TICK_INTERVAL := 3.0
var _timer := 0.0

const MATE_RANGE := 5
var _species_counts: Dictionary = {}


func setup(g: TorusGrid, proj: PlanetProjector) -> void:
	grid = g
	projector = proj


func update(world: Node, delta: float) -> void:
	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer -= TICK_INTERVAL

	var ecs := world as EcsWorld
	var entities := ecs.query(["ComFaunaSpecies", "ComReproduction", "ComPosition", "ComHunger"])

	var secs_per_year := float(GameConfig.HOURS_PER_DAY * GameConfig.DAYS_PER_SEASON * GameConfig.SEASONS_PER_YEAR) * 60.0
	var years_per_tick := (TICK_INTERVAL * GameConfig.TIME_SCALE) / secs_per_year

	_count_species(ecs, entities)

	var spawn_queue: Array[Dictionary] = []

	for eid in entities:
		var species: ComFaunaSpecies = ecs.get_component(eid, "ComFaunaSpecies") as ComFaunaSpecies
		var repro: ComReproduction = ecs.get_component(eid, "ComReproduction") as ComReproduction
		var pos: ComPosition = ecs.get_component(eid, "ComPosition") as ComPosition
		var hunger: ComHunger = ecs.get_component(eid, "ComHunger") as ComHunger

		repro.cooldown -= years_per_tick
		if repro.cooldown > 0.0:
			continue

		if species.age < repro.maturity_age:
			continue

		if hunger.current > hunger.max_hunger * 0.6:
			continue

		var count: int = _species_counts.get(species.species_key, 0)
		var cap: int = _get_species_cap(species.species_key)
		if count >= cap:
			continue

		var mate := _find_mate(ecs, eid, species, pos, entities)
		if mate < 0:
			continue

		repro.cooldown = repro.gestation_period

		var mate_repro: ComReproduction = ecs.get_component(mate, "ComReproduction") as ComReproduction
		if mate_repro != null:
			mate_repro.cooldown = repro.gestation_period

		var herd: ComHerd = ecs.get_component(eid, "ComHerd") as ComHerd
		var herd_id := herd.herd_id if herd != null else -1

		for _o in range(repro.offspring_count):
			spawn_queue.append({
				"species_key": species.species_key,
				"gx": grid.wrap_x(pos.grid_x + randi_range(-1, 1)),
				"gy": grid.wrap_y(pos.grid_y + randi_range(-1, 1)),
				"herd_id": herd_id,
			})

	for spawn_data in spawn_queue:
		_spawn_offspring(ecs, spawn_data)


func _count_species(ecs: EcsWorld, entities: Array[int]) -> void:
	_species_counts.clear()
	for eid in entities:
		var sp: ComFaunaSpecies = ecs.get_component(eid, "ComFaunaSpecies") as ComFaunaSpecies
		_species_counts[sp.species_key] = _species_counts.get(sp.species_key, 0) + 1


func _get_species_cap(species_key: String) -> int:
	var data: Dictionary = DefFauna.SPECIES_DATA.get(species_key, {})
	var base_cap := 60
	if data.get("social", "solitary") == "solitary":
		base_cap = 15
	elif data.get("social", "") == "pack":
		base_cap = 25
	return base_cap


func _find_mate(ecs: EcsWorld, self_id: int, species: ComFaunaSpecies, self_pos: ComPosition, entities: Array[int]) -> int:
	for eid in entities:
		if eid == self_id:
			continue
		var other_sp: ComFaunaSpecies = ecs.get_component(eid, "ComFaunaSpecies") as ComFaunaSpecies
		if other_sp.species_key != species.species_key:
			continue
		var other_repro: ComReproduction = ecs.get_component(eid, "ComReproduction") as ComReproduction
		if other_repro == null or other_repro.cooldown > 0.0:
			continue
		if other_sp.age < other_repro.maturity_age:
			continue
		var other_pos: ComPosition = ecs.get_component(eid, "ComPosition") as ComPosition
		if _grid_dist(self_pos, other_pos) <= MATE_RANGE:
			return eid
	return -1


func _grid_dist(a: ComPosition, b: ComPosition) -> float:
	if grid == null:
		return 9999.0
	var dx := absi(a.grid_x - b.grid_x)
	var dy := absi(a.grid_y - b.grid_y)
	dx = mini(dx, grid.width - dx)
	dy = mini(dy, grid.height - dy)
	return sqrt(float(dx * dx + dy * dy))


func _spawn_offspring(ecs: EcsWorld, data: Dictionary) -> void:
	var species_key: String = data["species_key"]
	var gx: int = data["gx"]
	var gy: int = data["gy"]
	var herd_id: int = data["herd_id"]
	var sp_data: Dictionary = DefFauna.SPECIES_DATA[species_key]

	var entity := ecs.create_entity()

	var pos := ComPosition.new()
	pos.grid_x = gx
	pos.grid_y = gy
	if projector != null and grid != null:
		var h := grid.get_height(gx, gy)
		var dir := projector.grid_to_sphere(float(gx) + 0.5, float(gy) + 0.5).normalized()
		pos.world_pos = dir * (projector.radius + h * projector.height_scale)
	ecs.add_component(entity, pos)

	var species := ComFaunaSpecies.new()
	species.species_key = species_key
	species.diet = sp_data["diet"]
	species.speed = sp_data["speed"]
	for b in sp_data["preferred_biomes"]:
		species.preferred_biomes.append(b)
	species.is_aquatic = sp_data.get("is_aquatic", false)
	species.is_flying = sp_data.get("is_flying", false)
	species.max_age = sp_data["max_age"]
	species.age = 0.0
	ecs.add_component(entity, species)

	var health := ComHealth.new()
	health.max_hp = sp_data["hp"]
	health.current_hp = sp_data["hp"]
	ecs.add_component(entity, health)

	var hunger := ComHunger.new()
	hunger.hunger_rate = sp_data["hunger_rate"]
	ecs.add_component(entity, hunger)

	var ai := ComAiState.new()
	ai.current_state = DefEnums.AIState.IDLE
	ecs.add_component(entity, ai)

	var repro := ComReproduction.new()
	repro.maturity_age = sp_data["maturity_age"]
	repro.gestation_period = sp_data["gestation"]
	repro.offspring_count = sp_data["offspring_count"]
	repro.cooldown = sp_data["maturity_age"]
	ecs.add_component(entity, repro)

	var herd := ComHerd.new()
	herd.herd_id = herd_id
	ecs.add_component(entity, herd)

	if sp_data["diet"] == DefEnums.DietType.CARNIVORE or sp_data["diet"] == DefEnums.DietType.OMNIVORE:
		var pred := ComPredator.new()
		pred.hunt_range = sp_data.get("hunt_range", 10.0)
		pred.attack_damage = sp_data.get("attack_damage", 10.0)
		for pt in sp_data.get("prey_types", []):
			pred.prey_types.append(pt)
		ecs.add_component(entity, pred)

	if sp_data["diet"] == DefEnums.DietType.HERBIVORE or sp_data["diet"] == DefEnums.DietType.OMNIVORE:
		var prey := ComPrey.new()
		prey.flee_speed_bonus = sp_data.get("flee_speed_bonus", 1.5)
		prey.awareness_range = sp_data.get("awareness_range", 10.0)
		ecs.add_component(entity, prey)

	var migration := ComMigration.new()
	migration.preferred_biome = sp_data["preferred_biomes"][0]
	ecs.add_component(entity, migration)


func randi_range(min_val: int, max_val: int) -> int:
	return min_val + (randi() % (max_val - min_val + 1))

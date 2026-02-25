class_name GenFauna

var grid: TorusGrid
var projector: PlanetProjector
var rng := RandomNumberGenerator.new()

const MAX_PER_SPECIES := 40
const LAND_SPECIES := ["deer", "wolf", "rabbit", "bear", "eagle", "bison"]
const WATER_SPECIES := ["fish"]


func generate(world: EcsWorld, g: TorusGrid, proj: PlanetProjector, biome_map: PackedInt32Array) -> void:
	grid = g
	projector = proj
	rng.seed = hash("fauna_gen") + GameConfig.WORLD_SEED

	var next_herd_id := 0

	for species_key in DefFauna.SPECIES_DATA:
		var data: Dictionary = DefFauna.SPECIES_DATA[species_key]
		var is_aquatic: bool = data.get("is_aquatic", false)
		var preferred: Array = data["preferred_biomes"]
		var herd_min: int = data["herd_size_min"]
		var herd_max: int = data["herd_size_max"]

		var valid_tiles := _find_valid_tiles(biome_map, preferred, is_aquatic)
		if valid_tiles.is_empty():
			continue

		var spawned := 0
		while spawned < MAX_PER_SPECIES and not valid_tiles.is_empty():
			var herd_size := rng.randi_range(herd_min, herd_max)
			var center_idx := rng.randi() % valid_tiles.size()
			var center := valid_tiles[center_idx]
			var herd_id := next_herd_id
			next_herd_id += 1

			for _m in range(herd_size):
				if spawned >= MAX_PER_SPECIES:
					break
				var tx := grid.wrap_x(center.x + rng.randi_range(-2, 2))
				var ty := grid.wrap_y(center.y + rng.randi_range(-2, 2))
				_spawn_animal(world, species_key, data, tx, ty, herd_id)
				spawned += 1

			valid_tiles.remove_at(center_idx)

		print("Fauna: spawned %d %s" % [spawned, species_key])


func _find_valid_tiles(biome_map: PackedInt32Array, preferred: Array, is_aquatic: bool) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var w := grid.width
	var h := grid.height
	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			if idx >= biome_map.size():
				continue
			var biome := biome_map[idx]
			var height := grid.get_height(x, y)
			if is_aquatic:
				if height < GameConfig.SEA_LEVEL and biome in preferred:
					tiles.append(Vector2i(x, y))
			else:
				if height >= GameConfig.SEA_LEVEL and biome in preferred:
					tiles.append(Vector2i(x, y))
	tiles.shuffle()
	return tiles


func _spawn_animal(world: EcsWorld, species_key: String, data: Dictionary, gx: int, gy: int, herd_id: int) -> void:
	var entity := world.create_entity()

	var pos := ComPosition.new()
	pos.grid_x = gx
	pos.grid_y = gy
	var h := grid.get_height(gx, gy)
	var dir := projector.grid_to_sphere(float(gx) + 0.5, float(gy) + 0.5).normalized()
	pos.world_pos = dir * (projector.radius + h * projector.height_scale)
	world.add_component(entity, pos)

	var species := ComFaunaSpecies.new()
	species.species_key = species_key
	species.diet = data["diet"]
	species.speed = data["speed"]
	for b in data["preferred_biomes"]:
		species.preferred_biomes.append(b)
	species.is_aquatic = data.get("is_aquatic", false)
	species.is_flying = data.get("is_flying", false)
	species.max_age = data["max_age"]
	species.age = rng.randf_range(0.0, data["maturity_age"] * 0.8)
	world.add_component(entity, species)

	var health := ComHealth.new()
	health.max_hp = data["hp"]
	health.current_hp = data["hp"]
	world.add_component(entity, health)

	var hunger := ComHunger.new()
	hunger.hunger_rate = data["hunger_rate"]
	world.add_component(entity, hunger)

	var energy := ComEnergy.new()
	energy.current = rng.randf_range(50.0, 100.0)
	world.add_component(entity, energy)

	var ai := ComAiState.new()
	var start_states := [DefEnums.AIState.WANDERING, DefEnums.AIState.FORAGING, DefEnums.AIState.WANDERING]
	ai.current_state = start_states[rng.randi() % start_states.size()]
	ai.state_timer = rng.randf_range(0.0, 2.0)
	world.add_component(entity, ai)

	var repro := ComReproduction.new()
	repro.maturity_age = data["maturity_age"]
	repro.gestation_period = data["gestation"]
	repro.offspring_count = data["offspring_count"]
	world.add_component(entity, repro)

	var herd := ComHerd.new()
	herd.herd_id = herd_id
	world.add_component(entity, herd)

	if data["diet"] == DefEnums.DietType.CARNIVORE or data["diet"] == DefEnums.DietType.OMNIVORE:
		var pred := ComPredator.new()
		pred.hunt_range = data.get("hunt_range", 10.0)
		pred.attack_damage = data.get("attack_damage", 10.0)
		for pt in data.get("prey_types", []):
			pred.prey_types.append(pt)
		world.add_component(entity, pred)

	if data["diet"] == DefEnums.DietType.HERBIVORE or data["diet"] == DefEnums.DietType.OMNIVORE:
		var prey := ComPrey.new()
		prey.flee_speed_bonus = data.get("flee_speed_bonus", 1.5)
		prey.awareness_range = data.get("awareness_range", 10.0)
		world.add_component(entity, prey)

	var migration := ComMigration.new()
	migration.preferred_biome = data["preferred_biomes"][0]
	world.add_component(entity, migration)

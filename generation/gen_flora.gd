class_name GenFlora

const MAX_FLORA_PER_TILE := 1
const MAX_TOTAL_FLORA := 16000
const MAX_AQUATIC_FLORA := 5000
const AQUATIC_DENSITY := 0.08

static var _clump_noise: FastNoiseLite
static var _species_noise: FastNoiseLite


static func _ensure_noise() -> void:
	if _clump_noise != null:
		return
	_clump_noise = FastNoiseLite.new()
	_clump_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	_clump_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_clump_noise.fractal_octaves = 2
	_clump_noise.frequency = 0.06
	_clump_noise.seed = 54321
	_clump_noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	_clump_noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE

	_species_noise = FastNoiseLite.new()
	_species_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_species_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_species_noise.fractal_octaves = 2
	_species_noise.frequency = 0.08
	_species_noise.seed = 67890


static func generate(world: EcsWorld, grid: TorusGrid, biome_map: PackedInt32Array, proj: PlanetProjector) -> int:
	_ensure_noise()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var count := 0
	var aquatic_count := 0
	var w := grid.width
	var h := grid.height

	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			var biome: int = biome_map[idx]
			var height := grid.get_height(x, y)

			if height >= GameConfig.SEA_LEVEL:
				if count >= MAX_TOTAL_FLORA:
					continue
				count += _try_place_land_flora(world, grid, proj, rng, x, y, biome, height)
			else:
				if aquatic_count >= MAX_AQUATIC_FLORA:
					continue
				aquatic_count += _try_place_aquatic_flora(world, grid, proj, rng, x, y, height)

	print("Flora: %d land + %d aquatic = %d total" % [count, aquatic_count, count + aquatic_count])
	return count + aquatic_count


static func _try_place_land_flora(world: EcsWorld, grid: TorusGrid, proj: PlanetProjector, rng: RandomNumberGenerator, x: int, y: int, biome: int, height: float) -> int:
	var biome_data: Dictionary = DefBiomes.BIOME_DATA.get(biome, {})
	var tree_density: float = biome_data.get("tree_density", 0.0)
	if tree_density <= 0.0:
		return 0

	# Noise-based clumping: creates natural groves and clearings
	var clump := (_clump_noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
	var clump_boost := clampf(clump * 1.8, 0.0, 1.0)

	# Fertility from biome affects density
	var fertility: float = biome_data.get("fertility", 0.5)
	var effective_density := tree_density * lerpf(0.4, 1.0, fertility) * clump_boost

	var roll := rng.randf()
	if roll > effective_density:
		return 0

	var valid_species := DefFlora.get_species_for_biome(biome)
	if valid_species.is_empty():
		return 0

	# Use noise to bias species selection for natural patches of same species
	var sp_noise := (_species_noise.get_noise_2d(float(x) * 2.0, float(y) * 2.0) + 1.0) * 0.5
	var sp_idx := int(sp_noise * float(valid_species.size())) % valid_species.size()
	var species_key: String = valid_species[sp_idx]

	_spawn_flora_entity(world, grid, proj, rng, x, y, height, species_key)
	return 1


static func _try_place_aquatic_flora(world: EcsWorld, grid: TorusGrid, proj: PlanetProjector, rng: RandomNumberGenerator, x: int, y: int, height: float) -> int:
	var depth := GameConfig.SEA_LEVEL - height
	if depth < 0.005:
		return 0

	if rng.randf() > AQUATIC_DENSITY:
		return 0

	var valid_species := DefFlora.get_aquatic_species_for_depth(depth)
	if valid_species.is_empty():
		return 0

	var species_key: String = valid_species[rng.randi() % valid_species.size()]
	_spawn_flora_entity(world, grid, proj, rng, x, y, height, species_key)
	return 1


static func _spawn_flora_entity(world: EcsWorld, _grid: TorusGrid, proj: PlanetProjector, rng: RandomNumberGenerator, x: int, y: int, height: float, species_key: String) -> void:
	var species_data: Dictionary = DefFlora.SPECIES_DATA[species_key]
	var entity := world.create_entity()

	var pos := ComPosition.new()
	pos.grid_x = x
	pos.grid_y = y
	if proj:
		var base := proj.grid_to_sphere(float(x) + 0.5, float(y) + 0.5)
		var fi := proj.world_to_cube_face(base)
		pos.world_pos = proj.cube_sphere_point(fi[0], fi[1], fi[2], height * proj.height_scale)
	world.add_component(entity, pos)

	var plant := ComPlantSpecies.new()
	plant.species_name = species_key
	plant.preferred_biomes.assign(species_data["preferred_biomes"])
	plant.water_need = species_data["water_need"]
	plant.light_need = species_data["light_need"]
	world.add_component(entity, plant)

	var growth := ComGrowth.new()
	growth.stage = DefEnums.GrowthStage.MATURE
	growth.growth_rate = species_data["growth_rate"]
	growth.growth_progress = rng.randf_range(0.5, 0.8)
	growth.age = rng.randf_range(0.0, species_data["max_age"] * 0.6)
	growth.max_age = species_data["max_age"]
	world.add_component(entity, growth)

	var seed_comp := ComSeedDispersal.new()
	seed_comp.method = species_data["seed_method"]
	seed_comp.seed_range = species_data["seed_range"]
	seed_comp.interval = species_data["seed_interval"]
	seed_comp.timer = rng.randf() * seed_comp.interval
	world.add_component(entity, seed_comp)

	var flammable := ComFlammable.new()
	flammable.flammability = species_data["flammability"]
	world.add_component(entity, flammable)

	var resource := ComResource.new()
	resource.wood_yield = species_data["wood_yield"]
	resource.food_yield = species_data["food_yield"]
	world.add_component(entity, resource)

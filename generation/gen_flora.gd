class_name GenFlora

const MAX_FLORA_PER_TILE := 1
const DENSITY_ROLL_SCALE := 0.6
const MAX_TOTAL_FLORA := 8000


static func generate(world: EcsWorld, grid: TorusGrid, biome_map: PackedInt32Array, proj: PlanetProjector) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var count := 0
	var w := grid.width
	var h := grid.height

	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			var biome: int = biome_map[idx]
			var height := grid.get_height(x, y)

			if height < GameConfig.SEA_LEVEL:
				continue

			var biome_data: Dictionary = DefBiomes.BIOME_DATA.get(biome, {})
			var tree_density: float = biome_data.get("tree_density", 0.0)
			if tree_density <= 0.0:
				continue

			if count >= MAX_TOTAL_FLORA:
				break

			var roll := rng.randf()
			if roll > tree_density * DENSITY_ROLL_SCALE:
				continue

			var valid_species := DefFlora.get_species_for_biome(biome)
			if valid_species.is_empty():
				continue

			var species_key: String = valid_species[rng.randi() % valid_species.size()]
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

			count += 1

	print("Flora generation capped at %d entities (max %d)" % [count, MAX_TOTAL_FLORA])
	return count

class_name PlanetGenerator
extends RefCounted

static func generate_terrain_step1_heightmap(
	grid: TorusGrid, 
	projector: PlanetProjector, 
	temperature_map: PackedFloat32Array, 
	moisture_map: PackedFloat32Array, 
	_biome_map: PackedInt32Array
) -> GenHeightmap:
	var heightmap_gen = GenHeightmap.new(GameConfig.WORLD_SEED)
	heightmap_gen.generate(grid, projector)

	var biome_gen := GenBiome.new(GameConfig.WORLD_SEED)
	biome_gen.generate(grid, temperature_map, moisture_map, projector)
	print("Heightmap + climate generated.")
	
	return heightmap_gen


static func generate_terrain_step2_erosion(grid: TorusGrid, moisture_map: PackedFloat32Array) -> void:
	var prebake_hydraulic := SysHydraulicErosion.new()
	prebake_hydraulic.grid = grid
	prebake_hydraulic.erosion_rate = 0.12
	prebake_hydraulic.deposition_rate = 0.15
	prebake_hydraulic.particles_per_batch = 200
	prebake_hydraulic.max_iterations = 50

	var prebake_thermal := SysThermalErosion.new()
	prebake_thermal.grid = grid
	prebake_thermal.thermal_rate = 0.01

	var prebake_coastal := SysCoastalErosion.new()
	prebake_coastal.grid = grid

	var prebake_wind := SysWindErosion.new()
	prebake_wind.grid = grid
	prebake_wind.moisture_map = moisture_map
	prebake_wind.wind_erosion_rate = 0.001

	const PREBAKE_ITERATIONS := 2
	for i in range(PREBAKE_ITERATIONS):
		for _p in range(400):
			var sx := randi() % grid.width
			var sy := randi() % grid.height
			if grid.get_height(sx, sy) > GameConfig.SEA_LEVEL:
				prebake_hydraulic._trace_particle(float(sx), float(sy))

		prebake_thermal.run_full_pass()
		prebake_coastal.run_full_pass()
		prebake_wind.run_full_pass()

	print("Prebake: %d iterations of erosion on %dx%d grid" % [PREBAKE_ITERATIONS, grid.width, grid.height])
	print("Erosion prebake complete.")


static func generate_terrain_step3_rivers(grid: TorusGrid, moisture_map: PackedFloat32Array) -> SysRiverFormation:
	var river_system = SysRiverFormation.new()
	river_system.setup(grid, null, moisture_map)
	print("River carving complete.")
	return river_system


static func generate_terrain_step4_biomes(
	grid: TorusGrid, 
	temperature_map: PackedFloat32Array, 
	moisture_map: PackedFloat32Array, 
	biome_map: PackedInt32Array,
	continentalness_map: PackedFloat32Array,
	erosion_noise_map: PackedFloat32Array,
	weirdness_map: PackedFloat32Array
) -> void:
	var w := grid.width
	var h := grid.height

	GenBiomeAssignment.assign(
		grid, temperature_map, moisture_map, biome_map,
		continentalness_map, erosion_noise_map, weirdness_map
	)

	for y in range(h):
		for x in range(w):
			grid.set_biome(x, y, biome_map[y * w + x])

	print("Biomes assigned.")


static func generate_terrain_step5_flora_fauna(world: EcsWorld, grid: TorusGrid, projector: PlanetProjector, biome_map: PackedInt32Array) -> void:
	var GenRocksScript = load("res://generation/gen_rocks.gd")
	var rock_count = GenRocksScript.generate(world, grid, projector, biome_map)
	print("Rocks generated: %d" % rock_count)

	var flora_count := GenFlora.generate(world, grid, biome_map, projector)
	print("Flora generated: %d plants." % flora_count)

	var fauna_gen := GenFauna.new()
	fauna_gen.generate(world, grid, projector, biome_map)
	print("Fauna generated.")


static func generate_terrain_step6_tribes(world: EcsWorld, grid: TorusGrid, projector: PlanetProjector) -> void:
	GenSettlement.generate(world, grid, projector)
	print("Tribes generated.")

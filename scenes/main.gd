extends Node3D

const SysDiurnalTemperatureScript = preload("res://systems/time/sys_diurnal_temperature.gd")
const SysWaterSweScript = preload("res://systems/water/sys_water_swe.gd")
const SysVolcanismScript = preload("res://systems/erosion/sys_volcanism.gd")
const SysClimateScript = preload("res://systems/weather/sys_climate.gd")
const PlanetGeneratorScript = preload("res://generation/planet_generator.gd")
const PlanetRockRendererScript = preload("res://planet/planet_rock_renderer.gd")

var world: EcsWorld
var grid: TorusGrid
var projector: PlanetProjector
var planet_mesh: PlanetMesh

var temperature_map: PackedFloat32Array
var moisture_map: PackedFloat32Array
var base_temperature_map: PackedFloat32Array
var base_moisture_map: PackedFloat32Array
var biome_map: PackedInt32Array

var time_system
var season_system
var weather_system
var diurnal_temp_system
var wind_system
var weather_visuals
var cloud_layer_node
var atmosphere_node
var rain_system
var atmo_grid
var flora_renderer
var fauna_renderer
var tribe_renderer
var rock_renderer
var chunk_scheduler
var river_system
var micro_biome_system
var biome_reassign_system
var water_grid
var water_mesh
var water_dynamics
var swe_river_map: PackedFloat32Array
var heightmap_gen
var _continentalness_map: PackedFloat32Array
var _erosion_noise_map: PackedFloat32Array
var _weirdness_map: PackedFloat32Array
var _debug_label: Label
var player_character: PlayerCharacter

var _loading_label: Label
var _is_generating: bool = true


func _ready() -> void:
	world = EcsWorld.new()
	world.name = "EcsWorld"
	add_child(world)

	print("World created. %d entities." % world.get_entity_count())

	_run_ecs_verification()
	_run_torus_grid_tests()

	# Set up visuals first so planet is visible during generation
	_build_planet()
	_add_camera_and_light()
	_add_loading_label()

	# Run heavy generation as a coroutine so each stage renders a frame
	_generate_async()


func _add_loading_label() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "LoadingCanvas"
	canvas.layer = 100
	add_child(canvas)
	_loading_label = Label.new()
	_loading_label.name = "LoadingLabel"
	_loading_label.text = "Generating planet..."
	_loading_label.add_theme_font_size_override("font_size", 22)
	_loading_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	_loading_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_loading_label.add_theme_constant_override("shadow_offset_x", 2)
	_loading_label.add_theme_constant_override("shadow_offset_y", 2)
	_loading_label.position = Vector2(20, 20)
	canvas.add_child(_loading_label)


func _set_loading_text(text: String) -> void:
	if _loading_label:
		_loading_label.text = text
	print(text)


func _generate_async() -> void:
	_set_loading_text("Generating heightmap...")
	await get_tree().process_frame

	_generate_terrain_step1_heightmap()
	planet_mesh.build_mesh()
	_set_loading_text("Eroding terrain...")
	await get_tree().process_frame

	_generate_terrain_step2_erosion()
	planet_mesh.build_mesh()
	_set_loading_text("Carving rivers...")
	await get_tree().process_frame

	_generate_terrain_step3_rivers()
	planet_mesh.set_river_map(river_system.river_map)
	planet_mesh.build_mesh()
	_set_loading_text("Assigning biomes...")
	await get_tree().process_frame

	_generate_terrain_step4_biomes()
	planet_mesh.build_mesh()
	_set_loading_text("Adding water...")
	await get_tree().process_frame

	_add_water_sphere()
	_set_loading_text("Generating flora...")
	await get_tree().process_frame

	_generate_terrain_step5_flora_fauna()
	_set_loading_text("Adding clouds & atmosphere...")
	await get_tree().process_frame

	_add_cloud_and_atmosphere()
	_add_rain_snow_particles()
	_set_loading_text("Starting systems...")
	await get_tree().process_frame

	_register_systems()
	_add_debug_hud()

	# Remove loading label
	if _loading_label:
		_loading_label.get_parent().queue_free()
		_loading_label = null
	_is_generating = false
	print("Planet generation complete!")


func _run_ecs_verification() -> void:
	var e1 := world.create_entity()
	var e2 := world.create_entity()

	var pos1 := ComPosition.new()
	pos1.grid_x = 10
	pos1.grid_y = 20
	world.add_component(e1, pos1)

	var hp1 := ComHealth.new()
	hp1.max_hp = 100.0
	hp1.current_hp = 100.0
	world.add_component(e1, hp1)

	var pos2 := ComPosition.new()
	pos2.grid_x = 50
	pos2.grid_y = 60
	world.add_component(e2, pos2)

	var with_pos := world.query(["ComPosition"])
	var with_both := world.query(["ComPosition", "ComHealth"])

	print("Verification: %d entities created." % world.get_entity_count())
	print("  query([ComPosition]) -> %d results (expected 2)" % with_pos.size())
	print("  query([ComPosition, ComHealth]) -> %d results (expected 1)" % with_both.size())

	var fetched_pos := world.get_component(e1.id, "ComPosition") as ComPosition
	if fetched_pos:
		print("  e1 position: (%d, %d) (expected 10, 20)" % [fetched_pos.grid_x, fetched_pos.grid_y])

	world.remove_entity(e2.id)
	var after_remove := world.query(["ComPosition"])
	print("  After removing e2: query([ComPosition]) -> %d results (expected 1)" % after_remove.size())
	print("ECS verification complete.")


func _run_torus_grid_tests() -> void:
	var tests := TestTorusGrid.new()
	tests.run_all()


func _build_planet() -> void:
	grid = TorusGrid.new(GameConfig.GRID_WIDTH, GameConfig.GRID_HEIGHT)
	projector = PlanetProjector.new(
		GameConfig.GRID_WIDTH,
		GameConfig.GRID_HEIGHT,
		GameConfig.PLANET_RADIUS,
		GameConfig.HEIGHT_SCALE
	)

	planet_mesh = PlanetMesh.new()
	planet_mesh.name = "PlanetMesh"
	planet_mesh.setup(grid, projector)

	var terrain_shader := load("res://shaders/terrain.gdshader") as Shader
	var terrain_mat := ShaderMaterial.new()
	terrain_mat.shader = terrain_shader
	terrain_mat.set_shader_parameter("planet_radius", GameConfig.PLANET_RADIUS)
	planet_mesh.set_material(terrain_mat)

	planet_mesh.build_mesh()
	add_child(planet_mesh)
	print("Planet mesh built: %dx%d grid -> sphere (radius %.0f)" % [
		grid.width, grid.height, projector.radius
	])


func _add_water_sphere() -> void:
	water_grid = WaterGrid.new()
	water_grid.initialize(grid.width, grid.height, grid, temperature_map)

	water_mesh = PlanetWaterMesh.new()
	water_mesh.name = "WaterMesh"
	water_mesh.setup(grid, projector, water_grid)

	var water_shader := load("res://shaders/water.gdshader") as Shader
	var water_mat := ShaderMaterial.new()
	water_mat.shader = water_shader
	water_mat.render_priority = 1
	water_mat.set_shader_parameter("planet_radius", GameConfig.PLANET_RADIUS)
	water_mesh.set_material(water_mat)

	add_child(water_mesh)
	water_mesh.build_mesh()
	print("Water grid initialized: %d water tiles." % _count_water_tiles())


func _count_water_tiles() -> int:
	var count := 0
	if water_grid:
		for i in range(water_grid.width * water_grid.height):
			if water_grid.water_depth[i] > 0.001:
				count += 1
	return count


func _add_cloud_and_atmosphere() -> void:
	atmo_grid = AtmosphereGrid.new()
	atmo_grid.initialize_from_biome(
		base_temperature_map, base_moisture_map,
		GameConfig.GRID_WIDTH, GameConfig.GRID_HEIGHT, projector
	)

	cloud_layer_node = PlanetCloudLayer.new()
	cloud_layer_node.name = "PlanetCloudLayer"
	cloud_layer_node.setup(projector, atmo_grid)
	add_child(cloud_layer_node)

	print("Cloud layer added (volumetric).")


func _add_rain_snow_particles() -> void:
	rain_system = PlanetRain.new()
	rain_system.name = "PlanetRain"
	rain_system.setup(projector, atmo_grid)
	var cam := get_node_or_null("DebugCamera") as Camera3D
	if cam:
		rain_system.set_camera(cam)
	add_child(rain_system)
	print("Planet rain system added.")


func _add_camera_and_light() -> void:
	var camera := PlanetCamera.new()
	camera.name = "DebugCamera"
	camera.orbit_distance = GameConfig.PLANET_RADIUS * 3.0
	camera.orbit_min = GameConfig.PLANET_RADIUS * 1.1
	camera.orbit_max = GameConfig.PLANET_RADIUS * 10.0
	camera.far = GameConfig.PLANET_RADIUS * 20.0
	camera.projector = projector
	camera.grid = grid
	camera.current = true
	
	player_character = PlayerCharacter.new()
	player_character.name = "PlayerCharacter"
	player_character.setup(projector, grid, float(GameConfig.GRID_WIDTH) * 0.5, float(GameConfig.GRID_HEIGHT) * 0.5)
	add_child(player_character)
	
	camera.player_character = player_character
	
	add_child(camera)

	var light := DirectionalLight3D.new()
	light.name = "SunLight"
	# Start at hour 6 (dawn): elevation = (6/24)*360 - 90 = 0°
	light.rotation_degrees = Vector3(0.0, 30.0, 23.0)
	light.light_energy = 0.05
	light.shadow_enabled = true
	add_child(light)

	var moon_light := DirectionalLight3D.new()
	moon_light.name = "MoonLight"
	moon_light.light_color = Color(0.6, 0.7, 0.9)
	moon_light.light_energy = 0.05
	moon_light.shadow_enabled = true
	add_child(moon_light)

	var env := WorldEnvironment.new()
	env.name = "WorldEnv"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.02, 0.05)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.15, 0.15, 0.2)
	environment.ambient_light_energy = 0.08
	env.environment = environment
	add_child(env)

	print("Camera and light added.")


func _generate_terrain_step1_heightmap() -> void:
	var total := grid.width * grid.height
	temperature_map = PackedFloat32Array()
	temperature_map.resize(total)
	moisture_map = PackedFloat32Array()
	moisture_map.resize(total)
	biome_map = PackedInt32Array()
	biome_map.resize(total)

	heightmap_gen = PlanetGeneratorScript.generate_terrain_step1_heightmap(
		grid, projector, temperature_map, moisture_map, biome_map
	)

	_continentalness_map = heightmap_gen.continentalness_map
	_erosion_noise_map = heightmap_gen.erosion_map
	_weirdness_map = heightmap_gen.weirdness_map


func _generate_terrain_step2_erosion() -> void:
	PlanetGeneratorScript.generate_terrain_step2_erosion(grid, moisture_map)


func _generate_terrain_step3_rivers() -> void:
	river_system = PlanetGeneratorScript.generate_terrain_step3_rivers(grid, moisture_map)


func _generate_terrain_step4_biomes() -> void:
	base_temperature_map = temperature_map.duplicate()
	base_moisture_map = moisture_map.duplicate()

	PlanetGeneratorScript.generate_terrain_step4_biomes(
		grid, temperature_map, moisture_map, biome_map,
		_continentalness_map, _erosion_noise_map, _weirdness_map
	)

	planet_mesh.set_biome_map(biome_map)
	planet_mesh.set_river_map(river_system.river_map)


func _generate_terrain_step5_flora_fauna() -> void:
	PlanetGeneratorScript.generate_terrain_step5_flora_fauna(world, grid, projector, biome_map)

	flora_renderer = PlanetFloraRenderer.new()
	flora_renderer.name = "FloraRenderer"
	flora_renderer.setup(projector, grid, world)
	add_child(flora_renderer)

	fauna_renderer = PlanetFaunaRenderer.new()
	fauna_renderer.name = "FaunaRenderer"
	fauna_renderer.setup(projector, grid, world)
	add_child(fauna_renderer)
	
	rock_renderer = PlanetRockRendererScript.new()
	rock_renderer.name = "RockRenderer"
	rock_renderer.setup(projector, grid, world)
	add_child(rock_renderer)


func _generate_terrain_step6_tribes() -> void:
	PlanetGeneratorScript.generate_terrain_step6_tribes(world, grid, projector)

	tribe_renderer = PlanetTribeRenderer.new()
	tribe_renderer.name = "TribeRenderer"
	tribe_renderer.setup(projector, grid, world)
	add_child(tribe_renderer)


func _register_systems() -> void:
	var sun := get_node("SunLight") as DirectionalLight3D
	var moon := get_node("MoonLight") as DirectionalLight3D
	var env := get_node("WorldEnv").environment as Environment

	time_system = SysTime.new()
	time_system.sun_light = sun
	time_system.moon_light = moon
	time_system.environment = env
	world.add_system(time_system)
	
	var sys_climate = SysClimateScript.new()
	sys_climate.setup(grid, projector, base_temperature_map, base_moisture_map, GameConfig.WORLD_SEED)
	world.add_system(sys_climate)

	season_system = SysSeason.new()
	season_system.setup(time_system, temperature_map, moisture_map, base_temperature_map, base_moisture_map)
	world.add_system(season_system)

	weather_system = SysWeather.new()
	weather_system.setup(time_system, grid, temperature_map, moisture_map)

	diurnal_temp_system = SysDiurnalTemperatureScript.new()
	diurnal_temp_system.setup(time_system, weather_system, grid, temperature_map, base_temperature_map)
	world.add_system(diurnal_temp_system)
	world.add_system(weather_system)

	wind_system = SysWind.new()
	wind_system.weather_system = weather_system
	world.add_system(wind_system)

	var precip_system := SysPrecipitation.new()
	precip_system.setup(weather_system, grid, moisture_map, temperature_map)
	world.add_system(precip_system)

	var hydraulic := SysHydraulicErosion.new()
	hydraulic.setup(grid, time_system, weather_system)
	world.add_system(hydraulic)

	var thermal := SysThermalErosion.new()
	thermal.setup(grid, time_system)
	world.add_system(thermal)

	var coastal := SysCoastalErosion.new()
	coastal.setup(grid, wind_system, time_system)
	world.add_system(coastal)

	var wind_ero := SysWindErosion.new()
	wind_ero.setup(grid, wind_system, moisture_map, weather_system)
	world.add_system(wind_ero)

	var tectonic := SysTectonicUplift.new()
	tectonic.setup(grid, heightmap_gen, projector)
	world.add_system(tectonic)

	var volcanism := SysVolcanismScript.new()
	volcanism.setup(grid, heightmap_gen, projector, temperature_map)
	world.add_system(volcanism)

	river_system.time_system = time_system
	world.add_system(river_system)

	micro_biome_system = SysMicroBiome.new()
	micro_biome_system.setup(grid, projector, temperature_map, moisture_map, biome_map, river_system.river_map)
	world.add_system(micro_biome_system)

	biome_reassign_system = SysBiomeReassign.new()
	biome_reassign_system.setup(grid, temperature_map, moisture_map, biome_map, _continentalness_map, _erosion_noise_map, _weirdness_map)
	world.add_system(biome_reassign_system)

	chunk_scheduler = ChunkScheduler.new()
	chunk_scheduler.name = "ChunkScheduler"
	chunk_scheduler.setup(grid, 4, 0.5)
	chunk_scheduler.register_processor(hydraulic.process_chunk)
	chunk_scheduler.register_processor(thermal.process_chunk)
	chunk_scheduler.register_processor(coastal.process_chunk)
	chunk_scheduler.register_processor(wind_ero.process_chunk)
	add_child(chunk_scheduler)

	var atmo_fluid := SysAtmosphereFluid.new()
	atmo_fluid.atmo_grid = atmo_grid
	atmo_fluid.wind_system = wind_system
	atmo_fluid.weather_system = weather_system
	world.add_system(atmo_fluid)

	weather_visuals = SysWeatherVisuals.new()
	weather_visuals.weather_system = weather_system
	weather_visuals.wind_system = wind_system
	weather_visuals.time_system = time_system
	weather_visuals.cloud_layer = cloud_layer_node
	weather_visuals.atmosphere_shell = atmosphere_node
	weather_visuals.planet_rain = rain_system
	weather_visuals.atmo_grid = atmo_grid
	weather_visuals.sun_light = get_node("SunLight") as DirectionalLight3D
	world.add_system(weather_visuals)

	var fire_spread = SysFireSpread.new()
	fire_spread.setup(grid, weather_system, wind_system)
	world.add_system(fire_spread)

	var SysConstructionClass = load("res://systems/tribe/sys_construction.gd")
	var construction = SysConstructionClass.new()
	construction.setup(grid)
	world.add_system(construction)
	
	var SysCombatClass = load("res://systems/sys_combat.gd")
	var combat_sys = SysCombatClass.new()
	combat_sys.setup(grid)
	world.add_system(combat_sys)

	var brave_ai = SysBraveAi.new()
	brave_ai.setup(grid)
	world.add_system(brave_ai)

	var tribal_ai = SysTribalAi.new()
	tribal_ai.setup(grid, projector)
	world.add_system(tribal_ai)

	var fauna_ai = SysFaunaAi.new()
	fauna_ai.setup(grid, projector, time_system, water_grid)
	world.add_system(fauna_ai)

	var fauna_hunger := SysHunger.new()
	fauna_hunger.setup(grid, water_grid)
	world.add_system(fauna_hunger)

	var predator_prey := SysPredatorPrey.new()
	predator_prey.setup(grid, projector)
	world.add_system(predator_prey)

	var herd_system := SysHerd.new()
	herd_system.setup(grid, projector)
	world.add_system(herd_system)

	var reproduction := SysReproduction.new()
	reproduction.setup(grid, projector)
	world.add_system(reproduction)

	var migration := SysMigration.new()
	migration.setup(grid, projector, time_system)
	world.add_system(migration)

	if GameConfig.USE_SWE_WATER:
		water_dynamics = SysWaterSweScript.new()
		water_dynamics.setup(grid, water_grid, weather_system, temperature_map)
		swe_river_map = water_dynamics.river_map
		world.add_system(water_dynamics)
	else:
		water_dynamics = SysWaterDynamics.new()
		water_dynamics.setup(grid, water_grid, weather_system, wind_system, temperature_map, moisture_map, river_system)
		world.add_system(water_dynamics)

	print("All systems registered (including flora + fauna + water).")


func _add_debug_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "DebugHUD"
	add_child(canvas)

	_debug_label = Label.new()
	_debug_label.position = Vector2(10, 10)
	_debug_label.add_theme_font_size_override("font_size", 16)
	_debug_label.add_theme_color_override("font_color", Color.WHITE)
	canvas.add_child(_debug_label)


var _mesh_rebuild_timer: float = 0.0
var _mesh_rebuild_interval: float = 30.0


func _prebake_erosion(moist: PackedFloat32Array) -> void:
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
	prebake_wind.moisture_map = moist
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


func _process(delta: float) -> void:
	if _is_generating:
		return
	_mesh_rebuild_timer += delta
	if _mesh_rebuild_timer >= _mesh_rebuild_interval or grid.is_dirty:
		_mesh_rebuild_timer = 0.0
		grid.is_dirty = false
		planet_mesh.set_biome_map(biome_map)
		if GameConfig.USE_SWE_WATER and not swe_river_map.is_empty():
			planet_mesh.set_river_map(swe_river_map)
		elif river_system:
			planet_mesh.set_river_map(river_system.river_map)
		if micro_biome_system:
			planet_mesh.set_micro_biome_map(micro_biome_system.micro_biome_map)
		planet_mesh.build_mesh()
		if water_mesh:
			water_mesh.build_mesh()

	if chunk_scheduler:
		var cam := get_viewport().get_camera_3d()
		if cam and projector:
			var grid_pos := projector.sphere_to_grid(cam.global_position)
			chunk_scheduler.set_camera_grid_pos(float(grid_pos.x), float(grid_pos.y))

	if time_system and _debug_label:
		var weather_str: String = weather_system.get_state_string() if weather_system else "?"
		var wind_str: String = wind_system.get_wind_string() if wind_system else "?"
		_debug_label.text = "%s | %s | Wind: %s | FPS: %d | Entities: %d" % [
			time_system.get_time_string(),
			weather_str,
			wind_str,
			Engine.get_frames_per_second(),
			world.get_entity_count()
		]

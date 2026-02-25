extends Node3D

var world: EcsWorld
var grid: TorusGrid
var projector: PlanetProjector
var planet_mesh: PlanetMesh

var temperature_map: PackedFloat32Array
var moisture_map: PackedFloat32Array
var base_temperature_map: PackedFloat32Array
var base_moisture_map: PackedFloat32Array

var time_system: SysTime
var season_system: SysSeason
var weather_system: SysWeather
var wind_system: SysWind
var weather_visuals: SysWeatherVisuals
var cloud_layer_node: PlanetCloudLayer
var atmosphere_node: PlanetAtmosphere
var _debug_label: Label


func _ready() -> void:
	world = EcsWorld.new()
	world.name = "EcsWorld"
	add_child(world)

	print("World created. %d entities." % world.get_entity_count())

	_run_ecs_verification()
	_run_torus_grid_tests()
	_build_planet()
	_generate_terrain()
	_add_water_sphere()
	_add_cloud_and_atmosphere()
	_add_camera_and_light()
	_add_rain_snow_particles()
	_register_systems()
	_add_debug_hud()


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
	planet_mesh.material_override = terrain_mat

	planet_mesh.build_mesh()
	add_child(planet_mesh)
	print("Planet mesh built: %dx%d grid -> sphere (radius %.0f)" % [
		grid.width, grid.height, projector.radius
	])


func _add_water_sphere() -> void:
	var water_mesh_inst := MeshInstance3D.new()
	water_mesh_inst.name = "WaterSphere"

	var sphere := SphereMesh.new()
	var water_radius := GameConfig.PLANET_RADIUS + GameConfig.SEA_LEVEL * GameConfig.HEIGHT_SCALE
	sphere.radius = water_radius
	sphere.height = water_radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	water_mesh_inst.mesh = sphere

	var water_shader := load("res://shaders/water.gdshader") as Shader
	var water_mat := ShaderMaterial.new()
	water_mat.shader = water_shader
	water_mat.set_shader_parameter("water_color", Color(0.05, 0.15, 0.5, 0.7))
	water_mat.set_shader_parameter("wave_speed", 1.0)
	water_mat.set_shader_parameter("wave_height", 0.05)
	water_mesh_inst.material_override = water_mat

	add_child(water_mesh_inst)
	print("Water sphere added.")


func _add_cloud_and_atmosphere() -> void:
	cloud_layer_node = PlanetCloudLayer.new()
	cloud_layer_node.name = "PlanetCloudLayer"
	cloud_layer_node.setup(GameConfig.PLANET_RADIUS)
	add_child(cloud_layer_node)

	atmosphere_node = PlanetAtmosphere.new()
	atmosphere_node.name = "PlanetAtmosphere"
	atmosphere_node.setup(GameConfig.PLANET_RADIUS)
	add_child(atmosphere_node)

	print("Cloud layer and atmosphere added.")


func _add_rain_snow_particles() -> void:
	var camera := get_node("DebugCamera") as Camera3D
	if not camera:
		return

	var rain := GPUParticles3D.new()
	rain.name = "RainParticles"
	rain.amount = 500
	rain.emitting = false
	rain.lifetime = 1.5
	rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))

	var rain_mat := ParticleProcessMaterial.new()
	rain_mat.direction = Vector3(0, -1, 0)
	rain_mat.spread = 5.0
	rain_mat.initial_velocity_min = 40.0
	rain_mat.initial_velocity_max = 60.0
	rain_mat.gravity = Vector3(0, -20, 0)
	rain.process_material = rain_mat

	var rain_mesh := QuadMesh.new()
	rain_mesh.size = Vector2(0.05, 0.4)
	rain.draw_pass_1 = rain_mesh

	var rain_draw_mat := StandardMaterial3D.new()
	rain_draw_mat.albedo_color = Color(0.7, 0.8, 1.0, 0.4)
	rain_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_mesh.material = rain_draw_mat

	camera.add_child(rain)
	rain.position = Vector3(0, 15, 0)

	var snow := GPUParticles3D.new()
	snow.name = "SnowParticles"
	snow.amount = 300
	snow.emitting = false
	snow.lifetime = 4.0
	snow.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))

	var snow_mat := ParticleProcessMaterial.new()
	snow_mat.direction = Vector3(0, -1, 0)
	snow_mat.spread = 30.0
	snow_mat.initial_velocity_min = 5.0
	snow_mat.initial_velocity_max = 10.0
	snow_mat.gravity = Vector3(0, -3, 0)
	snow.process_material = snow_mat

	var snow_mesh := SphereMesh.new()
	snow_mesh.radius = 0.06
	snow_mesh.height = 0.12
	snow.draw_pass_1 = snow_mesh

	var snow_draw_mat := StandardMaterial3D.new()
	snow_draw_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.8)
	snow_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	snow_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	snow_mesh.material = snow_draw_mat

	camera.add_child(snow)
	snow.position = Vector3(0, 15, 0)

	print("Rain and snow particle systems added.")


func _add_camera_and_light() -> void:
	var camera := PlanetCamera.new()
	camera.name = "DebugCamera"
	camera.orbit_distance = GameConfig.PLANET_RADIUS * 3.0
	camera.orbit_min = GameConfig.PLANET_RADIUS * 1.1
	camera.orbit_max = GameConfig.PLANET_RADIUS * 10.0
	camera.far = GameConfig.PLANET_RADIUS * 20.0
	camera.current = true
	add_child(camera)

	var light := DirectionalLight3D.new()
	light.name = "SunLight"
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	add_child(light)

	var env := WorldEnvironment.new()
	env.name = "WorldEnv"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.02, 0.05)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.15, 0.15, 0.2)
	environment.ambient_light_energy = 0.3
	env.environment = environment
	add_child(env)

	print("Camera and light added.")


func _generate_terrain() -> void:
	var heightmap_gen := GenHeightmap.new(GameConfig.WORLD_SEED)
	heightmap_gen.generate(grid)

	var w := grid.width
	var h := grid.height
	var total := w * h

	temperature_map = PackedFloat32Array()
	temperature_map.resize(total)
	moisture_map = PackedFloat32Array()
	moisture_map.resize(total)
	var biome_map_data := PackedInt32Array()
	biome_map_data.resize(total)

	var biome_gen := GenBiome.new(GameConfig.WORLD_SEED)
	biome_gen.generate(grid, temperature_map, moisture_map)

	base_temperature_map = temperature_map.duplicate()
	base_moisture_map = moisture_map.duplicate()

	GenBiomeAssignment.assign(grid, temperature_map, moisture_map, biome_map_data)

	planet_mesh.set_biome_map(biome_map_data)
	planet_mesh.build_mesh()


func _register_systems() -> void:
	var sun := get_node("SunLight") as DirectionalLight3D

	time_system = SysTime.new()
	time_system.sun_light = sun
	world.add_system(time_system)

	season_system = SysSeason.new()
	season_system.setup(time_system, temperature_map, moisture_map, base_temperature_map, base_moisture_map)
	world.add_system(season_system)

	weather_system = SysWeather.new()
	weather_system.time_system = time_system
	world.add_system(weather_system)

	wind_system = SysWind.new()
	wind_system.weather_system = weather_system
	world.add_system(wind_system)

	var precip_system := SysPrecipitation.new()
	precip_system.setup(weather_system, grid, moisture_map, temperature_map)
	world.add_system(precip_system)

	var hydraulic := SysHydraulicErosion.new()
	hydraulic.setup(grid, time_system)
	world.add_system(hydraulic)

	var thermal := SysThermalErosion.new()
	thermal.setup(grid, time_system)
	world.add_system(thermal)

	var coastal := SysCoastalErosion.new()
	coastal.setup(grid, wind_system, time_system)
	world.add_system(coastal)

	var wind_ero := SysWindErosion.new()
	wind_ero.setup(grid, wind_system, moisture_map)
	world.add_system(wind_ero)

	var rivers := SysRiverFormation.new()
	rivers.setup(grid, time_system, moisture_map)
	world.add_system(rivers)

	weather_visuals = SysWeatherVisuals.new()
	weather_visuals.weather_system = weather_system
	weather_visuals.wind_system = wind_system
	weather_visuals.time_system = time_system
	weather_visuals.cloud_layer = cloud_layer_node
	weather_visuals.atmosphere_shell = atmosphere_node
	weather_visuals.sun_light = get_node("SunLight") as DirectionalLight3D
	var env_node := get_node("WorldEnv") as WorldEnvironment
	if env_node:
		weather_visuals.environment = env_node.environment
	var cam := get_node("DebugCamera")
	if cam:
		weather_visuals.rain_particles = cam.get_node_or_null("RainParticles") as GPUParticles3D
		weather_visuals.snow_particles = cam.get_node_or_null("SnowParticles") as GPUParticles3D
	world.add_system(weather_visuals)

	print("All systems registered.")


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
var _mesh_rebuild_interval: float = 5.0


func _process(delta: float) -> void:
	_mesh_rebuild_timer += delta
	if _mesh_rebuild_timer >= _mesh_rebuild_interval:
		_mesh_rebuild_timer = 0.0
		planet_mesh.build_mesh()

	if time_system and _debug_label:
		var weather_str := weather_system.get_state_string() if weather_system else "?"
		var wind_str := wind_system.get_wind_string() if wind_system else "?"
		_debug_label.text = "%s | %s | Wind: %s | FPS: %d | Entities: %d" % [
			time_system.get_time_string(),
			weather_str,
			wind_str,
			Engine.get_frames_per_second(),
			world.get_entity_count()
		]

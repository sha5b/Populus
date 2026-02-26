class_name GenRocks

const ComRockScript = preload("res://components/com_rock.gd")
const DefRocksScript = preload("res://data/def_rocks.gd")

static func generate(world: EcsWorld, grid: TorusGrid, projector: PlanetProjector, _biome_map: PackedInt32Array) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(GameConfig.WORLD_SEED) + 20000

	var count := 0
	var w := grid.width
	var h := grid.height
	@warning_ignore("integer_division")
	var max_rocks := int((GameConfig.GRID_WIDTH * GameConfig.GRID_HEIGHT) / 8) # Some reasonable max

	for i in range(max_rocks):
		var x := rng.randi() % w
		var y := rng.randi() % h
		
		var terrain_h := grid.get_height(x, y)
		if terrain_h < GameConfig.SEA_LEVEL:
			continue # No rocks generated underwater right now
		
		# More rocks on mountains and ridges, less in fertile plains
		var rock_chance := 0.05
		if terrain_h > 0.6:
			rock_chance += 0.2
		if terrain_h > 0.8:
			rock_chance += 0.4
			
		var sediment := grid.get_sediment(x, y)
		if sediment < 0.05:
			rock_chance += 0.3 # Exposed bedrock has lots of loose rocks

		if rng.randf() > rock_chance:
			continue

		var eid := world.create_entity()

		var pos := ComPosition.new()
		pos.grid_x = x
		pos.grid_y = y
		# Add small jitter to make them look scattered naturally
		pos.world_pos = projector.grid_to_sphere(float(x) + rng.randf(), float(y) + rng.randf(), terrain_h)
		world.add_component(eid, pos)

		var rock := ComRockScript.new()
		var type_keys := DefRocksScript.ROCK_DATA.keys()
		rock.rock_type = type_keys[rng.randi() % type_keys.size()]
		var data: Dictionary = DefRocksScript.ROCK_DATA[rock.rock_type]
		rock.scale = rng.randf_range(data.get("scale_min", 0.5), data.get("scale_max", 2.0))
		world.add_component(eid, rock)

		count += 1

	return count

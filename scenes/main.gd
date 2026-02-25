extends Node

var world: EcsWorld


func _ready() -> void:
	world = EcsWorld.new()
	world.name = "EcsWorld"
	add_child(world)

	world.add_system(SysTest.new())

	print("World created. %d entities." % world.get_entity_count())

	_run_ecs_verification()


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

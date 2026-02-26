extends System
class_name SysConstruction

var grid: TorusGrid

var _timer: float = 0.0
const TICK_INTERVAL := 0.5


func setup(g: TorusGrid) -> void:
	grid = g


func update(world: Node, delta: float) -> void:
	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer -= TICK_INTERVAL

	var ecs := world as EcsWorld
	if ecs == null:
		return

	var constructions := ecs.get_components("ComConstruction")
	var positions := ecs.get_components("ComPosition")
	var followers := ecs.get_components("ComFollower")

	for eid in constructions.keys():
		var constr: ComConstruction = constructions[eid]
		if constr.progress >= 1.0:
			continue

		if not positions.has(eid):
			continue
		var p: ComPosition = positions[eid]

		# Check if we have enough wood to even build
		if constr.consumed_wood < constr.required_wood:
			continue

		# Count nearby builders
		var builder_count := 0
		for f_eid in followers.keys():
			var f: ComFollower = followers[f_eid]
			if f.state == DefEnums.AIState.BUILDING and f.target_entity == eid:
				var fp: ComPosition = ecs.get_component(f_eid, "ComPosition")
				if fp:
					var dist := absi(fp.grid_x - p.grid_x) + absi(fp.grid_y - p.grid_y)
					if dist <= 1:
						builder_count += 1

		if builder_count > 0:
			# 0.1 progress per tick per builder, so it takes ~5 seconds for 1 builder to finish
			var speed := builder_count * 0.1
			constr.progress += speed
			
			if constr.progress >= 1.0:
				constr.progress = 1.0
				# Optionally free the builder braves from their task so they don't get stuck
				for f_eid in followers.keys():
					var f: ComFollower = followers[f_eid]
					if f.state == DefEnums.AIState.BUILDING and f.target_entity == eid:
						f.state = DefEnums.AIState.IDLE
						f.target_entity = -1

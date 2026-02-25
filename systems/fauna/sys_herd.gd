extends System
class_name SysHerd

var grid: TorusGrid = null
var projector: PlanetProjector = null

const TICK_INTERVAL := 1.0
var _timer := 0.0

const SEPARATION_WEIGHT := 1.5
const COHESION_WEIGHT := 0.8
const ALIGNMENT_WEIGHT := 0.5


func setup(g: TorusGrid, proj: PlanetProjector) -> void:
	grid = g
	projector = proj


func update(world: Node, delta: float) -> void:
	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer -= TICK_INTERVAL

	var ecs := world as EcsWorld
	var entities := ecs.query(["ComHerd", "ComFaunaSpecies", "ComPosition", "ComAiState"])

	var herds: Dictionary = {}
	for eid in entities:
		var herd: ComHerd = ecs.get_component(eid, "ComHerd") as ComHerd
		if not herds.has(herd.herd_id):
			herds[herd.herd_id] = []
		herds[herd.herd_id].append(eid)

	for herd_id in herds:
		var members: Array = herds[herd_id]
		if members.size() < 2:
			continue
		_apply_boids(ecs, members)


func _apply_boids(ecs: EcsWorld, members: Array) -> void:
	if grid == null or projector == null:
		return

	var positions: Array[Vector2i] = []
	var center := Vector2.ZERO

	for eid in members:
		var pos: ComPosition = ecs.get_component(eid, "ComPosition") as ComPosition
		positions.append(Vector2i(pos.grid_x, pos.grid_y))
		center += Vector2(pos.grid_x, pos.grid_y)
	center /= float(members.size())

	for i in range(members.size()):
		var eid: int = members[i]
		var ai: ComAiState = ecs.get_component(eid, "ComAiState") as ComAiState
		if ai.current_state == DefEnums.AIState.FLEEING or ai.current_state == DefEnums.AIState.SLEEPING:
			continue

		var pos: ComPosition = ecs.get_component(eid, "ComPosition") as ComPosition
		var herd: ComHerd = ecs.get_component(eid, "ComHerd") as ComHerd
		var my_pos := Vector2(pos.grid_x, pos.grid_y)

		var sep := Vector2.ZERO
		for j in range(positions.size()):
			if i == j:
				continue
			var other := Vector2(positions[j].x, positions[j].y)
			var diff := _wrap_diff(my_pos, other)
			var dist := diff.length()
			if dist < herd.separation_dist and dist > 0.01:
				sep -= diff / dist

		var cohesion := _wrap_diff(center, my_pos)
		if cohesion.length() > herd.cohesion_dist:
			cohesion = cohesion.normalized()

		var steer := sep * SEPARATION_WEIGHT + cohesion * COHESION_WEIGHT
		if steer.length() < 0.3:
			continue

		steer = steer.normalized()
		var nx := grid.wrap_x(pos.grid_x + roundi(steer.x))
		var ny := grid.wrap_y(pos.grid_y + roundi(steer.y))

		var species: ComFaunaSpecies = ecs.get_component(eid, "ComFaunaSpecies") as ComFaunaSpecies
		var target_h := grid.get_height(nx, ny)
		if not species.is_aquatic and target_h < GameConfig.SEA_LEVEL:
			continue
		if species.is_aquatic and target_h >= GameConfig.SEA_LEVEL:
			continue

		pos.grid_x = nx
		pos.grid_y = ny
		var dir := projector.grid_to_sphere(float(nx) + 0.5, float(ny) + 0.5).normalized()
		pos.world_pos = dir * (projector.radius + target_h * projector.height_scale)


func _wrap_diff(from: Vector2, to: Vector2) -> Vector2:
	if grid == null:
		return to - from
	var dx := to.x - from.x
	var dy := to.y - from.y
	if absf(dx) > grid.width * 0.5:
		dx -= signf(dx) * grid.width
	if absf(dy) > grid.height * 0.5:
		dy -= signf(dy) * grid.height
	return Vector2(dx, dy)

extends System
class_name SysHerd

var grid: TorusGrid = null
var projector: PlanetProjector = null

const TICK_INTERVAL := 2.0
const MAX_HERD_PROCESS := 8
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
	var entities := ecs.query(["ComHerd", "ComFaunaSpecies", "ComPosition", "ComAiState", "ComIntelligence"])

	var herds: Dictionary = {}
	var herd_centers: Dictionary = {}
	var herd_species: Dictionary = {}
	
	for eid in entities:
		var herd: ComHerd = ecs.get_component(eid, "ComHerd") as ComHerd
		var species: ComFaunaSpecies = ecs.get_component(eid, "ComFaunaSpecies") as ComFaunaSpecies
		var pos: ComPosition = ecs.get_component(eid, "ComPosition") as ComPosition
		
		if not herds.has(herd.herd_id):
			herds[herd.herd_id] = []
			herd_centers[herd.herd_id] = Vector2.ZERO
			herd_species[herd.herd_id] = species.species_key
			
		herds[herd.herd_id].append(eid)
		herd_centers[herd.herd_id] += Vector2(pos.grid_x, pos.grid_y)

	for herd_id in herds:
		var members: Array = herds[herd_id]
		herd_centers[herd_id] /= float(members.size())
		
	# FISSION-FUSION LOGIC
	_process_fission_fusion(ecs, herds, herd_centers, herd_species)

	for herd_id in herds:
		var members: Array = herds[herd_id]
		if members.size() < 2:
			continue
		if members.size() > MAX_HERD_PROCESS:
			members = members.slice(0, MAX_HERD_PROCESS)
		_apply_boids(ecs, members)


func _process_fission_fusion(ecs: EcsWorld, herds: Dictionary, centers: Dictionary, species_map: Dictionary) -> void:
	var merge_dist := 15.0
	
	# 1. Fusion (Merge close herds of the same species)
	var merged_herds := []
	var herd_ids := herds.keys()
	for i in range(herd_ids.size()):
		var id_a: int = herd_ids[i]
		if id_a in merged_herds:
			continue
			
		for j in range(i + 1, herd_ids.size()):
			var id_b: int = herd_ids[j]
			if id_b in merged_herds:
				continue
				
			if species_map[id_a] != species_map[id_b]:
				continue
				
			var dist := _wrap_diff(centers[id_a], centers[id_b]).length()
			if dist < merge_dist:
				# Merge B into A
				for eid in herds[id_b]:
					var h: ComHerd = ecs.get_component(eid, "ComHerd")
					h.herd_id = id_a
					herds[id_a].append(eid)
				herds[id_b].clear()
				merged_herds.append(id_b)
				
	# 2. Fission (Split herds that get too large)
	var max_herd_size := 15
	var next_new_id := 0
	for id in herds.keys():
		var int_id := id as int
		if int_id > next_new_id:
			next_new_id = int_id
	next_new_id += 1
	
	for id in herds.keys():
		var members: Array = herds[id]
		if members.size() > max_herd_size:
			var split_count := members.size() / 2
			var new_herd_id := next_new_id
			next_new_id += 1
			
			# Move half the members to a new herd
			for k in range(split_count):
				var eid: int = members.pop_back()
				var h: ComHerd = ecs.get_component(eid, "ComHerd")
				h.herd_id = new_herd_id


func _apply_boids(ecs: EcsWorld, members: Array) -> void:
	if grid == null or projector == null:
		return

	var positions: Array[Vector2i] = []
	var center := Vector2.ZERO
	var leader_idx := -1
	var leader_pos := Vector2.ZERO

	for eid in members:
		var pos: ComPosition = ecs.get_component(eid, "ComPosition") as ComPosition
		positions.append(Vector2i(pos.grid_x, pos.grid_y))
		center += Vector2(pos.grid_x, pos.grid_y)
		var iq: ComIntelligence = ecs.get_component(eid, "ComIntelligence") as ComIntelligence
		if iq.is_leader and leader_idx == -1:
			leader_idx = positions.size() - 1
			leader_pos = Vector2(pos.grid_x, pos.grid_y)
	center /= float(members.size())

	for i in range(members.size()):
		var eid: int = members[i]
		var iq: ComIntelligence = ecs.get_component(eid, "ComIntelligence") as ComIntelligence
		if iq.is_leader:
			# Leaders don't flock to followers; they follow their own AI (foraging/wandering)
			continue

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

		var target := center
		if leader_idx != -1 and iq.iq >= 0.3:
			# Medium/High IQ animals follow the leader instead of the geometric center
			target = leader_pos

		var cohesion := _wrap_diff(target, my_pos)
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

		pos.prev_world_pos = pos.world_pos
		pos.lerp_t = 0.0
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

extends System
class_name SysPredatorPrey

var grid: TorusGrid = null
var projector: PlanetProjector = null

const TICK_INTERVAL := 1.5
var _timer := 0.0
const KILL_RANGE := 2


func setup(g: TorusGrid, proj: PlanetProjector) -> void:
	grid = g
	projector = proj


func update(world: Node, delta: float) -> void:
	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer -= TICK_INTERVAL

	var ecs := world as EcsWorld

	var predators := ecs.query(["ComPredator", "ComFaunaSpecies", "ComPosition", "ComAiState", "ComHunger"])
	var prey_entities := ecs.query(["ComPrey", "ComFaunaSpecies", "ComPosition", "ComHealth"])

	var prey_by_species: Dictionary = {}
	for pid in prey_entities:
		var ps: ComFaunaSpecies = ecs.get_component(pid, "ComFaunaSpecies") as ComFaunaSpecies
		if not prey_by_species.has(ps.species_key):
			prey_by_species[ps.species_key] = []
		prey_by_species[ps.species_key].append(pid)

	for eid in predators:
		var ai: ComAiState = ecs.get_component(eid, "ComAiState") as ComAiState
		if ai.current_state != DefEnums.AIState.HUNTING:
			continue

		var pred: ComPredator = ecs.get_component(eid, "ComPredator") as ComPredator
		var p_pos: ComPosition = ecs.get_component(eid, "ComPosition") as ComPosition
		var hunger: ComHunger = ecs.get_component(eid, "ComHunger") as ComHunger

		var target_id := _find_nearest_prey(ecs, p_pos, pred, prey_by_species)
		if target_id < 0:
			ai.current_state = DefEnums.AIState.WANDERING
			ai.state_timer = 0.0
			continue

		var t_pos: ComPosition = ecs.get_component(target_id, "ComPosition") as ComPosition
		var dist := _grid_distance(p_pos, t_pos)

		if dist <= KILL_RANGE:
			var t_health: ComHealth = ecs.get_component(target_id, "ComHealth") as ComHealth
			t_health.current_hp -= pred.attack_damage
			if t_health.current_hp <= 0.0:
				hunger.current = maxf(hunger.current - hunger.max_hunger * 0.6, 0.0)
				ecs.remove_entity(target_id)
				ai.current_state = DefEnums.AIState.IDLE
				ai.state_timer = 0.0
		else:
			_move_toward(p_pos, t_pos)

		var t_prey: ComPrey = ecs.get_component(target_id, "ComPrey") as ComPrey
		if t_prey != null:
			t_prey.is_fleeing = true

	_run_flee(ecs, prey_entities)


func _find_nearest_prey(ecs: EcsWorld, hunter_pos: ComPosition, pred: ComPredator, prey_by_species: Dictionary) -> int:
	var best_id := -1
	var best_dist := pred.hunt_range + 1.0
	for prey_key in pred.prey_types:
		if not prey_by_species.has(prey_key):
			continue
		for pid in prey_by_species[prey_key]:
			var pp: ComPosition = ecs.get_component(pid, "ComPosition") as ComPosition
			if pp == null:
				continue
			var d := _grid_distance(hunter_pos, pp)
			if d < best_dist:
				best_dist = d
				best_id = pid
	return best_id


func _grid_distance(a: ComPosition, b: ComPosition) -> float:
	if grid == null:
		return 9999.0
	var dx := absi(a.grid_x - b.grid_x)
	var dy := absi(a.grid_y - b.grid_y)
	dx = mini(dx, grid.width - dx)
	dy = mini(dy, grid.height - dy)
	return sqrt(float(dx * dx + dy * dy))


func _move_toward(mover: ComPosition, target: ComPosition) -> void:
	if grid == null or projector == null:
		return
	var dx := target.grid_x - mover.grid_x
	var dy := target.grid_y - mover.grid_y
	if absi(dx) > grid.width / 2:
		dx = -sign(dx) * (grid.width - absi(dx))
	if absi(dy) > grid.height / 2:
		dy = -sign(dy) * (grid.height - absi(dy))
	var sx := signi(dx)
	var sy := signi(dy)
	mover.grid_x = grid.wrap_x(mover.grid_x + sx)
	mover.grid_y = grid.wrap_y(mover.grid_y + sy)
	var h := grid.get_height(mover.grid_x, mover.grid_y)
	var dir := projector.grid_to_sphere(float(mover.grid_x) + 0.5, float(mover.grid_y) + 0.5).normalized()
	mover.world_pos = dir * (projector.radius + h * projector.height_scale)


func _run_flee(ecs: EcsWorld, prey_entities: Array[int]) -> void:
	for pid in prey_entities:
		var prey: ComPrey = ecs.get_component(pid, "ComPrey") as ComPrey
		if prey == null or not prey.is_fleeing:
			continue
		var ai: ComAiState = ecs.get_component(pid, "ComAiState") as ComAiState
		if ai == null:
			continue
		ai.current_state = DefEnums.AIState.FLEEING
		ai.state_timer = 0.0

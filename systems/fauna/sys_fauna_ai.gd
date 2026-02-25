extends System
class_name SysFaunaAi

var grid: TorusGrid = null
var projector: PlanetProjector = null
var time_system: SysTime = null

const TICK_INTERVAL := 1.0
var _timer := 0.0

const WANDER_DURATION := 5.0
const FORAGE_DURATION := 8.0
const SLEEP_DURATION := 10.0


func setup(g: TorusGrid, proj: PlanetProjector, ts: SysTime) -> void:
	grid = g
	projector = proj
	time_system = ts


func update(world: Node, delta: float) -> void:
	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer -= TICK_INTERVAL

	var ecs := world as EcsWorld
	var entities := ecs.query(["ComFaunaSpecies", "ComAiState", "ComPosition", "ComHunger", "ComHealth"])

	var secs_per_year := float(GameConfig.HOURS_PER_DAY * GameConfig.DAYS_PER_SEASON * GameConfig.SEASONS_PER_YEAR) * 60.0
	var years_per_tick := (TICK_INTERVAL * GameConfig.TIME_SCALE) / secs_per_year

	var dead_queue: Array[int] = []

	for eid in entities:
		var species: ComFaunaSpecies = ecs.get_component(eid, "ComFaunaSpecies") as ComFaunaSpecies
		var ai: ComAiState = ecs.get_component(eid, "ComAiState") as ComAiState
		var pos: ComPosition = ecs.get_component(eid, "ComPosition") as ComPosition
		var hunger: ComHunger = ecs.get_component(eid, "ComHunger") as ComHunger
		var health: ComHealth = ecs.get_component(eid, "ComHealth") as ComHealth

		species.age += years_per_tick

		if species.age >= species.max_age or health.current_hp <= 0.0:
			ai.current_state = DefEnums.AIState.DYING
			dead_queue.append(eid)
			continue

		ai.state_timer += TICK_INTERVAL

		_evaluate_state(ecs, eid, species, ai, pos, hunger, health)
		_execute_movement(ecs, eid, species, ai, pos)

	for eid in dead_queue:
		ecs.remove_entity(eid)


func _evaluate_state(ecs: EcsWorld, eid: int, species: ComFaunaSpecies, ai: ComAiState, pos: ComPosition, hunger: ComHunger, health: ComHealth) -> void:
	var prey_comp: ComPrey = ecs.get_component(eid, "ComPrey") as ComPrey
	if prey_comp != null and prey_comp.is_fleeing:
		ai.current_state = DefEnums.AIState.FLEEING
		return

	if hunger.current >= hunger.max_hunger * 0.7:
		if species.diet == DefEnums.DietType.CARNIVORE or species.diet == DefEnums.DietType.OMNIVORE:
			ai.current_state = DefEnums.AIState.HUNTING
			ai.state_timer = 0.0
			return
		else:
			ai.current_state = DefEnums.AIState.FORAGING
			ai.state_timer = 0.0
			return

	if _is_night() and ai.current_state != DefEnums.AIState.FLEEING:
		if ai.current_state != DefEnums.AIState.SLEEPING:
			ai.current_state = DefEnums.AIState.SLEEPING
			ai.state_timer = 0.0
		return

	match ai.current_state:
		DefEnums.AIState.IDLE:
			if ai.state_timer > 3.0:
				ai.current_state = DefEnums.AIState.WANDERING
				ai.state_timer = 0.0
		DefEnums.AIState.WANDERING:
			if ai.state_timer > WANDER_DURATION:
				ai.current_state = DefEnums.AIState.IDLE
				ai.state_timer = 0.0
		DefEnums.AIState.FORAGING:
			if ai.state_timer > FORAGE_DURATION:
				hunger.current = maxf(hunger.current - hunger.eat_rate, 0.0)
				ai.current_state = DefEnums.AIState.IDLE
				ai.state_timer = 0.0
		DefEnums.AIState.SLEEPING:
			if ai.state_timer > SLEEP_DURATION:
				ai.current_state = DefEnums.AIState.IDLE
				ai.state_timer = 0.0
		DefEnums.AIState.FLEEING:
			if ai.state_timer > 4.0:
				if prey_comp != null:
					prey_comp.is_fleeing = false
				ai.current_state = DefEnums.AIState.IDLE
				ai.state_timer = 0.0
		_:
			if ai.state_timer > 5.0:
				ai.current_state = DefEnums.AIState.IDLE
				ai.state_timer = 0.0


func _execute_movement(ecs: EcsWorld, eid: int, species: ComFaunaSpecies, ai: ComAiState, pos: ComPosition) -> void:
	if ai.current_state == DefEnums.AIState.SLEEPING or ai.current_state == DefEnums.AIState.IDLE:
		return
	if grid == null or projector == null:
		return

	var move_speed := species.speed
	if ai.current_state == DefEnums.AIState.FLEEING:
		var prey_comp: ComPrey = ecs.get_component(eid, "ComPrey") as ComPrey
		if prey_comp != null:
			move_speed += prey_comp.flee_speed_bonus

	var tiles_per_tick := move_speed * TICK_INTERVAL * 0.1
	var dx := randi_range(-1, 1)
	var dy := randi_range(-1, 1)
	if dx == 0 and dy == 0:
		dx = 1

	var steps := int(ceilf(tiles_per_tick))
	var nx := grid.wrap_x(pos.grid_x + dx * steps)
	var ny := grid.wrap_y(pos.grid_y + dy * steps)

	var target_h := grid.get_height(nx, ny)
	if not species.is_aquatic and target_h < GameConfig.SEA_LEVEL:
		return
	if species.is_aquatic and target_h >= GameConfig.SEA_LEVEL:
		return

	pos.grid_x = nx
	pos.grid_y = ny
	var dir := projector.grid_to_sphere(float(nx) + 0.5, float(ny) + 0.5).normalized()
	pos.world_pos = dir * (projector.radius + target_h * projector.height_scale)


func _is_night() -> bool:
	if time_system == null:
		return false
	var hour := fmod(time_system.game_time / 60.0, 24.0)
	return hour < 6.0 or hour > 20.0


func randi_range(min_val: int, max_val: int) -> int:
	return min_val + (randi() % (max_val - min_val + 1))

extends System
class_name SysFaunaAi

var grid: TorusGrid = null
var projector: PlanetProjector = null
var time_system: SysTime = null
var water_grid: WaterGrid = null

const TICK_INTERVAL := 1.0
const BATCH_SIZE := 40
const SPATIAL_CELL := 16
var _timer := 0.0
var _batch_offset := 0
var _is_night_cached := false
var _spatial_predators: Dictionary = {}


func setup(g: TorusGrid, proj: PlanetProjector, ts: SysTime, wg: WaterGrid = null) -> void:
	grid = g
	projector = proj
	time_system = ts
	water_grid = wg


func update(world: Node, delta: float) -> void:
	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer -= TICK_INTERVAL

	var ecs := world as EcsWorld
	var entities := ecs.query(["ComFaunaSpecies", "ComAiState", "ComPosition", "ComHunger", "ComHealth", "ComIntelligence"])
	var total := entities.size()
	if total == 0:
		return

	_is_night_cached = _is_night()
	_rebuild_spatial_predators(ecs)

	var secs_per_year := float(GameConfig.HOURS_PER_DAY * GameConfig.DAYS_PER_SEASON * GameConfig.SEASONS_PER_YEAR) * 60.0
	var years_per_tick := (TICK_INTERVAL * GameConfig.TIME_SCALE) / secs_per_year

	var dead_queue: Array[int] = []
	var start := _batch_offset
	var count := mini(BATCH_SIZE, total)

	for _i in range(count):
		var idx := (start + _i) % total
		var eid: int = entities[idx]
		var species: ComFaunaSpecies = ecs.get_component(eid, "ComFaunaSpecies") as ComFaunaSpecies
		var ai: ComAiState = ecs.get_component(eid, "ComAiState") as ComAiState
		var pos: ComPosition = ecs.get_component(eid, "ComPosition") as ComPosition
		var hunger: ComHunger = ecs.get_component(eid, "ComHunger") as ComHunger
		var health: ComHealth = ecs.get_component(eid, "ComHealth") as ComHealth
		var energy: ComEnergy = ecs.get_component(eid, "ComEnergy") as ComEnergy
		var iq: ComIntelligence = ecs.get_component(eid, "ComIntelligence") as ComIntelligence

		species.age += years_per_tick

		if species.age >= species.max_age or health.current_hp <= 0.0:
			ai.current_state = DefEnums.AIState.DYING
			dead_queue.append(eid)
			continue

		ai.state_timer += TICK_INTERVAL
		_update_needs(hunger, energy, TICK_INTERVAL)

		var new_state := _utility_select(ecs, eid, species, ai, pos, hunger, health, energy, iq)
		if new_state != ai.current_state:
			ai.previous_state = ai.current_state
			ai.current_state = new_state
			ai.state_timer = 0.0

		_execute_state(ecs, eid, species, ai, pos, hunger, energy)

	_batch_offset = (start + count) % maxi(total, 1)

	for eid in dead_queue:
		ecs.remove_entity(eid)


func _rebuild_spatial_predators(ecs: EcsWorld) -> void:
	_spatial_predators.clear()
	var predators := ecs.get_components("ComPredator")
	var positions := ecs.get_components("ComPosition")
	for pid in predators.keys():
		if not positions.has(pid):
			continue
		var p: ComPosition = positions[pid]
		var cx := int(floor(float(p.grid_x) / float(SPATIAL_CELL)))
		var cy := int(floor(float(p.grid_y) / float(SPATIAL_CELL)))
		var key = cy * 1000 + cx
		if not _spatial_predators.has(key):
			_spatial_predators[key] = []
		_spatial_predators[key].append(pid)


func _update_needs(hunger: ComHunger, energy: ComEnergy, dt: float) -> void:
	hunger.current = minf(hunger.current + hunger.hunger_rate * dt, hunger.max_hunger)
	if energy:
		energy.current = maxf(energy.current - energy.drain_rate * dt, 0.0)


func _utility_select(ecs: EcsWorld, eid: int, species: ComFaunaSpecies, ai: ComAiState, pos: ComPosition, hunger: ComHunger, health: ComHealth, energy: ComEnergy, iq: ComIntelligence) -> int:
	var prey_comp: ComPrey = ecs.get_component(eid, "ComPrey") as ComPrey
	if prey_comp != null and prey_comp.is_fleeing:
		return DefEnums.AIState.FLEEING

	var hunger_urgency := hunger.current / hunger.max_hunger
	var thirst_urgency := hunger.current_thirst / hunger.max_thirst
	var energy_urgency := 1.0 - (energy.current / energy.max_energy if energy else 0.5)
	var health_urgency := 1.0 - health.current_hp / health.max_hp
	var night_factor := 1.0 if _is_night() else 0.0

	var u_forage := 0.0
	var u_hunt := 0.0
	var u_drink := thirst_urgency * 2.0 # High priority if very thirsty
	var u_sleep := hunger_urgency * -0.3 + energy_urgency * 1.2 + night_factor * 0.8
	var u_wander := 0.3
	var u_flee := 0.0
	var u_mate := 0.0
	var u_social := 0.0

	if species.diet == DefEnums.DietType.HERBIVORE:
		u_forage = hunger_urgency * 1.5 + health_urgency * 0.3
	elif species.diet == DefEnums.DietType.CARNIVORE:
		u_hunt = hunger_urgency * 1.6
		u_forage = 0.0
	else:
		u_forage = hunger_urgency * 1.0
		u_hunt = hunger_urgency * 1.2

	if prey_comp != null:
		var threat := _sense_threat_spatial(ecs, eid, pos)
		u_flee = threat * 2.0

	var repro: ComReproduction = ecs.get_component(eid, "ComReproduction") as ComReproduction
	if repro and species.age >= repro.maturity_age and hunger_urgency < 0.4 and energy_urgency < 0.3 and thirst_urgency < 0.4:
		u_mate = 0.6

	if iq and iq.iq >= 0.7:
		if iq.is_leader and hunger_urgency < 0.4 and energy_urgency < 0.3 and thirst_urgency < 0.4:
			u_social = 0.25

	var best_u := u_wander
	var best_state := DefEnums.AIState.WANDERING

	if u_drink > best_u:
		best_u = u_drink
		# Reusing FORAGING state for drinking, but we will seek water
		best_state = DefEnums.AIState.FORAGING

	if u_forage > best_u:
		best_u = u_forage
		best_state = DefEnums.AIState.FORAGING
	if u_hunt > best_u:
		best_u = u_hunt
		best_state = DefEnums.AIState.HUNTING
	if u_sleep > best_u:
		best_u = u_sleep
		best_state = DefEnums.AIState.SLEEPING
	if u_flee > best_u:
		best_u = u_flee
		best_state = DefEnums.AIState.FLEEING
	if u_mate > best_u:
		best_u = u_mate
		best_state = DefEnums.AIState.MATING
	if u_social > best_u:
		best_u = u_social
		best_state = DefEnums.AIState.SOCIALIZING

	if ai.current_state == best_state and ai.state_timer < 1.0:
		return ai.current_state

	return best_state


func _sense_threat_spatial(ecs: EcsWorld, eid: int, pos: ComPosition) -> float:
	var positions := ecs.get_components("ComPosition")
	var threat := 0.0
	@warning_ignore("integer_division")
	var cx := int(pos.grid_x / SPATIAL_CELL)
	@warning_ignore("integer_division")
	var cy := int(pos.grid_y / SPATIAL_CELL)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var key := (cy + dy) * 1000 + (cx + dx)
			if not _spatial_predators.has(key):
				continue
			for pid in _spatial_predators[key]:
				if pid == eid or not positions.has(pid):
					continue
				var p_pos: ComPosition = positions[pid]
				var dist := _grid_distance(pos, p_pos)
				if dist < 12.0:
					threat = maxf(threat, 1.0 - (dist / 12.0))
	return threat


func _execute_state(ecs: EcsWorld, eid: int, species: ComFaunaSpecies, ai: ComAiState, pos: ComPosition, hunger: ComHunger, energy: ComEnergy) -> void:
	match ai.current_state:
		DefEnums.AIState.SLEEPING:
			if energy:
				energy.current = minf(energy.current + energy.rest_rate * TICK_INTERVAL, energy.max_energy)
			if energy and energy.current >= energy.max_energy * 0.9 and not _is_night():
				ai.current_state = DefEnums.AIState.WANDERING
				ai.state_timer = 0.0
		DefEnums.AIState.FORAGING:
			var h_urg := hunger.current / hunger.max_hunger
			var t_urg := hunger.current_thirst / hunger.max_thirst
			
			if ai.state_timer > 3.0:
				if t_urg > h_urg:
					hunger.current_thirst = maxf(hunger.current_thirst - hunger.drink_rate * 0.5, 0.0)
				else:
					hunger.current = maxf(hunger.current - hunger.eat_rate * 0.5, 0.0)
				ai.state_timer = 0.0
			
			_move_toward_food_or_water(pos, species, t_urg > h_urg)
		DefEnums.AIState.WANDERING:
			_move_random(pos, species)
		DefEnums.AIState.FLEEING:
			_move_away_from_threat(ecs, eid, pos, species)
			if ai.state_timer > 5.0:
				var prey_comp: ComPrey = ecs.get_component(eid, "ComPrey") as ComPrey
				if prey_comp:
					prey_comp.is_fleeing = false
				ai.current_state = DefEnums.AIState.WANDERING
				ai.state_timer = 0.0
		DefEnums.AIState.HUNTING:
			pass
		DefEnums.AIState.MATING:
			if ai.state_timer > 4.0:
				ai.current_state = DefEnums.AIState.WANDERING
				ai.state_timer = 0.0
		DefEnums.AIState.MIGRATING:
			# Handled in SysMigration
			pass
		DefEnums.AIState.SOCIALIZING:
			var dx := randi_range(-2, 2)
			var dy := randi_range(-2, 2)
			pos.grid_x = grid.wrap_x(pos.grid_x + dx)
			pos.grid_y = grid.wrap_y(pos.grid_y + dy)
		DefEnums.AIState.WANDERING, _:
			if ai.state_timer > 3.0:
				var dx := randi_range(-2, 2)
				var dy := randi_range(-2, 2)
				pos.grid_x = grid.wrap_x(pos.grid_x + dx)
				pos.grid_y = grid.wrap_y(pos.grid_y + dy)
				ai.state_timer = 0.0


func _move_random(pos: ComPosition, species: ComFaunaSpecies) -> void:
	if grid == null or projector == null:
		return
	var dx := _randi_range(-1, 1)
	var dy := _randi_range(-1, 1)
	if dx == 0 and dy == 0:
		dx = 1
	_try_move(pos, species, dx, dy)


func _move_toward_food_or_water(pos: ComPosition, species: ComFaunaSpecies, seek_water: bool) -> void:
	if grid == null:
		_move_random(pos, species)
		return
	var best_dir := Vector2i.ZERO
	var best_score := -999.0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := grid.wrap_x(pos.grid_x + dx)
			var ny := grid.wrap_y(pos.grid_y + dy)
			var nh := grid.get_height(nx, ny)
			
			var score := 0.0
			if seek_water:
				if water_grid:
					var w_idx := ny * water_grid.width + nx
					if water_grid.water_depth[w_idx] > 0.01:
						score = 10.0 # Reached water
					else:
						score = -nh # Move downhill to find water
				else:
					if nh < GameConfig.SEA_LEVEL:
						score = 10.0
					else:
						score = -nh
			else:
				if not species.is_aquatic and nh < GameConfig.SEA_LEVEL:
					continue
				var biome := grid.get_biome(nx, ny)
				var bdata: Dictionary = DefBiomes.BIOME_DATA.get(biome, {})
				score = bdata.get("fertility", 0.3)
				if species.diet == DefEnums.DietType.HERBIVORE:
					score += bdata.get("tree_density", 0.0) * 0.5
					
			if score > best_score:
				best_score = score
				best_dir = Vector2i(dx, dy)
	if best_dir != Vector2i.ZERO:
		_try_move(pos, species, best_dir.x, best_dir.y)
	else:
		_move_random(pos, species)


func _move_away_from_threat(ecs: EcsWorld, eid: int, pos: ComPosition, species: ComFaunaSpecies) -> void:
	var positions := ecs.get_components("ComPosition")
	var flee_dir := Vector2.ZERO
	@warning_ignore("integer_division")
	var cx := int(pos.grid_x / SPATIAL_CELL)
	@warning_ignore("integer_division")
	var cy := int(pos.grid_y / SPATIAL_CELL)
	for sdy in range(-1, 2):
		for sdx in range(-1, 2):
			var key := (cy + sdy) * 1000 + (cx + sdx)
			if not _spatial_predators.has(key):
				continue
			for pid in _spatial_predators[key]:
				if pid == eid or not positions.has(pid):
					continue
				var p_pos: ComPosition = positions[pid]
				var dist := _grid_distance(pos, p_pos)
				if dist < 15.0 and dist > 0.01:
					var dx := float(pos.grid_x - p_pos.grid_x)
					var dy := float(pos.grid_y - p_pos.grid_y)
					if absf(dx) > grid.width * 0.5:
						dx -= signf(dx) * grid.width
					if absf(dy) > grid.height * 0.5:
						dy -= signf(dy) * grid.height
					flee_dir += Vector2(dx, dy).normalized() / maxf(dist, 1.0)

	if flee_dir.length() > 0.01:
		var fd := flee_dir.normalized()
		_try_move(pos, species, roundi(fd.x), roundi(fd.y))
	else:
		_move_random(pos, species)


func _try_move(pos: ComPosition, species: ComFaunaSpecies, dx: int, dy: int) -> void:
	if grid == null or projector == null:
		return
	var nx := grid.wrap_x(pos.grid_x + dx)
	var ny := grid.wrap_y(pos.grid_y + dy)
	var target_h := grid.get_height(nx, ny)
	if not species.is_aquatic and target_h < GameConfig.SEA_LEVEL:
		return
	if species.is_aquatic and target_h >= GameConfig.SEA_LEVEL:
		return
	pos.prev_world_pos = pos.world_pos
	pos.lerp_t = 0.0
	pos.grid_x = nx
	pos.grid_y = ny
	var dir := projector.grid_to_sphere(float(nx) + 0.5, float(ny) + 0.5).normalized()
	pos.world_pos = dir * (projector.radius + target_h * projector.height_scale)


func _grid_distance(a: ComPosition, b: ComPosition) -> float:
	if grid == null:
		return 9999.0
	var dx := absi(a.grid_x - b.grid_x)
	var dy := absi(a.grid_y - b.grid_y)
	dx = mini(dx, grid.width - dx)
	dy = mini(dy, grid.height - dy)
	return sqrt(float(dx * dx + dy * dy))


func _is_night() -> bool:
	if time_system == null:
		return false
	var hour := fmod(time_system.game_time / 60.0, 24.0)
	return hour < 6.0 or hour > 20.0


func _randi_range(min_val: int, max_val: int) -> int:
	return min_val + (randi() % (max_val - min_val + 1))

extends System
class_name SysFireSpread

var grid: TorusGrid = null
var weather_system: SysWeather = null
var wind_system: SysWind = null

var _accumulator: float = 0.0
const TICK_INTERVAL := 1.0
const BURN_DURATION := 30.0
const SPREAD_RANGE := 2
const RAIN_EXTINGUISH_RATE := 10.0
const LIGHTNING_IGNITE_CHANCE := 0.002


func setup(p_grid: TorusGrid, p_weather: SysWeather, p_wind: SysWind) -> void:
	grid = p_grid
	weather_system = p_weather
	wind_system = p_wind


func update(_world: Node, delta: float) -> void:
	_accumulator += delta
	if _accumulator < TICK_INTERVAL:
		return
	_accumulator = 0.0

	var ecs := _world as EcsWorld
	if ecs == null:
		return

	_try_lightning_ignition(ecs)
	_process_burning(ecs)
	_spread_fire(ecs)


func _try_lightning_ignition(ecs: EcsWorld) -> void:
	if weather_system == null:
		return
	if weather_system.current_state != DefEnums.WeatherState.STORM:
		return

	var flammables := ecs.get_components("ComFlammable")
	if flammables.is_empty():
		return

	for eid in flammables.keys():
		var f: ComFlammable = flammables[eid]
		if f.is_burning:
			continue
		if randf() < LIGHTNING_IGNITE_CHANCE * f.flammability:
			f.is_burning = true
			f.burn_timer = BURN_DURATION
			break


func _process_burning(ecs: EcsWorld) -> void:
	var is_raining := false
	if weather_system:
		is_raining = weather_system.current_state == DefEnums.WeatherState.RAIN or weather_system.current_state == DefEnums.WeatherState.STORM

	var dead_entities: Array[int] = []
	var flammables := ecs.get_components("ComFlammable")

	for eid in flammables.keys():
		var f: ComFlammable = flammables[eid]
		if not f.is_burning:
			continue

		if is_raining:
			f.burn_timer += RAIN_EXTINGUISH_RATE * TICK_INTERVAL
			if f.burn_timer > BURN_DURATION:
				f.is_burning = false
				f.burn_timer = 0.0
				continue

		f.burn_timer -= TICK_INTERVAL
		if f.burn_timer <= 0.0:
			dead_entities.append(eid)

	for eid in dead_entities:
		ecs.remove_entity(eid)


func _spread_fire(ecs: EcsWorld) -> void:
	if grid == null:
		return

	var burning_positions: Array[Vector2i] = []
	var flammables := ecs.get_components("ComFlammable")
	var positions := ecs.get_components("ComPosition")

	for eid in flammables.keys():
		var f: ComFlammable = flammables[eid]
		if f.is_burning and positions.has(eid):
			var p: ComPosition = positions[eid]
			burning_positions.append(Vector2i(p.grid_x, p.grid_y))

	if burning_positions.is_empty():
		return

	var wind_bias := Vector2i.ZERO
	if wind_system:
		wind_bias = Vector2i(int(wind_system.direction.x), int(wind_system.direction.y))

	for burn_pos in burning_positions:
		for eid in flammables.keys():
			var f: ComFlammable = flammables[eid]
			if f.is_burning:
				continue
			if not positions.has(eid):
				continue

			var p: ComPosition = positions[eid]
			var dx := absi(p.grid_x - burn_pos.x)
			var dy := absi(p.grid_y - burn_pos.y)
			if dx > SPREAD_RANGE or dy > SPREAD_RANGE:
				continue

			var wind_factor := 1.0
			var to_target := Vector2i(p.grid_x - burn_pos.x, p.grid_y - burn_pos.y)
			if wind_bias.x * to_target.x + wind_bias.y * to_target.y > 0:
				wind_factor = 1.5

			if randf() < f.flammability * 0.15 * wind_factor:
				f.is_burning = true
				f.burn_timer = BURN_DURATION


func ignite_at(ecs: EcsWorld, tile_x: int, tile_y: int) -> void:
	var flammables := ecs.get_components("ComFlammable")
	var positions := ecs.get_components("ComPosition")

	for eid in flammables.keys():
		if not positions.has(eid):
			continue
		var p: ComPosition = positions[eid]
		if p.grid_x == tile_x and p.grid_y == tile_y:
			var f: ComFlammable = flammables[eid]
			f.is_burning = true
			f.burn_timer = BURN_DURATION
			break

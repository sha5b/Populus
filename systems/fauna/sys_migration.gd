extends System
class_name SysMigration

var grid: TorusGrid = null
var projector: PlanetProjector = null
var time_system: SysTime = null

const TICK_INTERVAL := 5.0
var _timer := 0.0
var _last_season := -1


func setup(g: TorusGrid, proj: PlanetProjector, ts: SysTime) -> void:
	grid = g
	projector = proj
	time_system = ts


func update(world: Node, delta: float) -> void:
	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer -= TICK_INTERVAL

	if time_system == null:
		return

	var current_season: int = time_system.season
	if current_season == _last_season:
		return
	_last_season = current_season

	if current_season != DefEnums.Season.AUTUMN:
		return

	var ecs := world as EcsWorld
	var entities := ecs.query(["ComMigration", "ComFaunaSpecies", "ComPosition", "ComAiState"])

	for eid in entities:
		var mig: ComMigration = ecs.get_component(eid, "ComMigration") as ComMigration
		var species: ComFaunaSpecies = ecs.get_component(eid, "ComFaunaSpecies") as ComFaunaSpecies
		var pos: ComPosition = ecs.get_component(eid, "ComPosition") as ComPosition
		var ai: ComAiState = ecs.get_component(eid, "ComAiState") as ComAiState

		if species.is_aquatic:
			continue

		var current_biome := grid.get_biome(pos.grid_x, pos.grid_y)
		if current_biome == mig.preferred_biome:
			continue

		var target := _find_preferred_tile(pos, mig.preferred_biome)
		if target.x < 0:
			continue

		mig.target = target
		ai.current_state = DefEnums.AIState.MIGRATING
		ai.state_timer = 0.0

		_step_toward(pos, target, species)


func _find_preferred_tile(pos: ComPosition, biome: int) -> Vector2i:
	if grid == null:
		return Vector2i(-1, -1)
	var search_radius := 30
	var best := Vector2i(-1, -1)
	var best_dist := 99999.0
	for dy in range(-search_radius, search_radius + 1, 3):
		for dx in range(-search_radius, search_radius + 1, 3):
			var tx := grid.wrap_x(pos.grid_x + dx)
			var ty := grid.wrap_y(pos.grid_y + dy)
			if grid.get_biome(tx, ty) == biome and grid.get_height(tx, ty) >= GameConfig.SEA_LEVEL:
				var d := sqrt(float(dx * dx + dy * dy))
				if d < best_dist:
					best_dist = d
					best = Vector2i(tx, ty)
	return best


func _step_toward(pos: ComPosition, target: Vector2i, species: ComFaunaSpecies) -> void:
	if grid == null or projector == null:
		return
	var dx := target.x - pos.grid_x
	var dy := target.y - pos.grid_y
	if absi(dx) > grid.width / 2:
		dx = -signi(dx) * (grid.width - absi(dx))
	if absi(dy) > grid.height / 2:
		dy = -signi(dy) * (grid.height - absi(dy))
	var sx := clampi(dx, -2, 2)
	var sy := clampi(dy, -2, 2)
	var nx := grid.wrap_x(pos.grid_x + sx)
	var ny := grid.wrap_y(pos.grid_y + sy)

	var h := grid.get_height(nx, ny)
	if h < GameConfig.SEA_LEVEL:
		return

	pos.prev_world_pos = pos.world_pos
	pos.lerp_t = 0.0
	pos.grid_x = nx
	pos.grid_y = ny
	var dir := projector.grid_to_sphere(float(nx) + 0.5, float(ny) + 0.5).normalized()
	pos.world_pos = dir * (projector.radius + h * projector.height_scale)

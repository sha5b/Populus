extends System
class_name SysHunger

var grid: TorusGrid = null

const TICK_INTERVAL := 2.0
var _timer := 0.0


func setup(g: TorusGrid) -> void:
	grid = g


func update(world: Node, delta: float) -> void:
	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer -= TICK_INTERVAL

	var ecs := world as EcsWorld
	var entities := ecs.query(["ComFaunaSpecies", "ComHunger", "ComHealth"])

	var secs_per_year := float(GameConfig.HOURS_PER_DAY * GameConfig.DAYS_PER_SEASON * GameConfig.SEASONS_PER_YEAR) * 60.0
	var years_per_tick := (TICK_INTERVAL * GameConfig.TIME_SCALE) / secs_per_year

	for eid in entities:
		var species: ComFaunaSpecies = ecs.get_component(eid, "ComFaunaSpecies") as ComFaunaSpecies
		var hunger: ComHunger = ecs.get_component(eid, "ComHunger") as ComHunger
		var health: ComHealth = ecs.get_component(eid, "ComHealth") as ComHealth

		hunger.current += hunger.hunger_rate * years_per_tick * 50.0
		hunger.current = clampf(hunger.current, 0.0, hunger.max_hunger)

		if hunger.current >= hunger.max_hunger:
			health.current_hp -= hunger.starvation_rate * years_per_tick * 20.0
			health.current_hp = maxf(health.current_hp, 0.0)

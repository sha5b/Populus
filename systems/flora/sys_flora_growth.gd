extends System
class_name SysFloraGrowth

var grid: TorusGrid = null
var moisture_map: PackedFloat32Array
var temperature_map: PackedFloat32Array
var time_system: SysTime = null

var _accumulator: float = 0.0
const TICK_INTERVAL := 2.0
const STAGE_THRESHOLDS := {
	DefEnums.GrowthStage.SEED: 0.1,
	DefEnums.GrowthStage.SAPLING: 0.3,
	DefEnums.GrowthStage.YOUNG: 0.5,
	DefEnums.GrowthStage.MATURE: 0.8,
	DefEnums.GrowthStage.OLD: 1.0,
}

var _dead_queue: Array[int] = []


func setup(p_grid: TorusGrid, p_moisture: PackedFloat32Array, p_temp: PackedFloat32Array, p_time: SysTime) -> void:
	grid = p_grid
	moisture_map = p_moisture
	temperature_map = p_temp
	time_system = p_time


func update(_world: Node, delta: float) -> void:
	_accumulator += delta
	if _accumulator < TICK_INTERVAL:
		return
	_accumulator = 0.0

	var ecs := _world as EcsWorld
	if ecs == null:
		return

	var entities := ecs.query(["ComPlantSpecies", "ComGrowth", "ComPosition"])
	_dead_queue.clear()

	for eid in entities:
		var growth: ComGrowth = ecs.get_component(eid, "ComGrowth") as ComGrowth
		var plant: ComPlantSpecies = ecs.get_component(eid, "ComPlantSpecies") as ComPlantSpecies
		var pos: ComPosition = ecs.get_component(eid, "ComPosition") as ComPosition

		if growth.stage == DefEnums.GrowthStage.DEAD:
			_dead_queue.append(eid)
			continue

		var game_seconds_per_tick := TICK_INTERVAL * GameConfig.TIME_SCALE
		var seconds_per_year := float(GameConfig.HOURS_PER_DAY * GameConfig.DAYS_PER_SEASON * GameConfig.SEASONS_PER_YEAR) * 60.0
		var years_per_tick := game_seconds_per_tick / seconds_per_year
		growth.age += years_per_tick

		var fertility := _get_fertility(pos, plant)
		var age_frac := growth.age / growth.max_age if growth.max_age > 0.0 else 1.0
		growth.growth_progress = clampf(age_frac, 0.0, 0.99)

		_update_stage(growth)

		if growth.age >= growth.max_age:
			growth.stage = DefEnums.GrowthStage.DEAD

	for eid in _dead_queue:
		ecs.remove_entity(eid)


func _get_fertility(pos: ComPosition, plant: ComPlantSpecies) -> float:
	if grid == null:
		return 0.5

	var idx := pos.grid_y * grid.width + pos.grid_x
	if idx < 0 or idx >= moisture_map.size():
		return 0.5

	var tile_moisture := moisture_map[idx]
	var tile_temp := temperature_map[idx]

	var water_match := 1.0 - absf(tile_moisture - plant.water_need) * 2.0
	water_match = clampf(water_match, 0.1, 1.0)

	var temp_factor := clampf(tile_temp, 0.1, 1.0)

	var biome := grid.get_biome(pos.grid_x, pos.grid_y)
	var biome_match := 1.0
	if biome >= 0 and not (biome in plant.preferred_biomes):
		biome_match = 0.2

	return water_match * temp_factor * biome_match


func _update_stage(growth: ComGrowth) -> void:
	var p := growth.growth_progress
	if p < STAGE_THRESHOLDS[DefEnums.GrowthStage.SEED]:
		growth.stage = DefEnums.GrowthStage.SEED
	elif p < STAGE_THRESHOLDS[DefEnums.GrowthStage.SAPLING]:
		growth.stage = DefEnums.GrowthStage.SAPLING
	elif p < STAGE_THRESHOLDS[DefEnums.GrowthStage.YOUNG]:
		growth.stage = DefEnums.GrowthStage.YOUNG
	elif p < STAGE_THRESHOLDS[DefEnums.GrowthStage.MATURE]:
		growth.stage = DefEnums.GrowthStage.MATURE
	else:
		growth.stage = DefEnums.GrowthStage.OLD

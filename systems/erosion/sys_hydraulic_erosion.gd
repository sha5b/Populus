extends System
class_name SysHydraulicErosion

var grid: TorusGrid = null
var time_system: SysTime = null
var weather_system: SysWeather = null

var base_erosion_rate: float = 0.3
var erosion_rate: float = 0.3
var deposition_rate: float = 0.3
var friction: float = 0.8
var speed_factor: float = 1.0
var max_iterations: int = 64
var base_particles: int = 200
var particles_per_batch: int = 200

var _game_hours_acc: float = 0.0
var _run_interval_hours: float = 1.0
var _total_particles: int = 0


func setup(g: TorusGrid, ts: SysTime, ws: SysWeather = null) -> void:
	grid = g
	time_system = ts
	weather_system = ws


const PARTICLES_PER_CHUNK := 10


func update(_world: Node, delta: float) -> void:
	if grid == null or time_system == null:
		return
	_game_hours_acc += delta * GameConfig.TIME_SCALE / 60.0
	if _game_hours_acc >= _run_interval_hours:
		_game_hours_acc -= _run_interval_hours
		_apply_weather_modifiers()


func process_chunk(px: int, py: int, size: int) -> void:
	if grid == null:
		return
	for _i in range(PARTICLES_PER_CHUNK):
		var sx := px + randi() % size
		var sy := py + randi() % size
		sx = grid.wrap_x(sx)
		sy = grid.wrap_y(sy)
		if grid.get_height(sx, sy) > GameConfig.SEA_LEVEL:
			_trace_particle(float(sx), float(sy))


func _trace_particle(x: float, y: float) -> float:
	var sediment := 0.0
	var vx := 0.0
	var vy := 0.0
	var total_moved := 0.0

	for i in range(max_iterations):
		var ix := int(x)
		var iy := int(y)

		var nx := _get_normal_x(ix, iy)
		var ny := _get_normal_y(ix, iy)
		var slope := sqrt(nx * nx + ny * ny)

		if slope < 0.001:
			_deposit_at(ix, iy, sediment * 0.5)
			total_moved += sediment * 0.5
			break

		var deposit := sediment * deposition_rate * (1.0 - slope)
		var erode := erosion_rate * slope * minf(1.0, float(i) * 0.1)

		deposit = maxf(deposit, 0.0)

		var height_here := grid.get_height(ix, iy)
		if height_here <= GameConfig.SEA_LEVEL:
			_deposit_at(ix, iy, sediment * 0.8)
			total_moved += sediment * 0.8
			break

		grid.set_height(ix, iy, height_here + deposit - erode)
		sediment += erode - deposit
		total_moved += absf(erode - deposit)

		vx = friction * vx + nx * speed_factor
		vy = friction * vy + ny * speed_factor

		x += vx
		y += vy

		x = fmod(fmod(x, float(grid.width)) + float(grid.width), float(grid.width))
		y = fmod(fmod(y, float(grid.height)) + float(grid.height), float(grid.height))

	return total_moved


func _get_normal_x(ix: int, iy: int) -> float:
	var left := grid.get_height(ix - 1, iy)
	var right := grid.get_height(ix + 1, iy)
	return left - right


func _get_normal_y(ix: int, iy: int) -> float:
	var up := grid.get_height(ix, iy - 1)
	var down := grid.get_height(ix, iy + 1)
	return up - down


func _deposit_at(ix: int, iy: int, amount: float) -> void:
	var wx := grid.wrap_x(ix)
	var wy := grid.wrap_y(iy)
	grid.set_height(wx, wy, grid.get_height(wx, wy) + amount)


func _apply_weather_modifiers() -> void:
	if weather_system == null:
		erosion_rate = base_erosion_rate
		particles_per_batch = base_particles
		return

	var state := weather_system.current_state
	match state:
		DefEnums.WeatherState.RAIN:
			erosion_rate = base_erosion_rate * 2.0
			particles_per_batch = int(base_particles * 1.5)
		DefEnums.WeatherState.STORM:
			erosion_rate = base_erosion_rate * 4.0
			particles_per_batch = base_particles * 3
		DefEnums.WeatherState.FOG:
			erosion_rate = base_erosion_rate * 0.5
			particles_per_batch = base_particles
		DefEnums.WeatherState.SNOW:
			erosion_rate = base_erosion_rate * 0.2
			particles_per_batch = int(base_particles * 0.5)
		_:
			erosion_rate = base_erosion_rate * 0.3
			particles_per_batch = int(base_particles * 0.5)

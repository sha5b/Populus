extends Node
class_name ChunkScheduler

const CHUNK_SIZE := 16
var _grid_w: int
var _grid_h: int
var _chunks_x: int
var _chunks_y: int
var _total_chunks: int

var _processors: Array[Callable] = []
var _tick_index: int = 0
var _priority_scores: PackedFloat32Array

var _camera_chunk: Vector2i = Vector2i(-1, -1)
var _chunks_per_frame: int = 4
var _accumulator: float = 0.0
var _tick_interval: float = 0.0

var grid: TorusGrid = null


func setup(g: TorusGrid, chunks_per_frame: int = 4, tick_interval: float = 0.0) -> void:
	grid = g
	_grid_w = g.width
	_grid_h = g.height
	@warning_ignore("integer_division")
	_chunks_x = _grid_w / CHUNK_SIZE
	@warning_ignore("integer_division")
	_chunks_y = _grid_h / CHUNK_SIZE
	_total_chunks = _chunks_x * _chunks_y
	_chunks_per_frame = chunks_per_frame
	_tick_interval = tick_interval
	_priority_scores = PackedFloat32Array()
	_priority_scores.resize(_total_chunks)
	_priority_scores.fill(0.0)


func register_processor(callable: Callable) -> void:
	_processors.append(callable)


func set_camera_grid_pos(gx: float, gy: float) -> void:
	_camera_chunk = Vector2i(
		clampi(int(floor(gx / float(CHUNK_SIZE))), 0, _chunks_x - 1),
		clampi(int(floor(gy / float(CHUNK_SIZE))), 0, _chunks_y - 1)
	)


func chunk_origin(chunk_idx: int) -> Vector2i:
	var cx := chunk_idx % _chunks_x
	@warning_ignore("integer_division")
	var cy := chunk_idx / _chunks_x
	return Vector2i(cx * CHUNK_SIZE, cy * CHUNK_SIZE)


func chunk_index(cx: int, cy: int) -> int:
	return cy * _chunks_x + cx


func _process(delta: float) -> void:
	if grid == null or _processors.is_empty():
		return

	if _tick_interval > 0.0:
		_accumulator += delta
		if _accumulator < _tick_interval:
			return
		_accumulator -= _tick_interval

	var to_tick := _select_chunks(_chunks_per_frame)
	for ci in to_tick:
		var origin := chunk_origin(ci)
		for processor in _processors:
			processor.call(origin.x, origin.y, CHUNK_SIZE)


func _update_priority_scores() -> void:
	for ci in range(_total_chunks):
		var cx := ci % _chunks_x
		@warning_ignore("integer_division")
		var cy := ci / _chunks_x

		var base_score := 1.0

		if _camera_chunk.x >= 0:
			var dx := absi(cx - _camera_chunk.x)
			var dy := absi(cy - _camera_chunk.y)
			@warning_ignore("integer_division")
			if dx > _chunks_x / 2:
				dx = _chunks_x - dx
			@warning_ignore("integer_division")
			if dy > _chunks_y / 2:
				dy = _chunks_y - dy
			var dist := dx + dy
			base_score += maxf(0.0, 5.0 - float(dist))

		_priority_scores[ci] = base_score


func _select_chunks(count: int) -> Array[int]:
	var selected: Array[int] = []

	var _rolling_start := _tick_index
	for _i in range(count):
		selected.append(_tick_index)
		_tick_index = (_tick_index + 1) % _total_chunks

	if _camera_chunk.x >= 0:
		var cam_ci := chunk_index(_camera_chunk.x, _camera_chunk.y)
		if cam_ci not in selected:
			selected[0] = cam_ci

	return selected

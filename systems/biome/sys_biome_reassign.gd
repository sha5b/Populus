extends System
class_name SysBiomeReassign

var grid: TorusGrid
var temperature_map: PackedFloat32Array
var moisture_map: PackedFloat32Array
var biome_map: PackedInt32Array
var continentalness_map: PackedFloat32Array
var erosion_map: PackedFloat32Array
var weirdness_map: PackedFloat32Array

var _last_heights: PackedFloat32Array
var _timer: float = 0.0
var _chunk_offset: int = 0
var _changed_count: int = 0

const TICK_INTERVAL := 2.0
const CHUNK_SIZE := 1024
const HEIGHT_DELTA_THRESHOLD := 0.008


func setup(
	g: TorusGrid,
	temp: PackedFloat32Array,
	moist: PackedFloat32Array,
	bmap: PackedInt32Array,
	cont: PackedFloat32Array,
	ero: PackedFloat32Array,
	weird: PackedFloat32Array
) -> void:
	grid = g
	temperature_map = temp
	moisture_map = moist
	biome_map = bmap
	continentalness_map = cont
	erosion_map = ero
	weirdness_map = weird
	_snapshot_heights()


func _snapshot_heights() -> void:
	var total := grid.width * grid.height
	_last_heights = PackedFloat32Array()
	_last_heights.resize(total)
	var w := grid.width
	for i in range(total):
		_last_heights[i] = grid.get_height(i % w, i / w)


func update(_world: Node, delta: float) -> void:
	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer -= TICK_INTERVAL
	_reassign_chunk()


func _reassign_chunk() -> void:
	var w := grid.width
	var total := w * grid.height
	var has_noise := continentalness_map.size() == total
	var start := _chunk_offset
	var end_idx := mini(start + CHUNK_SIZE, total)
	var changed := 0

	for i in range(start, end_idx):
		var x := i % w
		var y := i / w
		var current_h := grid.get_height(x, y)
		var delta_h := absf(current_h - _last_heights[i])

		if delta_h < HEIGHT_DELTA_THRESHOLD:
			continue

		_last_heights[i] = current_h
		var temp := temperature_map[i] if i < temperature_map.size() else 0.5
		var moist := moisture_map[i] if i < moisture_map.size() else 0.5
		var cont := continentalness_map[i] if has_noise else 0.5
		var ero := erosion_map[i] if has_noise else 0.5
		var weird := weirdness_map[i] if has_noise else 0.0

		var new_biome := GenBiomeAssignment._classify_multinoise(current_h, temp, moist, cont, ero, weird)
		if new_biome != biome_map[i]:
			biome_map[i] = new_biome
			grid.set_biome(x, y, new_biome)
			changed += 1

	_chunk_offset = end_idx if end_idx < total else 0

	if changed > 0:
		print("Biome reassignment chunk: %d tiles changed" % changed)

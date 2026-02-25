class_name AtmosphereGrid

const NUM_FACES := 6
const FACE_RES := 16
const ALT_RES := 8
const CELLS_PER_FACE := FACE_RES * FACE_RES * ALT_RES
const TOTAL_CELLS := NUM_FACES * CELLS_PER_FACE

const CHUNKS_PER_FACE := 4
const CHUNK_SIZE: int = FACE_RES / CHUNKS_PER_FACE
const TOTAL_CHUNKS := NUM_FACES * CHUNKS_PER_FACE * CHUNKS_PER_FACE

const LAPSE_RATE := 6.5
const FREEZING_TEMP := 0.0
const BASE_PRESSURE := 1013.0

var moisture: PackedFloat32Array
var temperature: PackedFloat32Array
var pressure: PackedFloat32Array
var cloud_density: PackedFloat32Array
var wind_u: PackedFloat32Array
var wind_v: PackedFloat32Array
var wind_w: PackedFloat32Array

var _dirty_chunks: PackedByteArray
var _projector: PlanetProjector


func _init() -> void:
	moisture = PackedFloat32Array()
	moisture.resize(TOTAL_CELLS)
	temperature = PackedFloat32Array()
	temperature.resize(TOTAL_CELLS)
	pressure = PackedFloat32Array()
	pressure.resize(TOTAL_CELLS)
	cloud_density = PackedFloat32Array()
	cloud_density.resize(TOTAL_CELLS)
	wind_u = PackedFloat32Array()
	wind_u.resize(TOTAL_CELLS)
	wind_v = PackedFloat32Array()
	wind_v.resize(TOTAL_CELLS)
	wind_w = PackedFloat32Array()
	wind_w.resize(TOTAL_CELLS)

	_dirty_chunks = PackedByteArray()
	_dirty_chunks.resize(TOTAL_CHUNKS)
	_dirty_chunks.fill(1)


func idx(face: int, fu: int, fv: int, alt: int) -> int:
	var ca := clampi(alt, 0, ALT_RES - 1)
	if fu >= 0 and fu < FACE_RES and fv >= 0 and fv < FACE_RES:
		return face * CELLS_PER_FACE + (ca * FACE_RES + fv) * FACE_RES + fu
	var mapped := _map_edge_cell(face, fu, fv)
	return mapped[0] * CELLS_PER_FACE + (ca * FACE_RES + mapped[2]) * FACE_RES + mapped[1]


func _map_edge_cell(face: int, fu: int, fv: int) -> Array:
	var last := FACE_RES - 1
	var cu := clampi(fu, 0, last)
	var cv := clampi(fv, 0, last)

	if fu < 0:
		match face:
			0: return [4, last, cv]
			1: return [5, last, cv]
			2: return [1, cv, last]
			3: return [1, last - cv, 0]
			4: return [1, last, cv]
			_: return [0, last, cv]
	elif fu >= FACE_RES:
		match face:
			0: return [5, 0, cv]
			1: return [4, 0, cv]
			2: return [0, cv, last]
			3: return [0, last - cv, 0]
			4: return [0, 0, cv]
			_: return [1, 0, cv]
	elif fv < 0:
		match face:
			0: return [2, last, cu]
			1: return [2, 0, last - cu]
			2: return [5, cu, last]
			3: return [4, last - cu, 0]
			4: return [2, cu, 0]
			_: return [2, last - cu, last]
	else:
		match face:
			0: return [3, last, last - cu]
			1: return [3, 0, cu]
			2: return [4, cu, last]
			3: return [5, last - cu, 0]
			4: return [3, cu, 0]
			_: return [3, last - cu, last]
	return [clampi(face, 0, NUM_FACES - 1), clampi(fu, 0, last), clampi(fv, 0, last)]


func initialize_from_biome(base_temp_map: PackedFloat32Array, base_moisture_map: PackedFloat32Array, grid_w: int, grid_h: int, proj: PlanetProjector) -> void:
	_projector = proj

	for face in range(NUM_FACES):
		for fv in range(FACE_RES):
			for fu in range(FACE_RES):
				var u_norm := (float(fu) + 0.5) / float(FACE_RES)
				var v_norm := (float(fv) + 0.5) / float(FACE_RES)
				var world_pos := proj.cube_sphere_point(face, u_norm, v_norm)
				var grid_pos := proj.sphere_to_grid(world_pos)
				var gx := clampi(grid_pos.x, 0, grid_w - 1)
				var gy := clampi(grid_pos.y, 0, grid_h - 1)
				var grid_idx := gy * grid_w + gx

				var base_t := base_temp_map[grid_idx] * 40.0 - 10.0
				var base_m := base_moisture_map[grid_idx]

				for alt in range(ALT_RES):
					var i := idx(face, fu, fv, alt)
					var alt_fraction := float(alt) / float(ALT_RES)

					temperature[i] = base_t - LAPSE_RATE * alt_fraction * 6.0
					moisture[i] = base_m * (1.0 - alt_fraction * 0.7)
					pressure[i] = BASE_PRESSURE * (1.0 - alt_fraction * 0.12)
					cloud_density[i] = 0.0
					wind_u[i] = 0.0
					wind_v[i] = 0.0
					wind_w[i] = 0.0

	mark_all_dirty()


func saturation_humidity(temp: float) -> float:
	return 0.1 + 0.9 * clampf((temp - FREEZING_TEMP) / 30.0, 0.0, 1.0)


func chunk_idx(face: int, cu: int, cv: int) -> int:
	return face * CHUNKS_PER_FACE * CHUNKS_PER_FACE + cv * CHUNKS_PER_FACE + cu


func mark_chunk_dirty_by_idx(ci: int) -> void:
	if ci >= 0 and ci < _dirty_chunks.size():
		_dirty_chunks[ci] = 1


func mark_all_dirty() -> void:
	_dirty_chunks.fill(1)


func is_chunk_dirty_by_idx(ci: int) -> bool:
	if ci >= 0 and ci < _dirty_chunks.size():
		return _dirty_chunks[ci] != 0
	return false


func clear_chunk_dirty_by_idx(ci: int) -> void:
	if ci >= 0 and ci < _dirty_chunks.size():
		_dirty_chunks[ci] = 0


func get_cloud_density_at(face: int, fu: int, fv: int, alt: int) -> float:
	return cloud_density[idx(face, fu, fv, alt)]


func get_cell_world_pos(face: int, fu: int, fv: int, alt: int, cloud_altitude: float) -> Vector3:
	if _projector == null:
		return Vector3.ZERO
	var u_norm := (float(fu) + 0.5) / float(FACE_RES)
	var v_norm := (float(fv) + 0.5) / float(FACE_RES)
	var alt_offset := cloud_altitude + float(alt) * (cloud_altitude / float(ALT_RES))
	return _projector.cube_sphere_point(face, u_norm, v_norm, alt_offset)


func get_column_max_density(face: int, fu: int, fv: int) -> float:
	var max_d := 0.0
	for alt in range(ALT_RES):
		max_d = maxf(max_d, cloud_density[idx(face, fu, fv, alt)])
	return max_d


func get_column_precipitation(face: int, fu: int, fv: int) -> float:
	var precip := 0.0
	for alt in range(ALT_RES):
		var d := cloud_density[idx(face, fu, fv, alt)]
		if d > 0.6:
			precip += (d - 0.6) * 0.5
	return precip


func get_latitude_fraction(face: int, _fu: int, fv: int) -> float:
	if _projector == null:
		return 0.5
	var u_norm := 0.5
	var v_norm := (float(fv) + 0.5) / float(FACE_RES)
	var world_pos := _projector.cube_sphere_point(face, u_norm, v_norm)
	var dir := world_pos.normalized()
	return (asin(clampf(dir.y, -1.0, 1.0)) / PI) + 0.5

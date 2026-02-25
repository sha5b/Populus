class_name AtmosphereGrid

const NUM_FACES := 6
const FACE_RES := 32
const ALT_RES := 4
const CELLS_PER_FACE := FACE_RES * FACE_RES * ALT_RES
const TOTAL_CELLS := NUM_FACES * CELLS_PER_FACE

const CHUNKS_PER_FACE := 8
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

var _cloud_noise_lo: FastNoiseLite
var _cloud_noise_hi: FastNoiseLite
var _coverage_noise: FastNoiseLite
var wind_offset: Vector3 = Vector3.ZERO
var _cloud_time: float = 0.0
var global_coverage_boost: float = 0.0
var weather_darkness: float = 0.0

const CLOUD_NOISE_SCALE := 1.2
const CLOUD_DETAIL_SCALE := 3.0
const CLOUD_COVERAGE_SCALE := 0.5
static var CLOUD_BASE_ALT: float = GameConfig.PLANET_RADIUS * 0.06
static var CLOUD_TOP_ALT: float = GameConfig.PLANET_RADIUS * 0.12
const CLOUD_DENSITY_CAP := 1.0


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

	_cloud_noise_lo = FastNoiseLite.new()
	_cloud_noise_lo.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cloud_noise_lo.fractal_type = FastNoiseLite.FRACTAL_FBM
	_cloud_noise_lo.fractal_octaves = 4
	_cloud_noise_lo.fractal_lacunarity = 2.0
	_cloud_noise_lo.fractal_gain = 0.5
	_cloud_noise_lo.frequency = 0.04
	_cloud_noise_lo.seed = 42

	_cloud_noise_hi = FastNoiseLite.new()
	_cloud_noise_hi.noise_type = FastNoiseLite.TYPE_CELLULAR
	_cloud_noise_hi.fractal_type = FastNoiseLite.FRACTAL_FBM
	_cloud_noise_hi.fractal_octaves = 3
	_cloud_noise_hi.fractal_lacunarity = 2.5
	_cloud_noise_hi.fractal_gain = 0.6
	_cloud_noise_hi.frequency = 0.12
	_cloud_noise_hi.seed = 137

	_coverage_noise = FastNoiseLite.new()
	_coverage_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_coverage_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_coverage_noise.fractal_octaves = 3
	_coverage_noise.frequency = 0.015
	_coverage_noise.seed = 999


func idx(face: int, fu: int, fv: int, alt: int) -> int:
	var cf := clampi(face, 0, NUM_FACES - 1)
	var cu := clampi(fu, 0, FACE_RES - 1)
	var cv := clampi(fv, 0, FACE_RES - 1)
	var ca := clampi(alt, 0, ALT_RES - 1)
	return cf * CELLS_PER_FACE + (ca * FACE_RES + cv) * FACE_RES + cu


func initialize_from_biome(_base_temp_map: PackedFloat32Array, base_moisture_map: PackedFloat32Array, grid_w: int, grid_h: int, proj: PlanetProjector) -> void:
	_projector = proj

	for face in range(NUM_FACES):
		for fv in range(FACE_RES):
			for fu in range(FACE_RES):
				var u_norm := (float(fu) + 0.5) / float(FACE_RES)
				var v_norm := (float(fv) + 0.5) / float(FACE_RES)
				var world_pos := proj.cube_sphere_point(face, u_norm, v_norm)
				var dir := world_pos.normalized()

				var abs_lat := asin(clampf(absf(dir.y), 0.0, 1.0)) / (PI * 0.5)
				var base_t := (1.0 - abs_lat) * 40.0 - 10.0

				var base_m := _sample_grid_bilinear(base_moisture_map, world_pos, proj, grid_w, grid_h)

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


func _sample_grid_bilinear(field: PackedFloat32Array, world_pos: Vector3, _proj: PlanetProjector, gw: int, gh: int) -> float:
	var r := world_pos.length()
	if r < 0.001:
		return 0.5
	var lat := asin(clampf(world_pos.y / r, -1.0, 1.0))
	var lon := atan2(world_pos.z, world_pos.x)
	if lon < 0.0:
		lon += TAU
	var gx := (lon / TAU) * float(gw)
	var gy := ((lat + PI * 0.5) / PI) * float(gh)

	var x0 := int(floor(gx)) % gw
	var y0 := clampi(int(floor(gy)), 0, gh - 1)
	var x1 := (x0 + 1) % gw
	var y1 := clampi(y0 + 1, 0, gh - 1)
	var fx: float = gx - float(floor(gx))
	var fy: float = gy - float(floor(gy))

	var v00 := field[y0 * gw + x0]
	var v10 := field[y0 * gw + x1]
	var v01 := field[y1 * gw + x0]
	var v11 := field[y1 * gw + x1]

	return lerpf(lerpf(v00, v10, fx), lerpf(v01, v11, fx), fy)


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
	var wp := get_cell_world_pos(face, fu, fv, alt, CLOUD_BASE_ALT)
	if wp.length_squared() < 0.01:
		return 0.0
	return sample_cloud_density_at_world(wp, face, fu, fv, alt)


func sample_cloud_density_at_world(wp: Vector3, face: int, fu: int, fv: int, alt: int) -> float:
	var dir := wp.normalized()
	var sp := dir * 50.0 + wind_offset

	var lo := (_cloud_noise_lo.get_noise_3d(sp.x * CLOUD_NOISE_SCALE, sp.y * CLOUD_NOISE_SCALE, sp.z * CLOUD_NOISE_SCALE) + 1.0) * 0.5

	var hi_sample := sp * CLOUD_DETAIL_SCALE
	var hi := (_cloud_noise_hi.get_noise_3d(hi_sample.x, hi_sample.y, hi_sample.z) + 1.0) * 0.5

	var base_shape := clampf(lo * 0.7 + hi * 0.3, 0.0, 1.0)

	var cov_sp := dir * 50.0 + wind_offset * 0.3
	var coverage := (_coverage_noise.get_noise_3d(cov_sp.x * CLOUD_COVERAGE_SCALE, cov_sp.y * CLOUD_COVERAGE_SCALE, cov_sp.z * CLOUD_COVERAGE_SCALE) + 1.0) * 0.5

	var cfu := clampi(fu, 0, FACE_RES - 1)
	var cfv := clampi(fv, 0, FACE_RES - 1)
	var surface_idx := idx(face, cfu, cfv, 0)
	var sim_moisture := moisture[surface_idx]
	var sim_temp := temperature[surface_idx]
	var temp_coverage := clampf((sim_temp + 10.0) / 40.0, 0.0, 1.0)
	var weather_coverage := clampf(sim_moisture * temp_coverage * 2.0, 0.0, 1.0)

	var total_coverage := clampf(coverage * 0.4 + weather_coverage * 0.6 + global_coverage_boost, 0.0, 1.0)

	var alt_frac := float(clampi(alt, 0, ALT_RES - 1)) / float(ALT_RES)
	var profile := _vertical_profile(alt_frac)

	var threshold := 0.65 - total_coverage * 0.45
	var density := clampf(base_shape - threshold, 0.0, CLOUD_DENSITY_CAP)
	density *= profile

	var abs_lat := absf(dir.y)
	if abs_lat > 0.85:
		density *= clampf((1.0 - abs_lat) / 0.15, 0.0, 1.0)

	return density


func _vertical_profile(alt_frac: float) -> float:
	if alt_frac < 0.15:
		return alt_frac / 0.15
	elif alt_frac < 0.5:
		return 1.0
	else:
		return clampf(1.0 - (alt_frac - 0.5) / 0.5, 0.0, 1.0)


func advance_wind(delta: float, wind_dir: Vector2, wind_speed: float) -> void:
	var speed := wind_speed * 0.3
	var planet_rotation := Vector3(0.0, 0.0, delta * 0.05)
	wind_offset += Vector3(wind_dir.x * speed * delta, 0.0, wind_dir.y * speed * delta) + planet_rotation
	_cloud_time += delta


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

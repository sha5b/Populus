extends Node3D
class_name PlanetWaterMesh

var grid: TorusGrid
var projector: PlanetProjector
var water: WaterGrid

const FACE_RES := 64
const NUM_FACES := 6
const CHUNKS_PER_FACE := 4
const CHUNK_SIZE := 16 # FACE_RES / CHUNKS_PER_FACE
const TOTAL_CHUNKS := NUM_FACES * CHUNKS_PER_FACE * CHUNKS_PER_FACE

var _chunk_meshes: Array[MeshInstance3D] = []
var _is_rebuilding_chunk: PackedByteArray
var _rebuild_index: int = 0
var _material: Material
var _rebuild_accumulator: float = 0.0
const REBUILDS_PER_SECOND: float = 24.0


func setup(g: TorusGrid, p: PlanetProjector, wg: WaterGrid) -> void:
	grid = g
	projector = p
	water = wg

	_chunk_meshes.resize(TOTAL_CHUNKS)
	_is_rebuilding_chunk = PackedByteArray()
	_is_rebuilding_chunk.resize(TOTAL_CHUNKS)
	_is_rebuilding_chunk.fill(0)

	for i in range(TOTAL_CHUNKS):
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_chunk_meshes[i] = mi


func set_material(mat: Material) -> void:
	_material = mat
	for mi in _chunk_meshes:
		if mi:
			mi.material_override = mat


func build_mesh() -> void:
	for ci in range(TOTAL_CHUNKS):
		if _is_rebuilding_chunk[ci] == 0:
			_is_rebuilding_chunk[ci] = 1
			WorkerThreadPool.add_task(_rebuild_chunk_thread.bind(ci), true, "WaterMeshChunk")


func _process(delta: float) -> void:
	if grid == null or projector == null or water == null:
		return

	_rebuild_accumulator += delta * REBUILDS_PER_SECOND
	var rebuilds_to_do := int(_rebuild_accumulator)
	
	if rebuilds_to_do > 0:
		_rebuild_accumulator -= float(rebuilds_to_do)
		rebuilds_to_do = mini(rebuilds_to_do, 4)

		for _i in range(rebuilds_to_do):
			var ci := _rebuild_index
			_rebuild_index = (_rebuild_index + 1) % TOTAL_CHUNKS
			if _is_rebuilding_chunk[ci] == 0:
				_is_rebuilding_chunk[ci] = 1
				WorkerThreadPool.add_task(_rebuild_chunk_thread.bind(ci), true, "WaterMeshChunk")


func _rebuild_chunk_thread(ci: int) -> void:
	@warning_ignore("integer_division")
	var face: int = ci / (CHUNKS_PER_FACE * CHUNKS_PER_FACE)
	var rem: int = ci % (CHUNKS_PER_FACE * CHUNKS_PER_FACE)
	@warning_ignore("integer_division")
	var cv: int = rem / CHUNKS_PER_FACE
	var cu: int = rem % CHUNKS_PER_FACE

	var res1 := CHUNK_SIZE + 1
	var vert_data: Array[Dictionary] = []
	vert_data.resize(res1 * res1)
	var depth_map := PackedFloat32Array()
	depth_map.resize(res1 * res1)

	var u_start := cu * CHUNK_SIZE
	var v_start := cv * CHUNK_SIZE

	var idx := 0
	for fv in range(res1):
		for fu in range(res1):
			var u := float(u_start + fu) / float(FACE_RES)
			var v := float(v_start + fv) / float(FACE_RES)

			var cube_wp := projector.cube_sphere_point(face, u, v)
			var gf := _world_to_grid_frac(cube_wp)
			var gx := int(floor(gf.x)) % grid.width
			var gy := clampi(int(floor(gf.y)), 0, grid.height - 1)

			var depth := water.get_depth(gx, gy)
			depth_map[idx] = depth

			var terrain_h := grid.get_height(gx, gy)
			var water_surface := GameConfig.SEA_LEVEL if depth < 0.001 else (terrain_h + depth)

			var equirect_dir := projector.grid_to_sphere(gf.x, gf.y).normalized()
			var wave := clampf(water.wave_height[water.get_index(gx, gy)], -0.5, 0.5)
			var r_scale := projector.radius / 100.0
			var water_offset := (0.0 if depth < 0.001 else (0.02 if depth < 0.05 else 0.005)) * r_scale
			var r := projector.radius + water_surface * projector.height_scale + wave * 0.3 * r_scale + water_offset

			vert_data[idx] = {
				"pos": equirect_dir * r,
				"nrm": equirect_dir,
				"col": _water_color(gx, gy, depth),
				"uv": Vector2(water.get_flow(gx, gy).x, water.get_flow(gx, gy).y),
			}
			idx += 1

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var vertex_remap := PackedInt32Array()
	vertex_remap.resize(res1 * res1)
	vertex_remap.fill(-1)

	var vi := 0
	for fv in range(CHUNK_SIZE):
		for fu in range(CHUNK_SIZE):
			var i00 := fv * res1 + fu
			var i10 := i00 + 1
			var i01 := i00 + res1
			var i11 := i01 + 1

			# Skip quad if ALL four corners are dry land
			var d00 := depth_map[i00]
			var d10 := depth_map[i10]
			var d01 := depth_map[i01]
			var d11 := depth_map[i11]
			if d00 < 0.001 and d10 < 0.001 and d01 < 0.001 and d11 < 0.001:
				continue

			# Ensure all 4 vertices are in the output
			for v_idx in [i00, i10, i01, i11]:
				if vertex_remap[v_idx] == -1:
					vertex_remap[v_idx] = vi
					var vd: Dictionary = vert_data[v_idx]
					verts.append(vd["pos"])
					normals.append(vd["nrm"])
					colors.append(vd["col"])
					uvs.append(vd["uv"])
					vi += 1

			indices.append(vertex_remap[i00])
			indices.append(vertex_remap[i01])
			indices.append(vertex_remap[i10])
			indices.append(vertex_remap[i10])
			indices.append(vertex_remap[i01])
			indices.append(vertex_remap[i11])

	var arrays := []
	if vi > 0:
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices

	_apply_chunk_mesh.call_deferred(ci, arrays)


func _apply_chunk_mesh(ci: int, arrays: Array) -> void:
	if ci < _chunk_meshes.size() and _chunk_meshes[ci] != null:
		if arrays.is_empty():
			_chunk_meshes[ci].mesh = null
		else:
			var arr_mesh := ArrayMesh.new()
			arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			_chunk_meshes[ci].mesh = arr_mesh
			
	if ci < _is_rebuilding_chunk.size():
		_is_rebuilding_chunk[ci] = 0


func _water_color(gx: int, gy: int, depth: float) -> Color:
	var temp := water.get_temperature(gx, gy)

	# Deep ocean: dark blue, moderate alpha. Shallow: lighter, very transparent
	var depth_t := clampf(depth / 0.5, 0.0, 1.0)
	var shallow := Color(0.12, 0.38, 0.52, lerpf(0.05, 0.55, depth_t))
	var deep := Color(0.02, 0.06, 0.30, 0.55)
	var base := shallow.lerp(deep, depth_t)

	# Temperature tint: warm=slightly green/turquoise, cold=dark blue
	var warm_tint := Color(0.05, 0.12, -0.05, 0.0)
	var cold_tint := Color(-0.03, -0.05, 0.08, 0.0)
	var temp_factor := clampf(temp, 0.0, 1.0)
	if temp_factor > 0.5:
		var t := (temp_factor - 0.5) * 2.0
		base.r += warm_tint.r * t
		base.g += warm_tint.g * t
		base.b += warm_tint.b * t
	else:
		var t := (0.5 - temp_factor) * 2.0
		base.r += cold_tint.r * t
		base.g += cold_tint.g * t
		base.b += cold_tint.b * t

	# No water = fully transparent
	if depth < 0.001:
		base.a = 0.0

	return base


func _world_to_grid_frac(world_pos: Vector3) -> Vector2:
	var r := world_pos.length()
	if r < 0.001:
		return Vector2.ZERO
	var lat := asin(clampf(world_pos.y / r, -1.0, 1.0))
	var lon := atan2(world_pos.z, world_pos.x)
	if lon < 0.0:
		lon += TAU
	var gx := (lon / TAU) * float(grid.width)
	var gy := ((lat + PI * 0.5) / PI) * float(grid.height)
	return Vector2(gx, gy)

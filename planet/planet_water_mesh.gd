extends MeshInstance3D
class_name PlanetWaterMesh

var grid: TorusGrid
var projector: PlanetProjector
var water: WaterGrid

var _rebuild_timer: float = 0.0
const REBUILD_INTERVAL := 4.0
const FACE_RES := 64
const NUM_FACES := 6


func setup(g: TorusGrid, p: PlanetProjector, wg: WaterGrid) -> void:
	grid = g
	projector = p
	water = wg


func _process(delta: float) -> void:
	_rebuild_timer += delta
	if _rebuild_timer < REBUILD_INTERVAL:
		return
	_rebuild_timer = 0.0
	build_mesh()


func build_mesh() -> void:
	if grid == null or projector == null or water == null:
		return

	var res1 := FACE_RES + 1

	# First pass: build vertex data and per-vertex depth for culling
	var vert_data: Array[Dictionary] = []
	vert_data.resize(NUM_FACES * res1 * res1)
	var depth_map := PackedFloat32Array()
	depth_map.resize(NUM_FACES * res1 * res1)

	var idx := 0
	for face in range(NUM_FACES):
		for fv in range(res1):
			for fu in range(res1):
				var u := float(fu) / float(FACE_RES)
				var v := float(fv) / float(FACE_RES)

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

	# Second pass: only emit quads where at least one corner has water
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var vertex_remap := PackedInt32Array()
	vertex_remap.resize(NUM_FACES * res1 * res1)
	vertex_remap.fill(-1)

	var vi := 0

	for face in range(NUM_FACES):
		var face_base := face * res1 * res1
		for fv in range(FACE_RES):
			for fu in range(FACE_RES):
				var i00 := face_base + fv * res1 + fu
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
				for ci in [i00, i10, i01, i11]:
					if vertex_remap[ci] == -1:
						vertex_remap[ci] = vi
						var vd: Dictionary = vert_data[ci]
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

	if vi == 0:
		mesh = null
		return

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = arr_mesh


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

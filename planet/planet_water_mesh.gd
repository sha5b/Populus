extends MeshInstance3D
class_name PlanetWaterMesh

var grid: TorusGrid
var projector: PlanetProjector
var water: WaterGrid

var _rebuild_timer: float = 0.0
const REBUILD_INTERVAL := 4.0
const FACE_RES := 32
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

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	var res1 := FACE_RES + 1
	var verts_per_face := res1 * res1
	var total_verts := NUM_FACES * verts_per_face
	var total_indices := NUM_FACES * FACE_RES * FACE_RES * 6

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.resize(total_verts)
	normals.resize(total_verts)
	colors.resize(total_verts)
	uvs.resize(total_verts)
	indices.resize(total_indices)

	var vi := 0
	var ii := 0
	var has_water := false

	for face in range(NUM_FACES):
		var face_base := vi
		for fv in range(res1):
			for fu in range(res1):
				var u := float(fu) / float(FACE_RES)
				var v := float(fv) / float(FACE_RES)

				var cube_wp := projector.cube_sphere_point(face, u, v)
				var gf := _world_to_grid_frac(cube_wp)
				var gx := int(floor(gf.x)) % grid.width
				var gy := clampi(int(floor(gf.y)), 0, grid.height - 1)

				var depth := water.get_depth(gx, gy)
				var terrain_h := grid.get_height(gx, gy)
				var water_surface := maxf(terrain_h + depth, GameConfig.SEA_LEVEL)

				if depth > 0.001:
					has_water = true

				var equirect_dir := projector.grid_to_sphere(gf.x, gf.y).normalized()
				var wave := water.wave_height[water.get_index(gx, gy)]
				var r := projector.radius + water_surface * projector.height_scale + wave * 0.3
				var pos := equirect_dir * r

				verts[vi] = pos
				normals[vi] = equirect_dir

				var col := _water_color(gx, gy, depth)
				colors[vi] = col

				var flow := water.get_flow(gx, gy)
				uvs[vi] = Vector2(flow.x, flow.y)

				vi += 1

		for fv in range(FACE_RES):
			for fu in range(FACE_RES):
				var i00 := face_base + fv * res1 + fu
				var i10 := i00 + 1
				var i01 := i00 + res1
				var i11 := i01 + 1
				indices[ii] = i00
				indices[ii + 1] = i01
				indices[ii + 2] = i10
				indices[ii + 3] = i10
				indices[ii + 4] = i01
				indices[ii + 5] = i11
				ii += 6

	if not has_water:
		mesh = null
		return

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

	# Deep ocean: dark blue. Shallow: lighter, greener
	var shallow := Color(0.15, 0.35, 0.55, 0.75)
	var deep := Color(0.02, 0.08, 0.35, 0.85)
	var depth_t := clampf(depth / 0.3, 0.0, 1.0)
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

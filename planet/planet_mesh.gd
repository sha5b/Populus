extends MeshInstance3D
class_name PlanetMesh

var grid: TorusGrid
var projector: PlanetProjector
var biome_map: PackedInt32Array
var river_map: PackedFloat32Array
var micro_biome_map: PackedInt32Array
var is_dirty: bool = false

const FACE_RES := 64
const NUM_FACES := 6


func setup(g: TorusGrid, p: PlanetProjector) -> void:
	grid = g
	projector = p
	biome_map = PackedInt32Array()


func set_biome_map(bm: PackedInt32Array) -> void:
	biome_map = bm


func set_river_map(rm: PackedFloat32Array) -> void:
	river_map = rm


func set_micro_biome_map(mbm: PackedInt32Array) -> void:
	micro_biome_map = mbm


func build_mesh() -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	var res1 := FACE_RES + 1
	var verts_per_face := res1 * res1
	var total_verts := NUM_FACES * verts_per_face
	var total_indices := NUM_FACES * FACE_RES * FACE_RES * 6

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(total_verts)
	normals.resize(total_verts)
	colors.resize(total_verts)
	indices.resize(total_indices)

	var vi := 0
	var ii := 0

	for face in range(NUM_FACES):
		var face_base := vi
		for fv in range(res1):
			for fu in range(res1):
				var u := float(fu) / float(FACE_RES)
				var v := float(fv) / float(FACE_RES)
				var pos := _vertex_at(face, u, v)
				verts[vi] = pos
				normals[vi] = pos.normalized()
				var gf := _world_to_grid_frac(projector.cube_sphere_point(face, u, v))
				colors[vi] = _sample_color_blended(gf)
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

	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = arr_mesh


func update_region(cx: int, cy: int, _radius_tiles: int) -> void:
	build_mesh()


func _sample_height_bilinear(fx: float, fy: float) -> float:
	var ix := int(floor(fx))
	var iy := int(floor(fy))
	var dx := fx - float(ix)
	var dy := fy - float(iy)
	var h00 := grid.get_height(ix, iy)
	var h10 := grid.get_height(ix + 1, iy)
	var h01 := grid.get_height(ix, iy + 1)
	var h11 := grid.get_height(ix + 1, iy + 1)
	return h00 * (1.0 - dx) * (1.0 - dy) + h10 * dx * (1.0 - dy) + h01 * (1.0 - dx) * dy + h11 * dx * dy


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


func _vertex_at(face: int, u: float, v: float) -> Vector3:
	var cube_wp := projector.cube_sphere_point(face, u, v)
	var gf := _world_to_grid_frac(cube_wp)
	var h := _sample_height_bilinear(gf.x, gf.y)
	var equirect_dir := projector.grid_to_sphere(gf.x, gf.y).normalized()
	return equirect_dir * (projector.radius + h * projector.height_scale)


func _sample_color_blended(gf: Vector2) -> Color:
	var fx: float = gf.x
	var fy: float = gf.y
	var ix := int(floor(fx))
	var iy := int(floor(fy))
	var dx: float = fx - floor(fx)
	var dy: float = fy - floor(fy)

	var c00 := _color_at_tile(ix, iy)
	var c10 := _color_at_tile(ix + 1, iy)
	var c01 := _color_at_tile(ix, iy + 1)
	var c11 := _color_at_tile(ix + 1, iy + 1)

	var top := c00.lerp(c10, dx)
	var bot := c01.lerp(c11, dx)
	return top.lerp(bot, dy)


func _color_at_tile(tx: int, ty: int) -> Color:
	var w := grid.width
	var gx := tx % w
	if gx < 0:
		gx += w
	var gy := clampi(ty, 0, grid.height - 1)
	var idx := gy * w + gx
	var height := grid.get_height(gx, gy)

	if river_map.size() > idx and idx >= 0:
		if river_map[idx] > 0.0:
			var river_strength := clampf(river_map[idx], 0.0, 1.0)
			var shallow := Color(0.2, 0.35, 0.55)
			var deep := Color(0.08, 0.15, 0.45)
			return shallow.lerp(deep, river_strength)

	if biome_map.size() > idx and idx >= 0:
		var biome: int = biome_map[idx]
		if DefBiomes.BIOME_DATA.has(biome):
			var base_color: Color = DefBiomes.BIOME_DATA[biome]["color"]
			var shade := clampf(0.8 + height * 0.5, 0.6, 1.2)
			var col := base_color * shade
			col = _apply_micro_tint(col, idx)
			return col

	return projector.height_color(height)


func _apply_micro_tint(base: Color, idx: int) -> Color:
	if micro_biome_map.size() <= idx or idx < 0:
		return base
	var mb: int = micro_biome_map[idx]
	if mb == DefMicroBiomes.MicroBiomeType.STANDARD:
		return base
	if not DefMicroBiomes.MICRO_DATA.has(mb):
		return base
	var tint: Color = DefMicroBiomes.MICRO_DATA[mb]["color_tint"]
	var blend := tint.a
	if blend <= 0.0:
		return base
	return base.lerp(Color(tint.r, tint.g, tint.b), blend)

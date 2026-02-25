extends MeshInstance3D
class_name PlanetMesh

var grid: TorusGrid
var projector: PlanetProjector
var biome_map: PackedInt32Array
var is_dirty: bool = false

const FACE_RES := 64
const NUM_FACES := 6


func setup(g: TorusGrid, p: PlanetProjector) -> void:
	grid = g
	projector = p
	biome_map = PackedInt32Array()


func set_biome_map(bm: PackedInt32Array) -> void:
	biome_map = bm


func build_mesh() -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	var total_quads := NUM_FACES * FACE_RES * FACE_RES
	verts.resize(total_quads * 4)
	normals.resize(total_quads * 4)
	colors.resize(total_quads * 4)
	indices.resize(total_quads * 6)

	var vi := 0
	var ii := 0

	for face in range(NUM_FACES):
		for fv in range(FACE_RES):
			for fu in range(FACE_RES):
				var u0 := float(fu) / float(FACE_RES)
				var u1 := float(fu + 1) / float(FACE_RES)
				var v0 := float(fv) / float(FACE_RES)
				var v1 := float(fv + 1) / float(FACE_RES)

				var p00 := _vertex_at(face, u0, v0)
				var p10 := _vertex_at(face, u1, v0)
				var p01 := _vertex_at(face, u0, v1)
				var p11 := _vertex_at(face, u1, v1)

				verts[vi] = p00
				verts[vi + 1] = p10
				verts[vi + 2] = p01
				verts[vi + 3] = p11

				normals[vi] = p00.normalized()
				normals[vi + 1] = p10.normalized()
				normals[vi + 2] = p01.normalized()
				normals[vi + 3] = p11.normalized()

				var gf00 := _world_to_grid_frac(projector.cube_sphere_point(face, u0, v0))
				var h00 := _sample_height_bilinear(gf00.x, gf00.y)
				var col := _sample_color_at_grid(gf00, h00)
				colors[vi] = col
				colors[vi + 1] = col
				colors[vi + 2] = col
				colors[vi + 3] = col

				indices[ii] = vi
				indices[ii + 1] = vi + 2
				indices[ii + 2] = vi + 1
				indices[ii + 3] = vi + 1
				indices[ii + 4] = vi + 2
				indices[ii + 5] = vi + 3

				vi += 4
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


func _sample_color_at_grid(gf: Vector2, height: float) -> Color:
	var gx := int(gf.x) % grid.width
	if gx < 0:
		gx += grid.width
	var gy := clampi(int(gf.y), 0, grid.height - 1)
	var w := grid.width
	var idx := gy * w + gx

	if biome_map.size() > idx and idx >= 0:
		var biome: int = biome_map[idx]
		if DefBiomes.BIOME_DATA.has(biome):
			var base_color: Color = DefBiomes.BIOME_DATA[biome]["color"]
			var shade := clampf(0.8 + height * 0.5, 0.6, 1.2)
			return base_color * shade

	return projector.height_color(height)

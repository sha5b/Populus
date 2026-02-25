extends MeshInstance3D
class_name PlanetMesh

var grid: TorusGrid
var projector: SphereProjector
var biome_map: PackedInt32Array


func setup(g: TorusGrid, p: SphereProjector) -> void:
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
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var w := grid.width
	var h := grid.height
	var total_quads := w * h

	verts.resize(total_quads * 4)
	normals.resize(total_quads * 4)
	colors.resize(total_quads * 4)
	uvs.resize(total_quads * 4)
	indices.resize(total_quads * 6)

	var vi := 0
	var ii := 0

	for ty in range(h):
		for tx in range(w):
			var h00 := grid.get_height(tx, ty)
			var h10 := grid.get_height(tx + 1, ty)
			var h01 := grid.get_height(tx, ty + 1)
			var h11 := grid.get_height(tx + 1, ty + 1)

			var gx0 := float(tx)
			var gx1 := float(tx + 1)
			var gy0 := float(ty)
			var gy1 := float(ty + 1)

			var p00 := projector.grid_to_sphere(gx0, gy0, h00)
			var p10 := projector.grid_to_sphere(gx1, gy0, h10)
			var p01 := projector.grid_to_sphere(gx0, gy1, h01)
			var p11 := projector.grid_to_sphere(gx1, gy1, h11)

			verts[vi] = p00
			verts[vi + 1] = p10
			verts[vi + 2] = p01
			verts[vi + 3] = p11

			var n00 := projector.get_sphere_normal(gx0, gy0)
			var n10 := projector.get_sphere_normal(gx1, gy0)
			var n01 := projector.get_sphere_normal(gx0, gy1)
			var n11 := projector.get_sphere_normal(gx1, gy1)
			normals[vi] = n00
			normals[vi + 1] = n10
			normals[vi + 2] = n01
			normals[vi + 3] = n11

			var tile_color := _get_tile_color(tx, ty, h00)
			colors[vi] = tile_color
			colors[vi + 1] = tile_color
			colors[vi + 2] = tile_color
			colors[vi + 3] = tile_color

			var u0 := float(tx) / float(w)
			var u1 := float(tx + 1) / float(w)
			var v0 := float(ty) / float(h)
			var v1 := float(ty + 1) / float(h)
			uvs[vi] = Vector2(u0, v0)
			uvs[vi + 1] = Vector2(u1, v0)
			uvs[vi + 2] = Vector2(u0, v1)
			uvs[vi + 3] = Vector2(u1, v1)

			indices[ii] = vi
			indices[ii + 1] = vi + 1
			indices[ii + 2] = vi + 2
			indices[ii + 3] = vi + 1
			indices[ii + 4] = vi + 3
			indices[ii + 5] = vi + 2

			vi += 4
			ii += 6

	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = arr_mesh


func update_region(cx: int, cy: int, radius_tiles: int) -> void:
	if mesh == null or not mesh is ArrayMesh:
		build_mesh()
		return

	var arr_mesh := mesh as ArrayMesh
	var arrays := arr_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var normals_arr: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

	var w := grid.width

	for dy in range(-radius_tiles, radius_tiles + 1):
		for dx in range(-radius_tiles, radius_tiles + 1):
			var tx := grid.wrap_x(cx + dx)
			var ty := grid.wrap_y(cy + dy)
			var quad_idx := ty * w + tx
			var vi := quad_idx * 4

			var h00 := grid.get_height(tx, ty)
			var h10 := grid.get_height(tx + 1, ty)
			var h01 := grid.get_height(tx, ty + 1)
			var h11 := grid.get_height(tx + 1, ty + 1)

			var gx0 := float(tx)
			var gx1 := float(tx + 1)
			var gy0 := float(ty)
			var gy1 := float(ty + 1)

			verts[vi] = projector.grid_to_sphere(gx0, gy0, h00)
			verts[vi + 1] = projector.grid_to_sphere(gx1, gy0, h10)
			verts[vi + 2] = projector.grid_to_sphere(gx0, gy1, h01)
			verts[vi + 3] = projector.grid_to_sphere(gx1, gy1, h11)

			normals_arr[vi] = projector.get_sphere_normal(gx0, gy0)
			normals_arr[vi + 1] = projector.get_sphere_normal(gx1, gy0)
			normals_arr[vi + 2] = projector.get_sphere_normal(gx0, gy1)
			normals_arr[vi + 3] = projector.get_sphere_normal(gx1, gy1)

			var tile_color := _get_tile_color(tx, ty, h00)
			colors[vi] = tile_color
			colors[vi + 1] = tile_color
			colors[vi + 2] = tile_color
			colors[vi + 3] = tile_color

	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals_arr
	arrays[Mesh.ARRAY_COLOR] = colors

	arr_mesh.clear_surfaces()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = arr_mesh


func _get_tile_color(tx: int, ty: int, height: float) -> Color:
	var w := grid.width
	var idx := grid.wrap_y(ty) * w + grid.wrap_x(tx)
	if biome_map.size() > idx:
		var biome: int = biome_map[idx]
		if DefBiomes.BIOME_DATA.has(biome):
			var base_color: Color = DefBiomes.BIOME_DATA[biome]["color"]
			var shade := clampf(0.8 + height * 0.5, 0.6, 1.2)
			return base_color * shade
	return projector.height_color(height)

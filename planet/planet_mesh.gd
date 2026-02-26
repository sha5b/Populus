extends MeshInstance3D
class_name PlanetMesh

var grid: TorusGrid
var projector: PlanetProjector
var biome_map: PackedInt32Array
var river_map: PackedFloat32Array
var micro_biome_map: PackedInt32Array
var is_dirty: bool = false
var _color_noise: FastNoiseLite
var _color_noise2: FastNoiseLite

const FACE_RES := 128
const NUM_FACES := 6


func setup(g: TorusGrid, p: PlanetProjector) -> void:
	grid = g
	projector = p
	biome_map = PackedInt32Array()
	# Scale noise frequency inversely with grid size for consistent feature scale
	var freq_scale := 128.0 / float(g.width)
	_color_noise = FastNoiseLite.new()
	_color_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_color_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_color_noise.fractal_octaves = 3
	_color_noise.frequency = 0.04 * freq_scale
	_color_noise.seed = 9999
	_color_noise2 = FastNoiseLite.new()
	_color_noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_color_noise2.fractal_type = FastNoiseLite.FRACTAL_FBM
	_color_noise2.fractal_octaves = 2
	_color_noise2.frequency = 0.1 * freq_scale
	_color_noise2.seed = 8888


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


func update_region(_cx: int, _cy: int, _radius_tiles: int) -> void:
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

	# Rivers: water color with depth
	if river_map.size() > idx and idx >= 0:
		if river_map[idx] > 0.0:
			var river_strength := clampf(river_map[idx], 0.0, 1.0)
			var shallow := Color(0.18, 0.32, 0.52)
			var deep := Color(0.06, 0.12, 0.40)
			return shallow.lerp(deep, river_strength)

	# Get biome color with noise-based dual-color variation
	var col := _get_biome_color_varied(gx, gy, idx, height)

	# Biome edge blending: smooth transitions at boundaries
	col = _blend_biome_edges(col, gx, gy, idx)

	# Shore gradient: tiles just above sea level get wet sand tint
	var sea := GameConfig.SEA_LEVEL
	if height > sea and height < sea + 0.06:
		var shore_t := clampf((height - sea) / 0.06, 0.0, 1.0)
		var wet_sand := Color(0.55, 0.50, 0.35)
		col = wet_sand.lerp(col, shore_t * shore_t)

	# River bank tint: tiles adjacent to rivers get darker/muddy
	if river_map.size() > idx and idx >= 0 and river_map[idx] <= 0.0:
		var river_proximity := _get_river_proximity(gx, gy)
		if river_proximity > 0.0:
			var bank_col := Color(0.25, 0.30, 0.20)
			col = col.lerp(bank_col, river_proximity * 0.35)

	# Apply height + slope gradient
	col = _apply_height_gradient(col, gx, gy, height)
	return col


func _get_biome_color_varied(gx: int, gy: int, idx: int, height: float) -> Color:
	if biome_map.size() <= idx or idx < 0:
		return projector.height_color(height)
	var biome: int = biome_map[idx]
	if not DefBiomes.BIOME_DATA.has(biome):
		return projector.height_color(height)

	# Ocean floor: height-based coloring to reveal underwater terrain
	if biome == DefEnums.BiomeType.OCEAN:
		return _get_ocean_floor_color(gx, gy, height)

	var data: Dictionary = DefBiomes.BIOME_DATA[biome]
	var col1: Color = data["color"]
	var col2: Color = data.get("color2", col1)
	var variation: float = data.get("color_variation", 0.2)

	# Low-freq noise for large patches of color variation within biome
	var n1 := (_color_noise.get_noise_2d(float(gx), float(gy)) + 1.0) * 0.5
	# High-freq noise for small-scale texture
	var n2 := (_color_noise2.get_noise_2d(float(gx), float(gy)) + 1.0) * 0.5

	# Blend between color1 and color2 using low-freq noise
	var base_col := col1.lerp(col2, n1)

	# Add small-scale jitter for organic feel
	var jitter := (n2 - 0.5) * variation * 0.3
	base_col.r = clampf(base_col.r + jitter, 0.0, 1.0)
	base_col.g = clampf(base_col.g + jitter * 0.8, 0.0, 1.0)
	base_col.b = clampf(base_col.b + jitter * 0.5, 0.0, 1.0)

	return base_col


func _get_ocean_floor_color(gx: int, gy: int, height: float) -> Color:
	var sea := GameConfig.SEA_LEVEL
	var depth := sea - height
	var depth_t := clampf(depth / 0.5, 0.0, 1.0)

	# Continental shelf (very shallow): sandy/tan
	var shelf := Color(0.35, 0.32, 0.22)
	# Mid-depth: blue-green sediment
	var mid := Color(0.12, 0.18, 0.28)
	# Abyssal plain: very dark
	var abyss := Color(0.04, 0.06, 0.14)

	var base_col: Color
	if depth_t < 0.15:
		base_col = shelf.lerp(mid, depth_t / 0.15)
	elif depth_t < 0.6:
		base_col = mid.lerp(abyss, (depth_t - 0.15) / 0.45)
	else:
		base_col = abyss

	# Slope-based ridge highlighting: steep underwater slopes = lighter (exposed rock)
	var slope := _get_slope(gx, gy)
	if slope > 0.02:
		var ridge_tint := Color(0.22, 0.20, 0.18)
		var ridge_t := clampf((slope - 0.02) / 0.08, 0.0, 0.6)
		base_col = base_col.lerp(ridge_tint, ridge_t)

	# Add noise variation for organic seafloor texture
	var n := (_color_noise2.get_noise_2d(float(gx), float(gy)) + 1.0) * 0.5
	var jitter := (n - 0.5) * 0.06
	base_col.r = clampf(base_col.r + jitter, 0.0, 1.0)
	base_col.g = clampf(base_col.g + jitter * 0.8, 0.0, 1.0)
	base_col.b = clampf(base_col.b + jitter * 0.5, 0.0, 1.0)

	return base_col


func _blend_biome_edges(center_col: Color, gx: int, gy: int, idx: int) -> Color:
	if biome_map.size() <= idx or idx < 0:
		return center_col
	var center_biome: int = biome_map[idx]
	var w := grid.width
	var diff_count := 0
	var diff_r := 0.0
	var diff_g := 0.0
	var diff_b := 0.0

	for n in grid.get_neighbors_4(gx, gy):
		var ni := n.y * w + n.x
		if ni < 0 or ni >= biome_map.size():
			continue
		if biome_map[ni] != center_biome:
			diff_count += 1
			var nh := grid.get_height(n.x, n.y)
			var ncol := _get_biome_color_varied(n.x, n.y, ni, nh)
			diff_r += ncol.r
			diff_g += ncol.g
			diff_b += ncol.b

	if diff_count == 0:
		return center_col

	# Subtle blend: only 20% influence from different neighbors
	var blend_t := float(diff_count) * 0.05
	var avg_r := diff_r / float(diff_count)
	var avg_g := diff_g / float(diff_count)
	var avg_b := diff_b / float(diff_count)
	return Color(
		lerpf(center_col.r, avg_r, blend_t),
		lerpf(center_col.g, avg_g, blend_t),
		lerpf(center_col.b, avg_b, blend_t),
		center_col.a
	)


func _get_river_proximity(gx: int, gy: int) -> float:
	if river_map.is_empty():
		return 0.0
	var w := grid.width
	var max_strength := 0.0
	for n in grid.get_neighbors_4(gx, gy):
		var ni := n.y * w + n.x
		if ni >= 0 and ni < river_map.size():
			max_strength = maxf(max_strength, river_map[ni])
	return clampf(max_strength, 0.0, 1.0)


func _apply_height_gradient(base_col: Color, gx: int, gy: int, height: float) -> Color:
	# Height-based brightness: valleys darker, peaks brighter
	var sea := GameConfig.SEA_LEVEL
	var h_norm := clampf((height - sea) / (1.0 - sea), 0.0, 1.0) if height > sea else 0.0
	var brightness := lerpf(0.75, 1.15, h_norm)

	# Slope darkening: steep areas get darker (cliffs/ravines)
	var slope := _get_slope(gx, gy)
	var slope_darken := clampf(1.0 - slope * 1.5, 0.6, 1.0)
	brightness *= slope_darken

	# Apply: darken RGB but keep hue by multiplying
	var result := Color(
		clampf(base_col.r * brightness, 0.0, 1.0),
		clampf(base_col.g * brightness, 0.0, 1.0),
		clampf(base_col.b * brightness, 0.0, 1.0),
		base_col.a
	)

	# High peaks: slight desaturation toward rocky grey
	if h_norm > 0.7:
		var grey := (result.r + result.g + result.b) / 3.0
		var desat := clampf((h_norm - 0.7) / 0.3, 0.0, 0.4)
		result.r = lerpf(result.r, grey, desat)
		result.g = lerpf(result.g, grey, desat)
		result.b = lerpf(result.b, grey, desat)

	return result


func _get_slope(gx: int, gy: int) -> float:
	var h_l := grid.get_height(grid.wrap_x(gx - 1), gy)
	var h_r := grid.get_height(grid.wrap_x(gx + 1), gy)
	var h_u := grid.get_height(gx, clampi(gy - 1, 0, grid.height - 1))
	var h_d := grid.get_height(gx, clampi(gy + 1, 0, grid.height - 1))
	var dx := absf(h_r - h_l) * 0.5
	var dy := absf(h_d - h_u) * 0.5
	return sqrt(dx * dx + dy * dy)

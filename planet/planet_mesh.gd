extends Node3D
class_name PlanetMesh

var grid: TorusGrid
var projector: PlanetProjector
var biome_map: PackedInt32Array
var river_map: PackedFloat32Array
var micro_biome_map: PackedInt32Array
var is_dirty: bool = false

var _color_noise: FastNoiseLite
var _color_noise2: FastNoiseLite
var _detail_noise: FastNoiseLite

const MAX_LOD_LEVEL := 5
const PATCH_RES := 16
const SPLIT_FACTOR := 2.2

enum NodeState { EMPTY, BUILDING, READY }

class QuadNode:
	var id: int
	var face: int
	var level: int
	var u_min: float
	var v_min: float
	var u_max: float
	var v_max: float
	var center: Vector3
	var radius: float
	
	var is_split: bool = false
	var children: Array[int] = []
	
	var mi: MeshInstance3D = null
	var state: int = 0 # NodeState.EMPTY
	var is_visible: bool = false

var _nodes: Dictionary = {}
var _next_node_id: int = 1
var _root_nodes: Array[int] = []

var _material: Material
var _camera_pos: Vector3 = Vector3.ZERO

var _rebuild_queue: Array[int] = []
var _pool: Array[MeshInstance3D] = []
var _active_count := 0
const MAX_CONCURRENT_BUILDS := 6

func setup(g: TorusGrid, p: PlanetProjector) -> void:
	grid = g
	projector = p
	biome_map = PackedInt32Array()
	
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
	
	_detail_noise = FastNoiseLite.new()
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_detail_noise.fractal_octaves = 4
	_detail_noise.seed = 7777

	_create_root_nodes()

func set_material(mat: Material) -> void:
	_material = mat
	for id in _nodes.keys():
		var n: QuadNode = _nodes[id]
		if n.mi:
			n.mi.material_override = mat

func set_biome_map(bm: PackedInt32Array) -> void:
	biome_map = bm

func set_river_map(rm: PackedFloat32Array) -> void:
	river_map = rm

func set_micro_biome_map(mbm: PackedInt32Array) -> void:
	micro_biome_map = mbm

func build_mesh() -> void:
	for id in _nodes.keys():
		var n: QuadNode = _nodes[id]
		if n.state == NodeState.READY:
			n.state = NodeState.EMPTY
	_rebuild_queue.clear()

# --- LOD LOGIC ---

func _create_root_nodes() -> void:
	for face in range(6):
		var id := _create_node(face, 0, 0.0, 0.0, 1.0, 1.0)
		_root_nodes.append(id)

func _create_node(face: int, level: int, u0: float, v0: float, u1: float, v1: float) -> int:
	var n := QuadNode.new()
	n.id = _next_node_id
	_next_node_id += 1
	n.face = face
	n.level = level
	n.u_min = u0
	n.v_min = v0
	n.u_max = u1
	n.v_max = v1
	
	var u_mid := (u0 + u1) * 0.5
	var v_mid := (v0 + v1) * 0.5
	n.center = _vertex_at_base(face, u_mid, v_mid)
	var corner := _vertex_at_base(face, u0, v0)
	n.radius = n.center.distance_to(corner) * 1.2
	
	_nodes[n.id] = n
	return n.id

func _process(_delta: float) -> void:
	if grid == null or projector == null:
		return
		
	var cam := get_viewport().get_camera_3d()
	if cam:
		_camera_pos = cam.global_position
		
	_update_lod_tree()
	_queue_rebuilds()
	_update_tree_visibility()

func _update_lod_tree() -> void:
	if _camera_pos == Vector3.ZERO:
		return
	for root_id in _root_nodes:
		_process_node(root_id)

func _process_node(id: int) -> void:
	var n: QuadNode = _nodes[id]
	var dist := n.center.distance_to(_camera_pos)
	
	var should_split := (dist < n.radius * SPLIT_FACTOR) and (n.level < MAX_LOD_LEVEL)
	if n.is_split and dist > n.radius * SPLIT_FACTOR * 1.1:
		should_split = false # Hysteresis
	
	if should_split:
		if not n.is_split:
			_split_node(n)
		for child_id in n.children:
			_process_node(child_id)
	else:
		if n.is_split:
			_merge_node(n)

func _split_node(n: QuadNode) -> void:
	var u_mid := (n.u_min + n.u_max) * 0.5
	var v_mid := (n.v_min + n.v_max) * 0.5
	
	n.children.append(_create_node(n.face, n.level + 1, n.u_min, n.v_min, u_mid, v_mid))
	n.children.append(_create_node(n.face, n.level + 1, u_mid, n.v_min, n.u_max, v_mid))
	n.children.append(_create_node(n.face, n.level + 1, n.u_min, v_mid, u_mid, n.v_max))
	n.children.append(_create_node(n.face, n.level + 1, u_mid, v_mid, n.u_max, n.v_max))
	n.is_split = true

func _merge_node(n: QuadNode) -> void:
	for child_id in n.children:
		_destroy_node_recursive(child_id)
	n.children.clear()
	n.is_split = false

func _destroy_node_recursive(id: int) -> void:
	var n: QuadNode = _nodes[id]
	if n.is_split:
		for child_id in n.children:
			_destroy_node_recursive(child_id)
	if n.mi:
		_pool_mesh_instance(n.mi)
		n.mi = null
	
	_rebuild_queue.erase(id)
	_nodes.erase(id)

func _queue_rebuilds() -> void:
	for id in _nodes.keys():
		var n: QuadNode = _nodes[id]
		if not n.is_split and n.state == NodeState.EMPTY:
			if not _rebuild_queue.has(id):
				_rebuild_queue.append(id)
	
	while _active_count < MAX_CONCURRENT_BUILDS and _rebuild_queue.size() > 0:
		var best_idx := -1
		var best_dist := 9999999.0
		for i in range(_rebuild_queue.size()):
			var nid := _rebuild_queue[i]
			if not _nodes.has(nid):
				continue
			var dist := _nodes[nid].center.distance_to(_camera_pos)
			if dist < best_dist:
				best_dist = dist
				best_idx = i
		
		if best_idx == -1:
			break
			
		var id := _rebuild_queue[best_idx]
		_rebuild_queue.remove_at(best_idx)
		
		if not _nodes.has(id):
			continue
			
		var n: QuadNode = _nodes[id]
		n.state = NodeState.BUILDING
		_active_count += 1
		
		var params = {
			"id": id,
			"face": n.face,
			"u_min": n.u_min,
			"v_min": n.v_min,
			"u_max": n.u_max,
			"v_max": n.v_max,
			"level": n.level
		}
		WorkerThreadPool.add_task(_rebuild_chunk_thread.bind(params), true, "PlanetQuadMesh")

func _update_tree_visibility() -> void:
	for root_id in _root_nodes:
		_update_node_visibility(_nodes[root_id])

func _update_node_visibility(n: QuadNode) -> bool:
	if not n.is_split:
		if n.state == NodeState.READY:
			if n.mi: n.mi.visible = true
			return true
		else:
			if n.mi: n.mi.visible = false
			return false
	else:
		var all_children_ready := true
		for child_id in n.children:
			if not _update_node_visibility(_nodes[child_id]):
				all_children_ready = false
		
		if all_children_ready:
			if n.mi: n.mi.visible = false
			return true
		else:
			if n.state == NodeState.READY:
				if n.mi: n.mi.visible = true
				for child_id in n.children:
					_hide_node_recursive(_nodes[child_id])
				return true
			else:
				if n.mi: n.mi.visible = false
				return false

func _hide_node_recursive(n: QuadNode) -> void:
	if n.mi: n.mi.visible = false
	for child_id in n.children:
		_hide_node_recursive(_nodes[child_id])

func _get_mesh_instance() -> MeshInstance3D:
	if _pool.size() > 0:
		var mi = _pool.pop_back()
		mi.visible = true
		return mi
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if _material:
		mi.material_override = _material
	add_child(mi)
	return mi

func _pool_mesh_instance(mi: MeshInstance3D) -> void:
	mi.visible = false
	mi.mesh = null
	_pool.append(mi)

# --- MESH GENERATION ---

func _vertex_at_base(face: int, u: float, v: float) -> Vector3:
	var cube_wp := projector.cube_sphere_point(face, u, v)
	var gf := _world_to_grid_frac(cube_wp)
	var h := _sample_height_bilinear(gf.x, gf.y)
	var equirect_dir := projector.grid_to_sphere(gf.x, gf.y).normalized()
	return equirect_dir * (projector.radius + h * projector.height_scale)

func _vertex_at(face: int, u: float, v: float, level: int) -> Vector3:
	var cube_wp := projector.cube_sphere_point(face, u, v)
	var gf := _world_to_grid_frac(cube_wp)
	var h := _sample_height_bilinear(gf.x, gf.y)
	
	if _detail_noise and level >= 3:
		var detail := _detail_noise.get_noise_3dv(cube_wp * 8.0) * 0.015
		var micro := _detail_noise.get_noise_3dv(cube_wp * 25.0) * 0.003
		h += detail + micro
		
	var equirect_dir := projector.grid_to_sphere(gf.x, gf.y).normalized()
	return equirect_dir * (projector.radius + h * projector.height_scale)

func _calc_normal(face: int, u: float, v: float, pos: Vector3, level: int) -> Vector3:
	var eps := 0.002
	var pos_u := _vertex_at(face, u + eps, v, level)
	var pos_v := _vertex_at(face, u, v + eps, level)
	
	var tangent := (pos_u - pos).normalized()
	var bitangent := (pos_v - pos).normalized()
	
	var n := bitangent.cross(tangent).normalized()
	if n.dot(pos.normalized()) < 0:
		n = -n
	return n

func _rebuild_chunk_thread(params: Dictionary) -> void:
	var id: int = params["id"]
	var face: int = params["face"]
	var u_min: float = params["u_min"]
	var v_min: float = params["v_min"]
	var u_max: float = params["u_max"]
	var v_max: float = params["v_max"]
	var level: int = params["level"]
	
	var res1 := PATCH_RES + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	var total_verts := res1 * res1
	var total_indices := PATCH_RES * PATCH_RES * 6
	verts.resize(total_verts)
	normals.resize(total_verts)
	colors.resize(total_verts)
	indices.resize(total_indices)

	var vi := 0
	var ii := 0

	for fv in range(res1):
		var v_t := float(fv) / float(PATCH_RES)
		var v := lerpf(v_min, v_max, v_t)
		for fu in range(res1):
			var u_t := float(fu) / float(PATCH_RES)
			var u := lerpf(u_min, u_max, u_t)
			
			var pos := _vertex_at(face, u, v, level)
			verts[vi] = pos
			normals[vi] = _calc_normal(face, u, v, pos, level)
			
			var cube_wp := projector.cube_sphere_point(face, u, v)
			var gf := _world_to_grid_frac(cube_wp)
			colors[vi] = _sample_color_blended(gf)
			vi += 1

	for fv in range(PATCH_RES):
		for fu in range(PATCH_RES):
			var i00 := fv * res1 + fu
			var i10 := i00 + 1
			var i01 := i00 + res1
			var i11 := i01 + 1
			
			# CCW Winding order to fix inside out mesh
			indices[ii] = i00
			indices[ii + 1] = i01
			indices[ii + 2] = i10
			indices[ii + 3] = i10
			indices[ii + 4] = i01
			indices[ii + 5] = i11
			ii += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	_apply_chunk_mesh.call_deferred(id, arrays)

func _apply_chunk_mesh(id: int, arrays: Array) -> void:
	_active_count -= 1
	if not _nodes.has(id):
		return
		
	var n: QuadNode = _nodes[id]
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	if n.mi == null:
		n.mi = _get_mesh_instance()
		
	n.mi.mesh = arr_mesh
	n.state = NodeState.READY


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
	var sediment_depth := grid.get_sediment(gx, gy)

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

	# Bedrock exposure tint
	if sediment_depth < 0.05 and height > GameConfig.SEA_LEVEL:
		var exposure := clampf(1.0 - (sediment_depth / 0.05), 0.0, 1.0)
		var bedrock_col := Color(0.35, 0.35, 0.38) # Grey rocky color
		col = col.lerp(bedrock_col, exposure * 0.7)

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

	for i in range(4):
		var n_x := grid.wrap_x(gx + TorusGrid.DIR_X[i])
		var n_y := grid.wrap_y(gy + TorusGrid.DIR_Y[i])
		var ni := n_y * w + n_x
		if ni < 0 or ni >= biome_map.size():
			continue
		if biome_map[ni] != center_biome:
			diff_count += 1
			var nh := grid.get_height(n_x, n_y)
			var ncol := _get_biome_color_varied(n_x, n_y, ni, nh)
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
	for i in range(4):
		var nx := grid.wrap_x(gx + TorusGrid.DIR_X[i])
		var ny := grid.wrap_y(gy + TorusGrid.DIR_Y[i])
		var ni := ny * w + nx
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

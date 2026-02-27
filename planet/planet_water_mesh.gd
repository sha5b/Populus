extends Node3D
class_name PlanetWaterMesh

var grid: TorusGrid
var projector: PlanetProjector
var water: WaterGrid

const MAX_LOD_LEVEL := 4
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

var _nodes: Dictionary = {}
var _next_node_id: int = 1
var _root_nodes: Array[int] = []

var _material: Material
var _camera_pos: Vector3 = Vector3.ZERO

var _rebuild_queue: Array[int] = []
var _pool: Array[MeshInstance3D] = []
var _active_count := 0
const MAX_CONCURRENT_BUILDS := 6

func setup(g: TorusGrid, p: PlanetProjector, wg: WaterGrid) -> void:
	grid = g
	projector = p
	water = wg
	_create_root_nodes()

func set_material(mat: Material) -> void:
	_material = mat
	for id in _nodes.keys():
		var n: QuadNode = _nodes[id]
		if n.mi:
			n.mi.material_override = mat

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
	if grid == null or projector == null or water == null:
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
		WorkerThreadPool.add_task(_rebuild_chunk_thread.bind(params), true, "WaterQuadMesh")

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
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	var gx := int(floor(gf.x)) % grid.width
	var gy := clampi(int(floor(gf.y)), 0, grid.height - 1)
	var depth := water.get_depth(gx, gy)
	var terrain_h := grid.get_height(gx, gy)
	var water_surface := GameConfig.SEA_LEVEL if depth < 0.001 else (terrain_h + depth)
	var equirect_dir := projector.grid_to_sphere(gf.x, gf.y).normalized()
	return equirect_dir * (projector.radius + water_surface * projector.height_scale)

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

func _rebuild_chunk_thread(params: Dictionary) -> void:
	var id: int = params["id"]
	var face: int = params["face"]
	var u_min: float = params["u_min"]
	var v_min: float = params["v_min"]
	var u_max: float = params["u_max"]
	var v_max: float = params["v_max"]
	var level: int = params["level"]
	
	var res1 := PATCH_RES + 1
	var vert_data: Array[Dictionary] = []
	vert_data.resize(res1 * res1)
	var depth_map := PackedFloat32Array()
	depth_map.resize(res1 * res1)

	var idx := 0
	for fv in range(res1):
		var v_t := float(fv) / float(PATCH_RES)
		var v := lerpf(v_min, v_max, v_t)
		for fu in range(res1):
			var u_t := float(fu) / float(PATCH_RES)
			var u := lerpf(u_min, u_max, u_t)
			
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
				"uv": Vector2(water.get_flow(gx, gy).x, water.get_flow(gx, gy).y)
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
	for fv in range(PATCH_RES):
		for fu in range(PATCH_RES):
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

			# CCW Winding order to fix inside out mesh
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

	_apply_chunk_mesh.call_deferred(id, arrays)

func _apply_chunk_mesh(id: int, arrays: Array) -> void:
	_active_count -= 1
	if not _nodes.has(id):
		return
		
	var n: QuadNode = _nodes[id]
	if arrays.is_empty():
		if n.mi:
			_pool_mesh_instance(n.mi)
			n.mi = null
	else:
		var arr_mesh := ArrayMesh.new()
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		
		if n.mi == null:
			n.mi = _get_mesh_instance()
			
		n.mi.mesh = arr_mesh
		
	n.state = NodeState.READY


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

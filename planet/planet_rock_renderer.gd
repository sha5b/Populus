extends Node3D
class_name PlanetRockRenderer

var _projector: PlanetProjector = null
var _grid: TorusGrid = null
var _ecs: EcsWorld = null

var _multimeshes: Dictionary = {}
var _mesh_cache: Dictionary = {}

var _rebuild_timer: float = 0.0
const REBUILD_INTERVAL := 5.0
const MAX_INSTANCES_PER_TYPE := 8192

const ComRockScript = preload("res://components/com_rock.gd")


func setup(proj: PlanetProjector, grid: TorusGrid, ecs: EcsWorld) -> void:
	_projector = proj
	_grid = grid
	_ecs = ecs


func _process(delta: float) -> void:
	_rebuild_timer += delta
	if _rebuild_timer < REBUILD_INTERVAL:
		return
	_rebuild_timer = 0.0
	_rebuild_all()


func _rebuild_all() -> void:
	if _ecs == null or _projector == null:
		return

	var by_type: Dictionary = {}

	var rocks := _ecs.get_components("ComRock")
	var positions := _ecs.get_components("ComPosition")

	for eid in rocks.keys():
		if not positions.has(eid):
			continue

		var rock = rocks[eid]
		var pos: ComPosition = positions[eid]

		var type_key := str(rock.rock_type)

		if not by_type.has(type_key):
			by_type[type_key] = []

		by_type[type_key].append({
			"pos": pos,
			"rock": rock
		})

	for type_key in by_type.keys():
		_update_multimesh(type_key, by_type[type_key])

	for type_key in _multimeshes.keys():
		if not by_type.has(type_key):
			var mmi: MultiMeshInstance3D = _multimeshes[type_key]
			mmi.multimesh.instance_count = 0


func _update_multimesh(type_key: String, instances: Array) -> void:
	if not _multimeshes.has(type_key):
		_create_multimesh_node(type_key)

	var mmi: MultiMeshInstance3D = _multimeshes[type_key]
	var mm: MultiMesh = mmi.multimesh
	var count := mini(instances.size(), MAX_INSTANCES_PER_TYPE)
	mm.instance_count = count

	for i in range(count):
		var data: Dictionary = instances[i]
		var pos: ComPosition = data["pos"]
		var rock = data["rock"]

		var wp: Vector3 = _get_surface_pos(pos)
		var up := wp.normalized()
		
		var t := Transform3D()
		var s: float = rock.scale * (GameConfig.PLANET_RADIUS / 100.0)
		t = t.scaled(Vector3(s, s, s))

		var fwd := up.cross(Vector3.RIGHT)
		if fwd.length_squared() < 0.001:
			fwd = up.cross(Vector3.FORWARD)
		fwd = fwd.normalized()
		var right := fwd.cross(up).normalized()
		
		# Rotate randomly based on position
		var hash_val := _jitter_hash(pos.grid_x, pos.grid_y, 2)
		var rot_angle := hash_val * TAU
		
		t.basis = Basis(right, up, fwd) * t.basis
		t.basis = t.basis.rotated(up, rot_angle)
		t.origin = wp
		
		# Slightly embed into the ground
		t.origin -= up * (s * 0.2)

		mm.set_instance_transform(i, t)
		
		var base_color := Color(0.4, 0.4, 0.42)
		var brightness := hash_val * 0.2 - 0.1
		base_color = base_color.lightened(brightness)
		mm.set_instance_color(i, base_color)


func _get_surface_pos(pos: ComPosition) -> Vector3:
	if _projector == null or _grid == null:
		return Vector3.ZERO
	var jx := _jitter_hash(pos.grid_x, pos.grid_y, 0) * 0.8
	var jy := _jitter_hash(pos.grid_x, pos.grid_y, 1) * 0.8
	var fx := float(pos.grid_x) + 0.1 + jx
	var fy := float(pos.grid_y) + 0.1 + jy
	var h := _sample_height_bilinear(fx, fy)
	var dir := _projector.grid_to_sphere(fx, fy).normalized()
	return dir * (_projector.radius + h * _projector.height_scale)


func _sample_height_bilinear(fx: float, fy: float) -> float:
	var ix := int(floor(fx))
	var iy := int(floor(fy))
	var dx := fx - float(ix)
	var dy := fy - float(iy)
	var h00 := _grid.get_height(ix, iy)
	var h10 := _grid.get_height(ix + 1, iy)
	var h01 := _grid.get_height(ix, iy + 1)
	var h11 := _grid.get_height(ix + 1, iy + 1)
	return h00 * (1.0 - dx) * (1.0 - dy) + h10 * dx * (1.0 - dy) + h01 * (1.0 - dx) * dy + h11 * dx * dy


func _jitter_hash(x: int, y: int, channel: int) -> float:
	var n := x * 374761393 + y * 668265263 + channel * 1274126177
	n = (n ^ (n >> 13)) * 1103515245
	return float(n & 0xFFFF) / 65535.0


func _create_multimesh_node(type_key: String) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = 0
	mm.mesh = _get_base_mesh(type_key)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Rocks_" + type_key
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.specular_amount = 0.1
	mmi.material_override = mat
	
	add_child(mmi)
	_multimeshes[type_key] = mmi


func _get_base_mesh(type_key: String) -> Mesh:
	if _mesh_cache.has(type_key):
		return _mesh_cache[type_key]

	var mesh: Mesh
	match type_key:
		"0": mesh = _make_voxel_rock_1()
		"1": mesh = _make_voxel_rock_2()
		_:   mesh = _make_voxel_rock_3()

	_mesh_cache[type_key] = mesh
	return mesh


func _add_box(st: SurfaceTool, pos: Vector3, size: Vector3, color: Color) -> void:
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	var hd := size.z * 0.5
	
	var p0 := pos + Vector3(-hw, -hh, -hd)
	var p1 := pos + Vector3(hw, -hh, -hd)
	var p2 := pos + Vector3(hw, hh, -hd)
	var p3 := pos + Vector3(-hw, hh, -hd)
	var p4 := pos + Vector3(-hw, -hh, hd)
	var p5 := pos + Vector3(hw, -hh, hd)
	var p6 := pos + Vector3(hw, hh, hd)
	var p7 := pos + Vector3(-hw, hh, hd)
	
	st.set_color(color)
	
	st.set_normal(Vector3.BACK)
	st.add_vertex(p0); st.add_vertex(p3); st.add_vertex(p2)
	st.add_vertex(p0); st.add_vertex(p2); st.add_vertex(p1)
	
	st.set_normal(Vector3.FORWARD)
	st.add_vertex(p5); st.add_vertex(p6); st.add_vertex(p7)
	st.add_vertex(p5); st.add_vertex(p7); st.add_vertex(p4)
	
	st.set_normal(Vector3.LEFT)
	st.add_vertex(p4); st.add_vertex(p7); st.add_vertex(p3)
	st.add_vertex(p4); st.add_vertex(p3); st.add_vertex(p0)
	
	st.set_normal(Vector3.RIGHT)
	st.add_vertex(p1); st.add_vertex(p2); st.add_vertex(p6)
	st.add_vertex(p1); st.add_vertex(p6); st.add_vertex(p5)
	
	st.set_normal(Vector3.UP)
	st.add_vertex(p3); st.add_vertex(p7); st.add_vertex(p6)
	st.add_vertex(p3); st.add_vertex(p6); st.add_vertex(p2)
	
	st.set_normal(Vector3.DOWN)
	st.add_vertex(p4); st.add_vertex(p0); st.add_vertex(p1)
	st.add_vertex(p4); st.add_vertex(p1); st.add_vertex(p5)


func _make_voxel_rock_1() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color.WHITE
	_add_box(st, Vector3(0, 0.2, 0), Vector3(0.6, 0.4, 0.5), c)
	_add_box(st, Vector3(0.1, 0.4, -0.1), Vector3(0.4, 0.2, 0.3), c)
	return st.commit()


func _make_voxel_rock_2() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color.WHITE
	_add_box(st, Vector3(0, 0.15, 0), Vector3(0.8, 0.3, 0.6), c)
	_add_box(st, Vector3(-0.2, 0.35, 0.1), Vector3(0.3, 0.3, 0.3), c)
	_add_box(st, Vector3(0.2, 0.25, -0.1), Vector3(0.3, 0.2, 0.2), c)
	return st.commit()


func _make_voxel_rock_3() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color.WHITE
	_add_box(st, Vector3(0, 0.3, 0), Vector3(0.5, 0.6, 0.4), c)
	_add_box(st, Vector3(0, 0.7, 0), Vector3(0.3, 0.4, 0.2), c)
	return st.commit()

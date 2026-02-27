extends Node3D
class_name PlanetFloraRenderer

var _projector: PlanetProjector = null
var _grid: TorusGrid = null
var _ecs: EcsWorld = null

var _multimeshes: Dictionary = {}
var _mesh_cache: Dictionary = {}

var _rebuild_timer: float = 0.0
const REBUILD_INTERVAL := 4.0
const MAX_INSTANCES_PER_TYPE := 4096

var _is_rebuilding: bool = false
const _ComGrove = preload("res://components/com_grove.gd")

func setup(proj: PlanetProjector, grid: TorusGrid, ecs: EcsWorld) -> void:
	_projector = proj
	_grid = grid
	_ecs = ecs


func _process(delta: float) -> void:
	if _is_rebuilding:
		return
	_rebuild_timer += delta
	if _rebuild_timer >= REBUILD_INTERVAL:
		_rebuild_timer = 0.0
		_rebuild_all_async()


var _rebuild_start_time: int = 0

func _rebuild_all_async() -> void:
	if _ecs == null or _projector == null:
		return

	_is_rebuilding = true
	var by_type: Dictionary = {}

	var plants := _ecs.get_components("ComPlantSpecies")
	var growths := _ecs.get_components("ComGrowth")
	var positions := _ecs.get_components("ComPosition")
	var flammables := _ecs.get_components("ComFlammable")
	var groves := _ecs.get_components("ComGrove")

	var keys := plants.keys()
	_rebuild_start_time = Time.get_ticks_msec()

	for eid in keys:
		if Time.get_ticks_msec() - _rebuild_start_time > 4:
			await get_tree().process_frame
			_rebuild_start_time = Time.get_ticks_msec()
			if _ecs == null:
				_is_rebuilding = false
				return

		if not growths.has(eid) or not positions.has(eid):
			continue

		var plant: ComPlantSpecies = plants[eid]
		var growth: ComGrowth = growths[eid]
		var pos: ComPosition = positions[eid]
		var grove: _ComGrove = groves.get(eid) as _ComGrove

		if growth.stage == DefEnums.GrowthStage.DEAD:
			continue

		var species_data: Dictionary = DefFlora.SPECIES_DATA.get(plant.species_name, {})
		if species_data.is_empty():
			continue

		var flora_type: int = species_data.get("flora_type", DefFlora.FloraType.TREE)
		var type_key := _get_type_key(flora_type)

		if not by_type.has(type_key):
			by_type[type_key] = []

		var is_burning := false
		if flammables.has(eid):
			is_burning = (flammables[eid] as ComFlammable).is_burning

		by_type[type_key].append({
			"pos": pos,
			"growth": growth,
			"species": species_data,
			"burning": is_burning,
			"grove": grove,
			"eid": eid
		})

	for type_key in by_type.keys():
		await _update_multimesh_async(type_key, by_type[type_key])
		if _ecs == null:
			_is_rebuilding = false
			return

	for type_key in _multimeshes.keys():
		if not by_type.has(type_key):
			var mmi: MultiMeshInstance3D = _multimeshes[type_key]
			mmi.multimesh.instance_count = 0

	_is_rebuilding = false


func _update_multimesh_async(type_key: String, instances: Array) -> void:
	if not _multimeshes.has(type_key):
		_create_multimesh_node(type_key)

	var mmi: MultiMeshInstance3D = _multimeshes[type_key]
	var mm: MultiMesh = mmi.multimesh
	
	# Calculate total instances to render
	var total_instances := 0
	for data in instances:
		var grove: _ComGrove = data.get("grove")
		if grove:
			total_instances += grove.tree_count
		else:
			total_instances += 1
			
	var count := mini(total_instances, MAX_INSTANCES_PER_TYPE)
	mm.instance_count = count

	var instance_idx := 0
	for data in instances:
		if instance_idx >= count:
			break
			
		if Time.get_ticks_msec() - _rebuild_start_time > 4:
			await get_tree().process_frame
			_rebuild_start_time = Time.get_ticks_msec()
			if _ecs == null:
				return

		var pos: ComPosition = data["pos"]
		var growth: ComGrowth = data["growth"]
		var species: Dictionary = data["species"]
		var burning: bool = data["burning"]
		var grove: _ComGrove = data["grove"]
		var eid: int = data["eid"]
		
		var trees_to_spawn := 1
		var radius := 0.0
		if grove:
			trees_to_spawn = grove.tree_count
			radius = grove.radius

		for j in range(trees_to_spawn):
			if instance_idx >= count:
				break
				
			# Jitter the position within the grove radius
			var offset_x := 0.0
			var offset_y := 0.0
			if trees_to_spawn > 1:
				var hash_val := _jitter_hash(eid, j, 2)
				var angle := hash_val * TAU
				var r := sqrt(_jitter_hash(eid, j, 3)) * radius
				offset_x = cos(angle) * r
				offset_y = sin(angle) * r

			var wp: Vector3 = _get_surface_pos_offset(pos, offset_x, offset_y)

			var up := wp.normalized()
			var mesh_height: float = species.get("mesh_height", 0.5)
			
			# Vary height slightly per tree in grove
			var height_variation := 1.0 + (_jitter_hash(eid, j, 4) - 0.5) * 0.4
			var stage_scale := _stage_scale(growth.stage) * height_variation
			var planet_scale := GameConfig.PLANET_RADIUS / 100.0
			var final_height := mesh_height * stage_scale * planet_scale
			var width_scale := stage_scale * 0.4 * planet_scale

			var t := Transform3D()
			t = t.scaled(Vector3(width_scale, final_height, width_scale))
			
			var fwd := up.cross(Vector3.RIGHT)
			if fwd.length_squared() < 0.001:
				fwd = up.cross(Vector3.FORWARD)
			fwd = fwd.normalized()
			
			# Add random rotation per tree
			var rand_rot := _jitter_hash(eid, j, 5) * TAU
			var local_right := fwd.cross(up).normalized()
			var rot_fwd := fwd * cos(rand_rot) + local_right * sin(rand_rot)
			var rot_right := rot_fwd.cross(up).normalized()
			
			t.basis = Basis(rot_right, up, rot_fwd) * t.basis
			t.origin = wp

			mm.set_instance_transform(instance_idx, t)

			var base_color: Color = species.get("mesh_color", Color(0.3, 0.5, 0.2))
			
			# Add color variation per tree
			var h_shift := (_jitter_hash(eid, j, 6) - 0.5) * 0.05
			var s_shift := (_jitter_hash(eid, j, 7) - 0.5) * 0.1
			var v_shift := (_jitter_hash(eid, j, 8) - 0.5) * 0.1
			base_color = Color.from_hsv(
				wrapf(base_color.h + h_shift, 0.0, 1.0),
				clampf(base_color.s + s_shift, 0.0, 1.0),
				clampf(base_color.v + v_shift, 0.0, 1.0)
			)

			if burning:
				base_color = Color(0.9, 0.3, 0.1)
			elif growth.stage == DefEnums.GrowthStage.SEED:
				base_color = base_color.darkened(0.4)
			elif growth.stage == DefEnums.GrowthStage.SAPLING:
				base_color = base_color.lightened(0.1)
			elif growth.stage == DefEnums.GrowthStage.OLD:
				base_color = base_color.darkened(0.15)

			mm.set_instance_color(instance_idx, base_color)
			instance_idx += 1


func _get_surface_pos(pos: ComPosition) -> Vector3:
	return _get_surface_pos_offset(pos, 0.0, 0.0)


func _get_surface_pos_offset(pos: ComPosition, ox: float, oy: float) -> Vector3:
	if _projector == null or _grid == null:
		return Vector3.ZERO
	var jx := _jitter_hash(pos.grid_x, pos.grid_y, 0) * 0.8
	var jy := _jitter_hash(pos.grid_x, pos.grid_y, 1) * 0.8
	var fx := float(pos.grid_x) + 0.1 + jx + ox
	var fy := float(pos.grid_y) + 0.1 + jy + oy
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


func _stage_scale(stage: int) -> float:
	match stage:
		DefEnums.GrowthStage.SEED: return 0.15
		DefEnums.GrowthStage.SAPLING: return 0.35
		DefEnums.GrowthStage.YOUNG: return 0.65
		DefEnums.GrowthStage.MATURE: return 1.0
		DefEnums.GrowthStage.OLD: return 0.85
		_: return 0.0


func _get_type_key(flora_type: int) -> String:
	match flora_type:
		DefFlora.FloraType.TREE: return "tree"
		DefFlora.FloraType.BUSH: return "bush"
		DefFlora.FloraType.GRASS: return "grass"
		DefFlora.FloraType.AQUATIC: return "aquatic"
		DefFlora.FloraType.GROUND_COVER: return "ground"
		_: return "tree"


func _create_multimesh_node(type_key: String) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = 0
	mm.mesh = _get_base_mesh(type_key)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Flora_" + type_key
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.material_override = _create_flora_material(type_key)
	add_child(mmi)

	_multimeshes[type_key] = mmi


func _create_flora_material(type_key: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	match type_key:
		"tree":
			mat.roughness = 0.82
			mat.specular_amount = 0.15
		"bush":
			mat.roughness = 0.85
			mat.specular_amount = 0.12
		"grass":
			mat.roughness = 0.90
			mat.specular_amount = 0.08
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold = 0.1
		"aquatic":
			mat.roughness = 0.60
			mat.specular_amount = 0.35
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		"ground":
			mat.roughness = 0.92
			mat.specular_amount = 0.05
		_:
			mat.roughness = 0.80
			mat.specular_amount = 0.15

	return mat


func _get_base_mesh(type_key: String) -> Mesh:
	if _mesh_cache.has(type_key):
		return _mesh_cache[type_key]

	var mesh: Mesh
	match type_key:
		"tree":
			mesh = _make_voxel_tree()
		"bush":
			mesh = _make_voxel_bush()
		"grass":
			mesh = _make_voxel_grass()
		"aquatic":
			mesh = _make_voxel_aquatic()
		"ground":
			mesh = _make_voxel_ground()
		_:
			mesh = _make_voxel_tree()

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
	
	# Front (-Z)
	st.set_normal(Vector3.BACK)
	st.add_vertex(p0); st.add_vertex(p3); st.add_vertex(p2)
	st.add_vertex(p0); st.add_vertex(p2); st.add_vertex(p1)
	
	# Back (+Z)
	st.set_normal(Vector3.FORWARD)
	st.add_vertex(p5); st.add_vertex(p6); st.add_vertex(p7)
	st.add_vertex(p5); st.add_vertex(p7); st.add_vertex(p4)
	
	# Left (-X)
	st.set_normal(Vector3.LEFT)
	st.add_vertex(p4); st.add_vertex(p7); st.add_vertex(p3)
	st.add_vertex(p4); st.add_vertex(p3); st.add_vertex(p0)
	
	# Right (+X)
	st.set_normal(Vector3.RIGHT)
	st.add_vertex(p1); st.add_vertex(p2); st.add_vertex(p6)
	st.add_vertex(p1); st.add_vertex(p6); st.add_vertex(p5)
	
	# Top (+Y)
	st.set_normal(Vector3.UP)
	st.add_vertex(p3); st.add_vertex(p7); st.add_vertex(p6)
	st.add_vertex(p3); st.add_vertex(p6); st.add_vertex(p2)
	
	# Bottom (-Y)
	st.set_normal(Vector3.DOWN)
	st.add_vertex(p4); st.add_vertex(p0); st.add_vertex(p1)
	st.add_vertex(p4); st.add_vertex(p1); st.add_vertex(p5)


func _make_voxel_tree() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var trunk_col := Color(0.6, 0.4, 0.3)
	var leaf_col := Color(1.0, 1.0, 1.0)
	
	_add_box(st, Vector3(0, 0.2, 0), Vector3(0.2, 0.4, 0.2), trunk_col)
	_add_box(st, Vector3(0, 0.6, 0), Vector3(0.8, 0.4, 0.8), leaf_col)
	_add_box(st, Vector3(0, 1.0, 0), Vector3(0.6, 0.4, 0.6), leaf_col)
	_add_box(st, Vector3(0, 1.4, 0), Vector3(0.4, 0.4, 0.4), leaf_col)
	
	return st.commit()


func _make_voxel_bush() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf_col := Color(1.0, 1.0, 1.0)
	_add_box(st, Vector3(0, 0.2, 0), Vector3(0.6, 0.4, 0.6), leaf_col)
	_add_box(st, Vector3(0, 0.5, 0), Vector3(0.4, 0.3, 0.4), leaf_col)
	return st.commit()


func _make_voxel_grass() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf_col := Color(1.0, 1.0, 1.0)
	_add_box(st, Vector3(0, 0.1, 0), Vector3(0.1, 0.2, 0.1), leaf_col)
	_add_box(st, Vector3(-0.15, 0.05, 0.1), Vector3(0.1, 0.1, 0.1), leaf_col)
	_add_box(st, Vector3(0.1, 0.08, -0.15), Vector3(0.1, 0.16, 0.1), leaf_col)
	return st.commit()


func _make_voxel_aquatic() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf_col := Color(1.0, 1.0, 1.0)
	_add_box(st, Vector3(0, 0.2, 0), Vector3(0.15, 0.4, 0.15), leaf_col)
	_add_box(st, Vector3(0.2, 0.3, 0), Vector3(0.15, 0.3, 0.15), leaf_col)
	_add_box(st, Vector3(-0.1, 0.25, 0.2), Vector3(0.15, 0.2, 0.15), leaf_col)
	return st.commit()


func _make_voxel_ground() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf_col := Color(1.0, 1.0, 1.0)
	_add_box(st, Vector3(0, 0.05, 0), Vector3(0.5, 0.1, 0.5), leaf_col)
	return st.commit()

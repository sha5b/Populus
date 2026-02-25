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

	var plants := _ecs.get_components("ComPlantSpecies")
	var growths := _ecs.get_components("ComGrowth")
	var positions := _ecs.get_components("ComPosition")
	var flammables := _ecs.get_components("ComFlammable")

	for eid in plants.keys():
		if not growths.has(eid) or not positions.has(eid):
			continue

		var plant: ComPlantSpecies = plants[eid]
		var growth: ComGrowth = growths[eid]
		var pos: ComPosition = positions[eid]

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
		var growth: ComGrowth = data["growth"]
		var species: Dictionary = data["species"]
		var burning: bool = data["burning"]

		var wp: Vector3 = _get_surface_pos(pos)

		var up := wp.normalized()
		var mesh_height: float = species.get("mesh_height", 0.5)
		var stage_scale := _stage_scale(growth.stage)
		var planet_scale := GameConfig.PLANET_RADIUS / 100.0
		var final_height := mesh_height * stage_scale * planet_scale
		var width_scale := stage_scale * 0.4 * planet_scale

		var t := Transform3D()
		t = t.scaled(Vector3(width_scale, final_height, width_scale))

		var fwd := up.cross(Vector3.RIGHT)
		if fwd.length_squared() < 0.001:
			fwd = up.cross(Vector3.FORWARD)
		fwd = fwd.normalized()
		var right := fwd.cross(up).normalized()
		t.basis = Basis(right, up, fwd) * t.basis

		t.origin = wp

		mm.set_instance_transform(i, t)

		var base_color: Color = species.get("mesh_color", Color(0.3, 0.5, 0.2))

		if burning:
			base_color = Color(0.9, 0.3, 0.1)
		elif growth.stage == DefEnums.GrowthStage.SEED:
			base_color = base_color.darkened(0.4)
		elif growth.stage == DefEnums.GrowthStage.SAPLING:
			base_color = base_color.lightened(0.1)
		elif growth.stage == DefEnums.GrowthStage.OLD:
			base_color = base_color.darkened(0.15)

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
			mesh = _make_cone_mesh(1.0, 0.3)
		"bush":
			mesh = _make_sphere_mesh(0.3)
		"grass":
			mesh = _make_quad_mesh(0.15, 0.25)
		"aquatic":
			mesh = _make_quad_mesh(0.1, 0.4)
		"ground":
			mesh = _make_flat_mesh(0.15)
		_:
			mesh = _make_cone_mesh(0.5, 0.2)

	_mesh_cache[type_key] = mesh
	return mesh


func _make_cone_mesh(height: float, radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)

	var segments := 6
	var tip := Vector3(0, height, 0)
	var base_center := Vector3(0, 0, 0)

	for i in range(segments):
		var angle_a := float(i) / float(segments) * TAU
		var angle_b := float(i + 1) / float(segments) * TAU
		var a := Vector3(cos(angle_a) * radius, 0, sin(angle_a) * radius)
		var b := Vector3(cos(angle_b) * radius, 0, sin(angle_b) * radius)

		st.set_normal((a + b).normalized() + Vector3.UP)
		st.add_vertex(a)
		st.add_vertex(tip)
		st.add_vertex(b)

		st.set_normal(Vector3.DOWN)
		st.add_vertex(b)
		st.add_vertex(base_center)
		st.add_vertex(a)

	return st.commit()


func _make_sphere_mesh(radius: float) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 6
	sphere.rings = 4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	st.append_from(sphere, 0, Transform3D.IDENTITY)
	return st.commit()


func _make_quad_mesh(width: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	var hw := width * 0.5

	st.set_normal(Vector3.BACK)
	st.add_vertex(Vector3(-hw, 0, 0))
	st.add_vertex(Vector3(-hw, height, 0))
	st.add_vertex(Vector3(hw, height, 0))
	st.add_vertex(Vector3(-hw, 0, 0))
	st.add_vertex(Vector3(hw, height, 0))
	st.add_vertex(Vector3(hw, 0, 0))

	st.set_normal(Vector3.RIGHT)
	st.add_vertex(Vector3(0, 0, -hw))
	st.add_vertex(Vector3(0, height, -hw))
	st.add_vertex(Vector3(0, height, hw))
	st.add_vertex(Vector3(0, 0, -hw))
	st.add_vertex(Vector3(0, height, hw))
	st.add_vertex(Vector3(0, 0, hw))

	return st.commit()


func _make_flat_mesh(radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(-radius, 0.01, -radius))
	st.add_vertex(Vector3(-radius, 0.01, radius))
	st.add_vertex(Vector3(radius, 0.01, radius))
	st.add_vertex(Vector3(-radius, 0.01, -radius))
	st.add_vertex(Vector3(radius, 0.01, radius))
	st.add_vertex(Vector3(radius, 0.01, -radius))
	return st.commit()

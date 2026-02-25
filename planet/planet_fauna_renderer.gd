extends Node3D
class_name PlanetFaunaRenderer

var _projector: PlanetProjector = null
var _grid: TorusGrid = null
var _ecs: EcsWorld = null

var _multimeshes: Dictionary = {}
var _mesh_cache: Dictionary = {}

var _rebuild_timer: float = 0.0
const REBUILD_INTERVAL := 1.0
const MAX_INSTANCES_PER_TYPE := 512

const SPECIES_COLORS: Dictionary = {
	"deer": Color(0.6, 0.4, 0.2),
	"wolf": Color(0.5, 0.5, 0.5),
	"rabbit": Color(0.85, 0.85, 0.8),
	"bear": Color(0.35, 0.2, 0.1),
	"eagle": Color(0.8, 0.7, 0.3),
	"fish": Color(0.3, 0.5, 0.8),
	"bison": Color(0.4, 0.3, 0.15),
}

const SPECIES_SCALE: Dictionary = {
	"deer": Vector3(0.3, 0.5, 0.6),
	"wolf": Vector3(0.25, 0.35, 0.5),
	"rabbit": Vector3(0.12, 0.15, 0.2),
	"bear": Vector3(0.5, 0.6, 0.7),
	"eagle": Vector3(0.2, 0.1, 0.4),
	"fish": Vector3(0.1, 0.08, 0.2),
	"bison": Vector3(0.5, 0.55, 0.8),
}


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

	var by_species: Dictionary = {}

	var fauna_comps := _ecs.get_components("ComFaunaSpecies")
	var positions := _ecs.get_components("ComPosition")
	var ai_states := _ecs.get_components("ComAiState")

	for eid in fauna_comps.keys():
		if not positions.has(eid):
			continue
		var species: ComFaunaSpecies = fauna_comps[eid]
		var pos: ComPosition = positions[eid]
		var ai: ComAiState = ai_states.get(eid) as ComAiState

		var key := species.species_key
		if not by_species.has(key):
			by_species[key] = []

		by_species[key].append({
			"pos": pos,
			"species": species,
			"ai": ai,
		})

	for key in SPECIES_COLORS:
		if not by_species.has(key):
			_set_instance_count(key, 0)
			continue
		var instances: Array = by_species[key]
		var count := mini(instances.size(), MAX_INSTANCES_PER_TYPE)
		var mm := _get_or_create_multimesh(key, count)
		_update_instances(mm, instances, key, count)


func _get_or_create_multimesh(species_key: String, count: int) -> MultiMesh:
	if not _multimeshes.has(species_key):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _get_mesh(species_key)
		mm.instance_count = count

		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "Fauna_" + species_key

		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		mmi.material_override = mat

		add_child(mmi)
		_multimeshes[species_key] = mm
	else:
		_multimeshes[species_key].instance_count = count
	return _multimeshes[species_key]


func _set_instance_count(species_key: String, count: int) -> void:
	if _multimeshes.has(species_key):
		_multimeshes[species_key].instance_count = count


func _get_mesh(species_key: String) -> Mesh:
	if _mesh_cache.has(species_key):
		return _mesh_cache[species_key]

	var mesh := SphereMesh.new()
	var sc: Vector3 = SPECIES_SCALE.get(species_key, Vector3(0.3, 0.3, 0.3))
	mesh.radius = sc.x
	mesh.height = sc.y * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	_mesh_cache[species_key] = mesh
	return mesh


func _update_instances(mm: MultiMesh, instances: Array, species_key: String, count: int) -> void:
	var base_color: Color = SPECIES_COLORS.get(species_key, Color.WHITE)

	for i in range(count):
		var data: Dictionary = instances[i]
		var pos: ComPosition = data["pos"]
		var species: ComFaunaSpecies = data["species"]
		var ai: ComAiState = data["ai"]

		var wp := _get_surface_pos(pos, species)
		var up := wp.normalized()

		var sc: Vector3 = SPECIES_SCALE.get(species_key, Vector3(0.3, 0.3, 0.3))
		var t := Transform3D()
		t = t.scaled(sc)

		var fwd := up.cross(Vector3.RIGHT)
		if fwd.length_squared() < 0.001:
			fwd = up.cross(Vector3.FORWARD)
		fwd = fwd.normalized()
		var right := fwd.cross(up).normalized()
		t.basis = Basis(right, up, fwd) * t.basis

		t.origin = wp + up * sc.y

		mm.set_instance_transform(i, t)

		var col := base_color
		if ai != null:
			match ai.current_state:
				DefEnums.AIState.HUNTING:
					col = base_color.lerp(Color.RED, 0.3)
				DefEnums.AIState.FLEEING:
					col = base_color.lerp(Color.YELLOW, 0.4)
				DefEnums.AIState.SLEEPING:
					col = base_color.darkened(0.4)
				DefEnums.AIState.MATING:
					col = base_color.lerp(Color.MAGENTA, 0.3)
		mm.set_instance_color(i, col)


func _get_surface_pos(pos: ComPosition, species: ComFaunaSpecies) -> Vector3:
	if _projector == null or _grid == null:
		return Vector3.ZERO
	var fx := float(pos.grid_x) + 0.5
	var fy := float(pos.grid_y) + 0.5
	var h := _grid.get_height(pos.grid_x, pos.grid_y)
	if species.is_aquatic:
		h = minf(h, GameConfig.SEA_LEVEL)
	var dir := _projector.grid_to_sphere(fx, fy).normalized()
	return dir * (_projector.radius + h * _projector.height_scale)

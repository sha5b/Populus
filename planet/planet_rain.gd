extends Node3D
class_name PlanetRain

var _projector: PlanetProjector
var _atmo_grid: AtmosphereGrid
var _scale: float = 1.0
var _camera: Camera3D = null
var _lightning_bolt: MeshInstance3D = null
var _lightning_timer: float = 0.0

func setup(proj: PlanetProjector, atmo: AtmosphereGrid = null) -> void:
	_projector = proj
	_atmo_grid = atmo
	_scale = proj.radius / 50.0

	_lightning_bolt = _create_lightning_bolt()
	_lightning_bolt.visible = false
	add_child(_lightning_bolt)


func set_camera(cam: Camera3D) -> void:
	_camera = cam


func _create_lightning_bolt() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 0.9, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.9, 1.0)
	mat.emission_energy_multiplier = 8.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mi.material_override = mat
	return mi


func set_raining(_active: bool, _snow: bool = false) -> void:
	pass


func set_fog(_active: bool) -> void:
	pass


func set_storm(_is_storm: bool) -> void:
	pass


func trigger_lightning() -> void:
	_lightning_timer = 0.3
	if _lightning_bolt:
		_lightning_bolt.visible = true
		_rebuild_lightning_mesh()


func _process(delta: float) -> void:
	if _lightning_timer > 0.0:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0 and _lightning_bolt:
			_lightning_bolt.visible = false


func _rebuild_lightning_mesh() -> void:
	var cam := _camera
	if cam == null:
		cam = get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null or _projector == null:
		return
	var cam_pos := cam.global_position
	var surface_dir := cam_pos.normalized()
	var tangent := surface_dir.cross(Vector3.UP).normalized()
	if tangent.length_squared() < 0.01:
		tangent = surface_dir.cross(Vector3.RIGHT).normalized()
	var bitangent := surface_dir.cross(tangent).normalized()

	# Place bolt on the planet surface below camera, offset sideways
	var s := _scale
	var surface_point := surface_dir * (_projector.radius + 1.0)
	var lateral_offset := tangent * randf_range(-20.0 * s, 20.0 * s) + bitangent * randf_range(-12.0 * s, 12.0 * s)
	var bolt_top := surface_point + lateral_offset + surface_dir * 20.0 * s
	var bolt_bottom := surface_point + lateral_offset - surface_dir * 2.0 * s

	var im := _lightning_bolt.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	var segments := 12
	var bolt_width := 5.0 * s
	var right := tangent
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var pos := bolt_top.lerp(bolt_bottom, t)
		if i > 0 and i < segments:
			pos += tangent * randf_range(-5.0 * s, 5.0 * s) + bitangent * randf_range(-3.0 * s, 3.0 * s)
		var w := bolt_width * (1.0 - t * 0.6)
		var alpha := 1.0 - t * 0.3
		im.surface_set_color(Color(1.0, 1.0, 0.95, alpha))
		im.surface_add_vertex(pos + right * w)
		im.surface_set_color(Color(1.0, 1.0, 0.95, alpha))
		im.surface_add_vertex(pos - right * w)

	im.surface_end()


func update_positions() -> void:
	pass

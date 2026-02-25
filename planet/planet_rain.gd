extends Node3D
class_name PlanetRain

const MAX_EMITTERS := 6
const FOG_EMITTER_COUNT := 3

var _projector: PlanetProjector
var _grid: TorusGrid
var _scale: float = 1.0
var _emitters: Array[GPUParticles3D] = []
var _fog_emitters: Array[GPUParticles3D] = []
var _lightning_bolt: MeshInstance3D = null
var _lightning_timer: float = 0.0
var _active: bool = false
var _is_snow: bool = false
var _fog_active: bool = false


func setup(proj: PlanetProjector, g: TorusGrid = null) -> void:
	_projector = proj
	_grid = g
	_scale = proj.radius / 50.0

	for i in range(MAX_EMITTERS):
		var emitter := _create_rain_emitter()
		emitter.emitting = false
		add_child(emitter)
		_emitters.append(emitter)

	for i in range(FOG_EMITTER_COUNT):
		var fog := _create_fog_emitter()
		fog.emitting = false
		add_child(fog)
		_fog_emitters.append(fog)

	_lightning_bolt = _create_lightning_bolt()
	_lightning_bolt.visible = false
	add_child(_lightning_bolt)


func _get_emitter_offsets() -> Array[Vector2]:
	var s := _scale
	return [
		Vector2(0, 0), Vector2(25 * s, 0), Vector2(-25 * s, 0),
		Vector2(0, 25 * s), Vector2(0, -25 * s), Vector2(18 * s, 18 * s),
	]


func _create_rain_emitter() -> GPUParticles3D:
	var s := _scale
	var p := GPUParticles3D.new()
	p.amount = 1500
	p.lifetime = 2.5
	var aabb_size := 120.0 * s
	p.visibility_aabb = AABB(Vector3(-aabb_size, -aabb_size, -aabb_size), Vector3(aabb_size * 2, aabb_size * 2, aabb_size * 2))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 12.0
	mat.initial_velocity_min = 15.0
	mat.initial_velocity_max = 30.0
	mat.gravity = Vector3(0, -40, 0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(40.0 * s, 5.0 * s, 40.0 * s)
	p.process_material = mat

	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0 * s, 8.0 * s)
	p.draw_pass_1 = mesh

	var draw_mat := StandardMaterial3D.new()
	draw_mat.albedo_color = Color(0.75, 0.85, 1.0, 0.4)
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw_mat.no_depth_test = true
	mesh.material = draw_mat

	return p


func _create_fog_emitter() -> GPUParticles3D:
	var s := _scale
	var p := GPUParticles3D.new()
	p.amount = 120
	p.lifetime = 8.0
	var aabb_size := 120.0 * s
	p.visibility_aabb = AABB(Vector3(-aabb_size, -aabb_size * 0.5, -aabb_size), Vector3(aabb_size * 2, aabb_size, aabb_size * 2))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 0.8
	mat.gravity = Vector3(0, 0, 0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(40.0 * s, 8.0 * s, 40.0 * s)
	p.process_material = mat

	var mesh := QuadMesh.new()
	mesh.size = Vector2(50.0 * s, 25.0 * s)
	p.draw_pass_1 = mesh

	var draw_mat := StandardMaterial3D.new()
	draw_mat.albedo_color = Color(0.82, 0.85, 0.9, 0.25)
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.no_depth_test = true
	mesh.material = draw_mat

	return p


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


func set_raining(active: bool, snow: bool = false) -> void:
	_active = active
	_is_snow = snow
	for e in _emitters:
		e.emitting = active
		var mat := e.process_material as ParticleProcessMaterial
		if snow:
			mat.initial_velocity_min = 3.0
			mat.initial_velocity_max = 6.0
			mat.spread = 35.0
		else:
			mat.initial_velocity_min = 15.0
			mat.initial_velocity_max = 30.0
			mat.spread = 12.0


func set_fog(active: bool) -> void:
	_fog_active = active
	for fog in _fog_emitters:
		fog.emitting = active


func set_storm(is_storm: bool) -> void:
	for e in _emitters:
		e.amount = 2500 if is_storm else 1500


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
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
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
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null or _projector == null:
		return

	var cam_pos := cam.global_position
	var surface_up := cam_pos.normalized()
	var tangent := surface_up.cross(Vector3.UP).normalized()
	if tangent.length_squared() < 0.01:
		tangent = surface_up.cross(Vector3.RIGHT).normalized()
	var bitangent := surface_up.cross(tangent).normalized()

	# Place rain at planet surface below camera, not at camera orbit altitude
	var s := _scale
	var surface_point := surface_up * (_projector.radius + 1.0)
	var offsets := _get_emitter_offsets()

	for i in range(MAX_EMITTERS):
		var offset := offsets[i] if i < offsets.size() else Vector2.ZERO
		var world_pos := surface_point + tangent * offset.x + bitangent * offset.y + surface_up * 20.0 * s

		var orient := Basis(tangent, surface_up, bitangent)
		_emitters[i].global_transform = Transform3D(orient, world_pos)

		var mat := _emitters[i].process_material as ParticleProcessMaterial
		if mat:
			mat.gravity = Vector3(0, -1, 0) * (8.0 if _is_snow else 50.0)
			mat.direction = Vector3(0, -1, 0)

	var fog_spread := 25.0 * s
	var fog_offsets: Array[Vector3] = [Vector3.ZERO, tangent * fog_spread, bitangent * fog_spread]
	for i in range(mini(_fog_emitters.size(), fog_offsets.size())):
		var fog_pos: Vector3 = surface_point + fog_offsets[i] + surface_up * 5.0 * s
		var fog_orient := Basis(tangent, surface_up, bitangent)
		_fog_emitters[i].global_transform = Transform3D(fog_orient, fog_pos)

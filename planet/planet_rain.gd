extends Node3D
class_name PlanetRain

const MAX_EMITTERS := 8

var _projector: PlanetProjector
var _emitters: Array[GPUParticles3D] = []
var _emitter_grid_pos: Array[Vector2] = []
var _active: bool = false
var _is_snow: bool = false


func setup(proj: PlanetProjector) -> void:
	_projector = proj

	for i in range(MAX_EMITTERS):
		var emitter := _create_rain_emitter()
		emitter.emitting = false
		add_child(emitter)
		_emitters.append(emitter)
		_emitter_grid_pos.append(Vector2.ZERO)

	_distribute_emitters()


func _create_rain_emitter() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 100
	p.lifetime = 1.2
	p.visibility_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 8.0
	mat.initial_velocity_min = 15.0
	mat.initial_velocity_max = 25.0
	mat.gravity = Vector3(0, -30, 0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(5.0, 0.5, 5.0)
	p.process_material = mat

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.04, 0.3)
	p.draw_pass_1 = mesh

	var draw_mat := StandardMaterial3D.new()
	draw_mat.albedo_color = Color(0.7, 0.8, 1.0, 0.3)
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh.material = draw_mat

	return p


func _distribute_emitters() -> void:
	var w := float(_projector.width)
	var h := float(_projector.height)
	for i in range(MAX_EMITTERS):
		_emitter_grid_pos[i] = Vector2(randf() * w, randf() * h)


func set_raining(active: bool, snow: bool = false) -> void:
	_active = active
	_is_snow = snow
	for e in _emitters:
		e.emitting = active
		if snow:
			var mat := e.process_material as ParticleProcessMaterial
			mat.initial_velocity_min = 3.0
			mat.initial_velocity_max = 6.0
			mat.gravity = Vector3(0, -5, 0)
			mat.spread = 25.0
		else:
			var mat := e.process_material as ParticleProcessMaterial
			mat.initial_velocity_min = 15.0
			mat.initial_velocity_max = 25.0
			mat.gravity = Vector3(0, -30, 0)
			mat.spread = 8.0


func set_storm(is_storm: bool) -> void:
	for e in _emitters:
		e.amount = 300 if is_storm else 100


func update_positions() -> void:
	if not _projector:
		return

	var hs := _projector.height_scale
	for i in range(MAX_EMITTERS):
		var gpos := _emitter_grid_pos[i]
		var world_pos := _projector.grid_to_sphere(gpos.x, gpos.y, 2.0 / hs)

		var surface_normal := world_pos.normalized()
		var tangent := surface_normal.cross(Vector3.UP).normalized()
		if tangent.length_squared() < 0.01:
			tangent = surface_normal.cross(Vector3.RIGHT).normalized()
		var bitangent := surface_normal.cross(tangent).normalized()

		var orient := Basis(tangent, surface_normal, bitangent)
		_emitters[i].global_transform = Transform3D(orient, world_pos)

		var mat := _emitters[i].process_material as ParticleProcessMaterial
		if mat:
			mat.gravity = -surface_normal * (5.0 if _is_snow else 30.0)
			mat.direction = -surface_normal

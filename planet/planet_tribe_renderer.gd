extends Node3D
class_name PlanetTribeRenderer

const ComFollowerScript = preload("res://components/com_follower.gd")

var projector: PlanetProjector
var grid: TorusGrid
var ecs: EcsWorld

var _follower_mesh: MeshInstance3D
var _follower_multimesh: MultiMesh
var _building_mesh: MeshInstance3D
var _building_multimesh: MultiMesh

var _materials: Dictionary = {}

const MAX_FOLLOWERS := 2000
const MAX_BUILDINGS := 500


func setup(proj: PlanetProjector, g: TorusGrid, w: EcsWorld) -> void:
	projector = proj
	grid = g
	ecs = w

	_setup_materials()
	_setup_multimeshes()


func _setup_materials() -> void:
	var shader := load("res://shaders/toon_stripe.gdshader") as Shader
	if shader == null:
		push_error("Failed to load toon_stripe.gdshader")
		return

	# Blue Tribe
	var mat_blue := ShaderMaterial.new()
	mat_blue.shader = shader
	mat_blue.set_shader_parameter("primary_color", Color(0.2, 0.4, 0.8))
	mat_blue.set_shader_parameter("stripe_color", Color(0.9, 0.9, 0.9))
	mat_blue.set_shader_parameter("stripe_angle", 45.0) # Diagonal stripes for tribes
	mat_blue.set_shader_parameter("stripe_scale", 8.0)
	_materials[DefEnums.TribeId.BLUE] = mat_blue

	# Red Tribe
	var mat_red := ShaderMaterial.new()
	mat_red.shader = shader
	mat_red.set_shader_parameter("primary_color", Color(0.8, 0.2, 0.2))
	mat_red.set_shader_parameter("stripe_color", Color(0.9, 0.9, 0.9))
	mat_red.set_shader_parameter("stripe_angle", 45.0)
	mat_red.set_shader_parameter("stripe_scale", 8.0)
	_materials[DefEnums.TribeId.RED] = mat_red


func _setup_multimeshes() -> void:
	# Followers (small capsules)
	var f_mesh := CapsuleMesh.new()
	f_mesh.radius = 1.2
	f_mesh.height = 3.5
	f_mesh.radial_segments = 8
	f_mesh.rings = 2

	_follower_multimesh = MultiMesh.new()
	_follower_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_follower_multimesh.use_colors = true
	_follower_multimesh.instance_count = MAX_FOLLOWERS
	_follower_multimesh.mesh = f_mesh

	_follower_mesh = MeshInstance3D.new()
	_follower_mesh.multimesh = _follower_multimesh
	_follower_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Default material (though we'll use instance colors if needed, or split by tribe later)
	_follower_mesh.material_override = _materials.get(DefEnums.TribeId.BLUE)
	add_child(_follower_mesh)

	# Buildings (boxes)
	var b_mesh := BoxMesh.new()
	b_mesh.size = Vector3(4.0, 4.0, 4.0)

	_building_multimesh = MultiMesh.new()
	_building_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_building_multimesh.use_colors = true
	_building_multimesh.instance_count = MAX_BUILDINGS
	_building_multimesh.mesh = b_mesh

	_building_mesh = MeshInstance3D.new()
	_building_mesh.multimesh = _building_multimesh
	_building_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_building_mesh.material_override = _materials.get(DefEnums.TribeId.BLUE)
	add_child(_building_mesh)


func _process(_delta: float) -> void:
	if ecs == null or projector == null:
		return
	_update_rendering()


func _update_rendering() -> void:
	var positions := ecs.get_components("ComPosition")
	var followers := ecs.get_components("ComFollower")
	var buildings := ecs.get_components("ComBuilding")
	var constructions := ecs.get_components("ComConstruction")

	# Update Followers
	var f_idx := 0
	for eid in followers.keys():
		if f_idx >= MAX_FOLLOWERS:
			break
		if not positions.has(eid):
			continue
		var p: ComPosition = positions[eid]
		var f = followers[eid]

		var world_pos := _get_surface_pos(p.grid_x, p.grid_y)
		var up := world_pos.normalized()
		var x_basis := _basis_from_up(up)
		var xform := Transform3D(x_basis, world_pos)

		_follower_multimesh.set_instance_transform(f_idx, xform)
		var color := Color(0.2, 0.4, 0.8) if f.tribe_id == DefEnums.TribeId.BLUE else Color(0.8, 0.2, 0.2)
		_follower_multimesh.set_instance_color(f_idx, color)
		f_idx += 1
	_follower_multimesh.visible_instance_count = f_idx

	# Update Buildings
	var b_idx := 0
	for eid in buildings.keys():
		if b_idx >= MAX_BUILDINGS:
			break
		if not positions.has(eid):
			continue
		var p: ComPosition = positions[eid]
		var b: ComBuilding = buildings[eid]

		var world_pos := _get_surface_pos(p.grid_x, p.grid_y)
		var up := world_pos.normalized()
		var x_basis := _basis_from_up(up)
		# Scale based on building size
		
		# If it's a construction, scale it down or make it look different based on progress
		var c: ComConstruction = constructions.get(eid)
		var y_scale := 1.0
		var is_construction := false
		if c and c.progress < 1.0:
			is_construction = true
			y_scale = maxf(0.1, c.progress)
			
		x_basis = x_basis.scaled(Vector3(float(b.size.x) * 0.8, y_scale, float(b.size.y) * 0.8))
		var xform := Transform3D(x_basis, world_pos)

		_building_multimesh.set_instance_transform(b_idx, xform)
		var color := Color(0.2, 0.4, 0.8) if b.tribe_id == DefEnums.TribeId.BLUE else Color(0.8, 0.2, 0.2)
		
		if is_construction:
			color = color.lerp(Color(0.5, 0.5, 0.5), 0.5) # Grayish tint for construction
			
		_building_multimesh.set_instance_color(b_idx, color)
		b_idx += 1
	_building_multimesh.visible_instance_count = b_idx


func _get_surface_pos(gx: int, gy: int) -> Vector3:
	var h := grid.get_height(gx, gy)
	var dir := projector.grid_to_sphere(float(gx), float(gy)).normalized()
	return dir * (projector.radius + maxf(h, GameConfig.SEA_LEVEL) * projector.height_scale)


func _basis_from_up(up: Vector3) -> Basis:
	var forward := Vector3.FORWARD
	if absf(up.dot(forward)) > 0.99:
		forward = Vector3.RIGHT
	var right := up.cross(forward).normalized()
	forward = right.cross(up).normalized()
	return Basis(right, up, forward)

extends Node3D
class_name PlanetCloudLayer

const MAX_REBUILDS_PER_FRAME := 12

var _projector: PlanetProjector
var _atmo_grid: AtmosphereGrid
var _cloud_material: ShaderMaterial
var _chunk_meshes: Array[MeshInstance3D] = []
var _rebuild_index: int = 0
var _cloud_altitude: float = 3.5


func setup(proj: PlanetProjector, atmo: AtmosphereGrid) -> void:
	_projector = proj
	_atmo_grid = atmo

	var shader := load("res://shaders/cloud_volume.gdshader") as Shader
	_cloud_material = ShaderMaterial.new()
	_cloud_material.shader = shader
	_cloud_material.render_priority = 1

	var total := AtmosphereGrid.TOTAL_CHUNKS
	_chunk_meshes.resize(total)
	for i in range(total):
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _cloud_material
		add_child(mi)
		_chunk_meshes[i] = mi


func update_clouds(_delta: float, _wind_dir: Vector2, _wind_speed: float) -> void:
	update_clouds_rolling(_delta)


func update_clouds_rolling(_delta: float) -> void:
	if _atmo_grid == null:
		return

	var total := AtmosphereGrid.TOTAL_CHUNKS
	for _i in range(MAX_REBUILDS_PER_FRAME):
		var ci := _rebuild_index
		_rebuild_index = (_rebuild_index + 1) % total
		_rebuild_chunk_by_idx(ci)


func _rebuild_chunk_by_idx(ci: int) -> void:
	var cpf := AtmosphereGrid.CHUNKS_PER_FACE
	var face: int = ci / (cpf * cpf)
	var rem: int = ci % (cpf * cpf)
	var cv: int = rem / cpf
	var cu := rem % cpf

	var mesh := CloudMeshGenerator.generate_chunk_mesh(
		_atmo_grid, face, cu, cv,
		_cloud_altitude
	)

	_chunk_meshes[ci].mesh = mesh


func set_global_coverage(_coverage: float) -> void:
	pass


func clear_coverage() -> void:
	pass

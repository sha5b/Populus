extends Node3D
class_name PlanetCloudLayer

const MAX_REBUILDS_PER_FRAME := 24
const CLOUD_LOD_STEP := 2

var _projector: PlanetProjector
var _atmo_grid: AtmosphereGrid
var _cloud_material: ShaderMaterial
var _chunk_meshes: Array[MeshInstance3D] = []
var _rebuild_index: int = 0
var _cloud_altitude: float = GameConfig.PLANET_RADIUS * 0.07
var _drift_since_rebuild: Vector3 = Vector3.ZERO
var _morph_t: float = 0.5
var _rebuild_cycle_timer: float = 0.0


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


func update_clouds_rolling(delta: float) -> void:
	if _atmo_grid == null:
		return

	var total := AtmosphereGrid.TOTAL_CHUNKS
	for _i in range(MAX_REBUILDS_PER_FRAME):
		var ci := _rebuild_index
		_rebuild_index = (_rebuild_index + 1) % total
		_rebuild_chunk_by_idx(ci)

	_rebuild_cycle_timer += delta
	var cycle_duration := float(total) / float(MAX_REBUILDS_PER_FRAME) / 60.0
	_morph_t = clampf(_rebuild_cycle_timer / maxf(cycle_duration, 0.1), 0.0, 1.0)
	if _rebuild_index == 0:
		_rebuild_cycle_timer = 0.0
		_drift_since_rebuild = Vector3.ZERO


func update_wind_drift(delta: float, wind_dir: Vector2, wind_speed: float) -> void:
	var speed := wind_speed * 0.15
	_drift_since_rebuild += Vector3(wind_dir.x * speed * delta, 0.0, wind_dir.y * speed * delta)
	if _cloud_material:
		_cloud_material.set_shader_parameter("wind_drift", _drift_since_rebuild)
		_cloud_material.set_shader_parameter("morph_t", _morph_t)


func _rebuild_chunk_by_idx(ci: int) -> void:
	var cpf := AtmosphereGrid.CHUNKS_PER_FACE
	var face: int = ci / (cpf * cpf)
	var rem: int = ci % (cpf * cpf)
	var cv: int = rem / cpf
	var cu := rem % cpf

	var mesh := CloudMeshGenerator.generate_chunk_mesh(
		_atmo_grid, face, cu, cv,
		_cloud_altitude, CLOUD_LOD_STEP
	)

	_chunk_meshes[ci].mesh = mesh


func set_global_coverage(coverage: float) -> void:
	if _atmo_grid:
		_atmo_grid.global_coverage_boost = coverage * 0.5


func set_weather_darkness(darkness: float) -> void:
	if _cloud_material:
		_cloud_material.set_shader_parameter("weather_darkness", darkness)


func clear_coverage() -> void:
	if _atmo_grid:
		_atmo_grid.global_coverage_boost = 0.0

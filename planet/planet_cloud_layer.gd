extends MeshInstance3D
class_name PlanetCloudLayer

var _material: ShaderMaterial


func setup(planet_radius: float) -> void:
	var sphere := SphereMesh.new()
	var cloud_radius := planet_radius + 2.0
	sphere.radius = cloud_radius
	sphere.height = cloud_radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	mesh = sphere

	var shader := load("res://shaders/clouds.gdshader") as Shader
	_material = ShaderMaterial.new()
	_material.shader = shader
	material_override = _material


func set_coverage(value: float) -> void:
	if _material:
		_material.set_shader_parameter("cloud_coverage", value)


func set_wind(direction: Vector2, speed: float) -> void:
	if _material:
		_material.set_shader_parameter("wind_direction", direction)
		_material.set_shader_parameter("cloud_speed", speed * 0.01)


func set_brightness(value: float) -> void:
	if _material:
		_material.set_shader_parameter("brightness", value)

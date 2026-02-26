extends MeshInstance3D
class_name PlanetAtmosphere

var _material: ShaderMaterial


func setup(planet_radius: float) -> void:
	var sphere := SphereMesh.new()
	var atmo_radius := planet_radius * 1.02
	sphere.radius = atmo_radius
	sphere.height = atmo_radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	mesh = sphere

	var shader := load("res://shaders/atmosphere.gdshader") as Shader
	_material = ShaderMaterial.new()
	_material.shader = shader
	material_override = _material


func set_density(value: float) -> void:
	if _material:
		_material.set_shader_parameter("atmosphere_density", value)


func set_sun_direction(dir: Vector3) -> void:
	if _material:
		_material.set_shader_parameter("sun_direction", dir)

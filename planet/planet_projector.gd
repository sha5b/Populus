class_name PlanetProjector

var width: int
var height: int
var radius: float
var height_scale: float


func _init(w: int = 128, h: int = 128, r: float = 50.0, hs: float = 5.0) -> void:
	width = w
	height = h
	radius = r
	height_scale = hs


func grid_to_sphere(gx: float, gy: float, h: float = 0.0) -> Vector3:
	var lon := (gx / float(width)) * TAU
	var lat := (gy / float(height)) * PI - PI * 0.5
	var r := radius + h * height_scale
	return Vector3(
		r * cos(lat) * cos(lon),
		r * sin(lat),
		r * cos(lat) * sin(lon)
	)


func sphere_to_grid(world_pos: Vector3) -> Vector2i:
	var r := world_pos.length()
	if r < 0.001:
		return Vector2i(0, 0)
	var lat := asin(clampf(world_pos.y / r, -1.0, 1.0))
	var lon := atan2(world_pos.z, world_pos.x)
	if lon < 0.0:
		lon += TAU
	var gx := (lon / TAU) * float(width)
	var gy := ((lat + PI * 0.5) / PI) * float(height)
	return Vector2i(int(gx) % width, int(gy) % height)


func get_sphere_normal(gx: float, gy: float) -> Vector3:
	return grid_to_sphere(gx, gy, 0.0).normalized()


func height_color(h: float) -> Color:
	if h < GameConfig.SEA_LEVEL:
		return Color(0.1, 0.25, 0.6)
	elif h < 0.15:
		return Color(0.9, 0.85, 0.6)
	elif h < 0.4:
		return Color(0.2, 0.55, 0.2)
	elif h < 0.65:
		return Color(0.45, 0.4, 0.3)
	elif h < 0.85:
		return Color(0.55, 0.5, 0.45)
	else:
		return Color(0.95, 0.95, 0.98)

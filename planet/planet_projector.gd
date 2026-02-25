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


func cube_sphere_point(face: int, u: float, v: float, altitude: float = 0.0) -> Vector3:
	var x := u * 2.0 - 1.0
	var y := v * 2.0 - 1.0
	var cube_pos: Vector3
	match face:
		0: cube_pos = Vector3( 1.0,    y,   -x)
		1: cube_pos = Vector3(-1.0,    y,    x)
		2: cube_pos = Vector3(   x,  1.0,   -y)
		3: cube_pos = Vector3(   x, -1.0,    y)
		4: cube_pos = Vector3(   x,    y,  1.0)
		_: cube_pos = Vector3(  -x,    y, -1.0)
	var dir := cube_pos.normalized()
	return dir * (radius + altitude)


func world_to_cube_face(world_pos: Vector3) -> Array:
	var dir := world_pos.normalized()
	var abs_dir := Vector3(absf(dir.x), absf(dir.y), absf(dir.z))
	var face: int
	var raw_u: float
	var raw_v: float
	if abs_dir.x >= abs_dir.y and abs_dir.x >= abs_dir.z:
		if dir.x > 0:
			face = 0; raw_u = -dir.z / dir.x; raw_v = dir.y / dir.x
		else:
			face = 1; raw_u = dir.z / (-dir.x); raw_v = dir.y / (-dir.x)
	elif abs_dir.y >= abs_dir.x and abs_dir.y >= abs_dir.z:
		if dir.y > 0:
			face = 2; raw_u = dir.x / dir.y; raw_v = -dir.z / dir.y
		else:
			face = 3; raw_u = dir.x / (-dir.y); raw_v = dir.z / (-dir.y)
	else:
		if dir.z > 0:
			face = 4; raw_u = dir.x / dir.z; raw_v = dir.y / dir.z
		else:
			face = 5; raw_u = -dir.x / (-dir.z); raw_v = dir.y / (-dir.z)
	var u := (raw_u + 1.0) * 0.5
	var v := (raw_v + 1.0) * 0.5
	return [face, clampf(u, 0.0, 1.0), clampf(v, 0.0, 1.0)]


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

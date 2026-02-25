extends Camera3D
class_name PlanetCamera

enum Mode { ORBIT, FPS }

var mode: Mode = Mode.ORBIT

var orbit_distance: float = 150.0
var orbit_min: float = 55.0
var orbit_max: float = 500.0
var zoom_speed: float = 1.0

var yaw: float = 0.0
var pitch: float = -0.3
var pitch_min: float = -PI * 0.49
var pitch_max: float = PI * 0.49

var rotate_speed: float = 0.005
var pan_speed: float = 0.1

var _target: Vector3 = Vector3.ZERO
var _is_rotating: bool = false
var _is_panning: bool = false

var _fps_grid_pos: Vector2 = Vector2(128.0, 128.0)
var _fps_yaw: float = 0.0
var _fps_pitch: float = 0.0
var _fps_eye_height: float = 1.5
var _fps_move_speed: float = 8.0
var _fps_look_speed: float = 0.003
var _fps_mouse_captured: bool = false
var _fps_tangent_fwd: Vector3 = Vector3.FORWARD
var _fps_tangent_right: Vector3 = Vector3.RIGHT
var _fps_surface_up: Vector3 = Vector3.UP

var projector: PlanetProjector = null
var grid: TorusGrid = null


func _ready() -> void:
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_TAB:
			_toggle_mode()
			return

	if mode == Mode.ORBIT:
		_orbit_input(event)
	else:
		_fps_input(event)


func _process(delta: float) -> void:
	if mode == Mode.ORBIT:
		_orbit_process(delta)
	else:
		_fps_process(delta)


func _toggle_mode() -> void:
	if mode == Mode.ORBIT:
		mode = Mode.FPS
		_fps_mouse_captured = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if projector:
			var grid_pos := projector.sphere_to_grid(_target)
			_fps_grid_pos = Vector2(float(grid_pos.x), float(grid_pos.y))
		_fps_yaw = yaw
		_fps_pitch = 0.0
		_update_fps_transform()
		print("Camera: FPS mode (Tab to return to orbit)")
	else:
		mode = Mode.ORBIT
		_fps_mouse_captured = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_target = Vector3.ZERO
		_update_transform()
		print("Camera: Orbit mode")


func _orbit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				orbit_distance = maxf(orbit_min, orbit_distance - zoom_speed * (orbit_distance * 0.05))
				_update_transform()
			MOUSE_BUTTON_WHEEL_DOWN:
				orbit_distance = minf(orbit_max, orbit_distance + zoom_speed * (orbit_distance * 0.05))
				_update_transform()
			MOUSE_BUTTON_RIGHT:
				_is_rotating = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_is_panning = mb.pressed

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _is_rotating:
			yaw -= mm.relative.x * rotate_speed
			pitch -= mm.relative.y * rotate_speed
			pitch = clampf(pitch, pitch_min, pitch_max)
			_update_transform()
		elif _is_panning:
			var right := global_transform.basis.x
			var up := global_transform.basis.y
			var pan_amount := pan_speed * orbit_distance * 0.001
			_target -= right * mm.relative.x * pan_amount
			_target += up * mm.relative.y * pan_amount
			_update_transform()


func _orbit_process(_delta: float) -> void:
	var kb_pan := Vector3.ZERO
	var pan_amount := pan_speed * orbit_distance * 0.002

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		kb_pan += global_transform.basis.y * pan_amount
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		kb_pan -= global_transform.basis.y * pan_amount
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		kb_pan -= global_transform.basis.x * pan_amount
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		kb_pan += global_transform.basis.x * pan_amount

	if Input.is_key_pressed(KEY_Q):
		yaw += rotate_speed * 2.0
		_update_transform()
	if Input.is_key_pressed(KEY_E):
		yaw -= rotate_speed * 2.0
		_update_transform()

	if kb_pan.length_squared() > 0.0001:
		_target += kb_pan
		_update_transform()


func _fps_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _fps_mouse_captured:
		var mm := event as InputEventMouseMotion
		_fps_yaw -= mm.relative.x * _fps_look_speed
		_fps_pitch -= mm.relative.y * _fps_look_speed
		_fps_pitch = clampf(_fps_pitch, -PI * 0.45, PI * 0.45)
		_update_fps_transform()

	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_ESCAPE:
			_fps_mouse_captured = not _fps_mouse_captured
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _fps_mouse_captured else Input.MOUSE_MODE_VISIBLE


func _fps_process(delta: float) -> void:
	if projector == null or grid == null:
		return

	var input_fwd := 0.0
	var input_right := 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_fwd += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_fwd -= 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_right -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_right += 1.0

	var sprint := 1.0
	if Input.is_key_pressed(KEY_SHIFT):
		sprint = 3.0

	if absf(input_fwd) < 0.01 and absf(input_right) < 0.01:
		return

	var world_move := (_fps_tangent_fwd * input_fwd + _fps_tangent_right * input_right).normalized()
	var move_len := _fps_move_speed * sprint * delta

	var new_world := global_position + world_move * move_len
	var new_grid := projector.sphere_to_grid(new_world)
	var new_gx := float(new_grid.x) + 0.5
	var new_gy := float(new_grid.y) + 0.5

	_fps_grid_pos.x = fmod(new_gx + float(grid.width), float(grid.width))
	_fps_grid_pos.y = clampf(new_gy, 0.0, float(grid.height - 1))

	_update_fps_transform()


func _update_fps_transform() -> void:
	if projector == null or grid == null:
		return

	var gx := _fps_grid_pos.x
	var gy := _fps_grid_pos.y
	var terrain_h := _sample_height_bilinear(gx, gy)
	var surface_pos := projector.grid_to_sphere(gx, gy, terrain_h)
	var surface_up_dir := surface_pos.normalized()
	var world_pos := surface_pos + surface_up_dir * _fps_eye_height
	var surface_up := world_pos.normalized()

	var raw_forward := Vector3(sin(_fps_yaw), 0.0, -cos(_fps_yaw))
	var tangent_forward := (raw_forward - surface_up * raw_forward.dot(surface_up)).normalized()
	var tangent_right := tangent_forward.cross(surface_up).normalized()

	_fps_tangent_fwd = tangent_forward
	_fps_tangent_right = tangent_right
	_fps_surface_up = surface_up

	var pitched_forward := tangent_forward * cos(_fps_pitch) + surface_up * sin(_fps_pitch)
	pitched_forward = pitched_forward.normalized()

	near = 0.02
	global_position = world_pos
	look_at(world_pos + pitched_forward, surface_up)


func _sample_height_bilinear(gx: float, gy: float) -> float:
	if grid == null:
		return 0.0
	var x0 := int(floor(gx)) % grid.width
	var y0 := clampi(int(floor(gy)), 0, grid.height - 1)
	var x1 := (x0 + 1) % grid.width
	var y1 := clampi(y0 + 1, 0, grid.height - 1)
	var fx: float = gx - floor(gx)
	var fy: float = gy - floor(gy)
	var h00 := grid.get_height(x0, y0)
	var h10 := grid.get_height(x1, y0)
	var h01 := grid.get_height(x0, y1)
	var h11 := grid.get_height(x1, y1)
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)


func _update_transform() -> void:
	var offset := Vector3.ZERO
	offset.x = orbit_distance * cos(pitch) * sin(yaw)
	offset.y = orbit_distance * sin(pitch)
	offset.z = orbit_distance * cos(pitch) * cos(yaw)
	global_position = _target + offset
	look_at(_target, Vector3.UP)

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

var _fps_grid_pos: Vector2 = Vector2(64.0, 64.0)
var _fps_yaw: float = 0.0
var _fps_pitch: float = 0.0
var _fps_eye_height: float = 1.5
var _fps_move_speed: float = 15.0
var _fps_look_speed: float = 0.003
var _fps_mouse_captured: bool = false

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

	var move_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move_dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move_dir.x += 1.0

	var sprint := 1.0
	if Input.is_key_pressed(KEY_SHIFT):
		sprint = 3.0

	if move_dir.length_squared() > 0.0:
		move_dir = move_dir.normalized()
		var forward_x := sin(_fps_yaw)
		var forward_y := -cos(_fps_yaw)
		var right_x := cos(_fps_yaw)
		var right_y := sin(_fps_yaw)

		var grid_delta_x := (forward_x * move_dir.y + right_x * move_dir.x) * _fps_move_speed * sprint * delta
		var grid_delta_y := (forward_y * move_dir.y + right_y * move_dir.x) * _fps_move_speed * sprint * delta

		_fps_grid_pos.x = fmod(_fps_grid_pos.x + grid_delta_x + float(grid.width), float(grid.width))
		_fps_grid_pos.y = clampf(_fps_grid_pos.y + grid_delta_y, 0.0, float(grid.height - 1))

		_update_fps_transform()


func _update_fps_transform() -> void:
	if projector == null or grid == null:
		return

	var gx := _fps_grid_pos.x
	var gy := _fps_grid_pos.y
	var terrain_h := grid.get_tile_center_height(
		int(gx) % grid.width,
		clampi(int(gy), 0, grid.height - 1)
	)
	var eye_h := terrain_h + _fps_eye_height / projector.height_scale

	var world_pos := projector.grid_to_sphere(gx, gy, eye_h)
	var surface_up := world_pos.normalized()

	var raw_forward := Vector3(sin(_fps_yaw), 0.0, -cos(_fps_yaw))
	var tangent_forward := (raw_forward - surface_up * raw_forward.dot(surface_up)).normalized()
	var tangent_right := tangent_forward.cross(surface_up).normalized()

	var pitched_forward := tangent_forward * cos(_fps_pitch) + surface_up * sin(_fps_pitch)
	pitched_forward = pitched_forward.normalized()

	global_position = world_pos
	look_at(world_pos + pitched_forward, surface_up)


func _update_transform() -> void:
	var offset := Vector3.ZERO
	offset.x = orbit_distance * cos(pitch) * sin(yaw)
	offset.y = orbit_distance * sin(pitch)
	offset.z = orbit_distance * cos(pitch) * cos(yaw)
	global_position = _target + offset
	look_at(_target, Vector3.UP)

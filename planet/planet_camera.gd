extends Camera3D
class_name PlanetCamera

enum Mode { ORBIT, THIRD_PERSON }

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

var _third_person_yaw: float = 0.0
var _third_person_pitch: float = -0.3
var _third_person_distance: float = 25.0
var _third_person_look_speed: float = 0.003
var _mouse_captured: bool = false

var projector: PlanetProjector = null
var grid: TorusGrid = null
var player_character: Node3D = null # The PlayerCharacter node to follow


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
		_third_person_input(event)


func _process(delta: float) -> void:
	if mode == Mode.ORBIT:
		_orbit_process(delta)
	else:
		_third_person_process(delta)


func _toggle_mode() -> void:
	if mode == Mode.ORBIT:
		mode = Mode.THIRD_PERSON
		_mouse_captured = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
		# If we have a player character, snap the camera to them
		_third_person_yaw = yaw
		_third_person_pitch = -0.2
		_update_third_person_transform()
		print("Camera: 3rd Person mode (Tab to return to orbit)")
	else:
		mode = Mode.ORBIT
		_mouse_captured = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# Snap target back to player character pos to maintain context
		if player_character:
			_target = player_character.global_position
		else:
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


func _third_person_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		var mm := event as InputEventMouseMotion
		_third_person_yaw -= mm.relative.x * _third_person_look_speed
		_third_person_pitch -= mm.relative.y * _third_person_look_speed
		_third_person_pitch = clampf(_third_person_pitch, -PI * 0.45, PI * 0.45)
		_update_third_person_transform()

	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_ESCAPE:
			_mouse_captured = not _mouse_captured
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _mouse_captured else Input.MOUSE_MODE_VISIBLE
			
	if event is InputEventMouseButton and _mouse_captured:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_third_person_distance = maxf(5.0, _third_person_distance - zoom_speed * 5.0)
				_update_third_person_transform()
			MOUSE_BUTTON_WHEEL_DOWN:
				_third_person_distance = minf(100.0, _third_person_distance + zoom_speed * 5.0)
				_update_third_person_transform()


func _third_person_process(_delta: float) -> void:
	if projector == null or grid == null or player_character == null:
		return
		
	if player_character.has_method("set_yaw"):
		player_character.set_yaw(_third_person_yaw)
		
	_update_third_person_transform()


func _update_third_person_transform() -> void:
	if projector == null or grid == null or player_character == null:
		return

	var target_pos: Vector3 = player_character.global_position
	var surface_up := target_pos.normalized()

	var raw_forward := Vector3(sin(_third_person_yaw), 0.0, -cos(_third_person_yaw))
	var tangent_forward := (raw_forward - surface_up * raw_forward.dot(surface_up)).normalized()

	var pitched_forward := tangent_forward * cos(_third_person_pitch) + surface_up * sin(_third_person_pitch)
	pitched_forward = pitched_forward.normalized()
	
	var cam_pos := target_pos - pitched_forward * _third_person_distance

	near = 0.02
	global_position = cam_pos
	look_at(target_pos, surface_up)


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

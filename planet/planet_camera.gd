extends Camera3D
class_name PlanetCamera

var orbit_distance: float = 150.0
var orbit_min: float = 55.0
var orbit_max: float = 500.0
var zoom_speed: float = 10.0

var yaw: float = 0.0
var pitch: float = -0.3
var pitch_min: float = -PI * 0.49
var pitch_max: float = PI * 0.49

var rotate_speed: float = 0.005
var pan_speed: float = 0.1

var _target: Vector3 = Vector3.ZERO
var _is_rotating: bool = false
var _is_panning: bool = false


func _ready() -> void:
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
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


func _process(_delta: float) -> void:
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


func _update_transform() -> void:
	var offset := Vector3.ZERO
	offset.x = orbit_distance * cos(pitch) * sin(yaw)
	offset.y = orbit_distance * sin(pitch)
	offset.z = orbit_distance * cos(pitch) * cos(yaw)
	global_position = _target + offset
	look_at(_target, Vector3.UP)

extends Node3D
class_name PlayerCharacter

var projector: PlanetProjector
var grid: TorusGrid

var grid_pos := Vector2(128.0, 128.0)
var altitude := 0.0 # Height above the terrain
var vertical_velocity := 0.0

var move_speed := 15.0
var sprint_speed := 35.0
var jump_force := 15.0
var gravity := 40.0

var _sprite: Sprite3D
var _yaw: float = 0.0

func _ready() -> void:
	_sprite = Sprite3D.new()
	var tex = load("res://icon.svg")
	if tex:
		_sprite.texture = tex
	_sprite.pixel_size = 0.05
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	add_child(_sprite)


func setup(proj: PlanetProjector, g: TorusGrid, start_gx: float, start_gy: float) -> void:
	projector = proj
	grid = g
	grid_pos = Vector2(start_gx, start_gy)


func _process(delta: float) -> void:
	if projector == null or grid == null:
		return
		
	# Apply gravity and jumping
	vertical_velocity -= gravity * delta
	altitude += vertical_velocity * delta
	
	if altitude <= 0.0:
		altitude = 0.0
		vertical_velocity = 0.0
		if Input.is_action_just_pressed("ui_accept"): # Spacebar usually
			vertical_velocity = jump_force

	# Movement
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

	var speed := sprint_speed if Input.is_key_pressed(KEY_SHIFT) else move_speed
	
	if absf(input_fwd) > 0.01 or absf(input_right) > 0.01:
		var surface_pos := projector.grid_to_sphere(grid_pos.x, grid_pos.y, 0.0)
		var surface_up := surface_pos.normalized()
		
		# Compute camera-relative forward and right vectors projected onto the planet's tangent plane
		var raw_forward := Vector3(sin(_yaw), 0.0, -cos(_yaw))
		var tangent_forward := (raw_forward - surface_up * raw_forward.dot(surface_up)).normalized()
		var tangent_right := tangent_forward.cross(surface_up).normalized()
		
		var move_dir := (tangent_forward * input_fwd + tangent_right * input_right).normalized()
		var move_dist := speed * delta
		var target_pos := surface_pos + move_dir * move_dist
		
		var new_frac := _world_to_grid_frac(target_pos)
		grid_pos = new_frac
		
	_update_transform()


func set_yaw(y: float) -> void:
	_yaw = y


func _world_to_grid_frac(world_pos: Vector3) -> Vector2:
	var r := world_pos.length()
	if r < 0.001:
		return Vector2.ZERO
	var lat := asin(clampf(world_pos.y / r, -1.0, 1.0))
	var lon := atan2(world_pos.z, world_pos.x)
	if lon < 0.0:
		lon += TAU
	var gx := (lon / TAU) * float(grid.width)
	var gy := ((lat + PI * 0.5) / PI) * float(grid.height)
	return Vector2(gx, gy)


func _update_transform() -> void:
	var terrain_h := _sample_height_bilinear(grid_pos.x, grid_pos.y)
	# Surface position is terrain height + local altitude
	var surface_pos := projector.grid_to_sphere(grid_pos.x, grid_pos.y, terrain_h)
	var up_dir := surface_pos.normalized()
	
	# Offset by altitude
	var world_pos := surface_pos + up_dir * altitude
	
	global_position = world_pos
	
	# Align sprite upright relative to the planet
	var tangent_right := Vector3.FORWARD.cross(up_dir).normalized()
	if tangent_right.length_squared() < 0.01:
		tangent_right = Vector3.RIGHT.cross(up_dir).normalized()
	var tangent_fwd := up_dir.cross(tangent_right).normalized()
	
	global_transform.basis = Basis(tangent_right, up_dir, tangent_fwd)


func _sample_height_bilinear(gx: float, gy: float) -> float:
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

extends Node3D
class_name PlanetFaunaRenderer

var _projector: PlanetProjector = null
var _grid: TorusGrid = null
var _ecs: EcsWorld = null

var _multimeshes: Dictionary = {}
var _mesh_cache: Dictionary = {}
var _texture_cache: Dictionary = {}

var _rebuild_timer: float = 0.0
var _lerp_timer: float = 0.0
const REBUILD_INTERVAL := 1.0
const LERP_INTERVAL := 0.1
const MAX_INSTANCES_PER_TYPE := 512
const LERP_SPEED := 1.0

var _is_rebuilding: bool = false

const SPECIES_COLORS: Dictionary = {
	"deer": Color(0.6, 0.4, 0.2),
	"wolf": Color(0.5, 0.5, 0.5),
	"rabbit": Color(0.85, 0.85, 0.8),
	"bear": Color(0.35, 0.2, 0.1),
	"eagle": Color(0.8, 0.7, 0.3),
	"fish": Color(0.5, 0.55, 0.7),
	"bison": Color(0.4, 0.3, 0.15),
	"shark": Color(0.45, 0.48, 0.52),
	"whale": Color(0.3, 0.35, 0.45),
	"jellyfish": Color(0.7, 0.5, 0.85),
	"crab": Color(0.75, 0.35, 0.2),
	"sea_turtle": Color(0.3, 0.5, 0.25),
}

const SPRITE_SIZE: Dictionary = {
	"deer": 1.2,
	"wolf": 1.0,
	"rabbit": 0.6,
	"bear": 1.5,
	"eagle": 0.8,
	"fish": 0.5,
	"bison": 1.4,
	"shark": 1.6,
	"whale": 2.5,
	"jellyfish": 0.5,
	"crab": 0.4,
	"sea_turtle": 1.0,
}

const SPECIES_LETTER: Dictionary = {
	"deer": "D",
	"wolf": "W",
	"rabbit": "R",
	"bear": "B",
	"eagle": "E",
	"fish": "F",
	"bison": "N",
	"shark": "S",
	"whale": "H",
	"jellyfish": "J",
	"crab": "C",
	"sea_turtle": "T",
}


func setup(proj: PlanetProjector, grid: TorusGrid, ecs: EcsWorld) -> void:
	_projector = proj
	_grid = grid
	_ecs = ecs


func _process(delta: float) -> void:
	_lerp_timer += delta
	if _lerp_timer >= LERP_INTERVAL:
		_advance_lerp(_lerp_timer)
		_lerp_timer = 0.0
		
	if _is_rebuilding:
		return
		
	_rebuild_timer += delta
	if _rebuild_timer < REBUILD_INTERVAL:
		return
	_rebuild_timer = 0.0
	_rebuild_all_async()


func _advance_lerp(delta: float) -> void:
	if _ecs == null:
		return
	var fauna := _ecs.get_components("ComFaunaSpecies")
	var positions := _ecs.get_components("ComPosition")
	for eid in fauna.keys():
		if not positions.has(eid):
			continue
		var pos: ComPosition = positions[eid]
		if pos.lerp_t < 1.0:
			pos.lerp_t = minf(pos.lerp_t + delta / LERP_SPEED, 1.0)


func _rebuild_all_async() -> void:
	if _ecs == null or _projector == null:
		return

	_is_rebuilding = true
	var by_species: Dictionary = {}

	var fauna_comps := _ecs.get_components("ComFaunaSpecies")
	var positions := _ecs.get_components("ComPosition")
	var ai_states := _ecs.get_components("ComAiState")

	var keys := fauna_comps.keys()
	var start_time := Time.get_ticks_msec()

	for eid in keys:
		if Time.get_ticks_msec() - start_time > 4:
			await get_tree().process_frame
			start_time = Time.get_ticks_msec()
			if _ecs == null:
				_is_rebuilding = false
				return

		if not positions.has(eid):
			continue
		var species: ComFaunaSpecies = fauna_comps[eid]
		var pos: ComPosition = positions[eid]
		var ai: ComAiState = ai_states.get(eid) as ComAiState
		var herd: ComHerd = _ecs.get_component(eid, "ComHerd") as ComHerd
		
		var key := species.species_key
		if not by_species.has(key):
			by_species[key] = []

		by_species[key].append({
			"pos": pos,
			"species": species,
			"ai": ai,
			"herd": herd,
			"eid": eid
		})

	# Render all species found + hide any that vanished
	var all_keys := {}
	for key in by_species:
		all_keys[key] = true
	for key in _multimeshes:
		all_keys[key] = true

	for key in all_keys:
		if Time.get_ticks_msec() - start_time > 4:
			await get_tree().process_frame
			start_time = Time.get_ticks_msec()
			if _ecs == null:
				_is_rebuilding = false
				return
				
		if not by_species.has(key):
			_set_instance_count(key, 0)
			continue
		var instances: Array = by_species[key]
		
		# Calculate total instances required for this species (summing herd counts)
		var total_instances := 0
		for data in instances:
			var h: ComHerd = data.get("herd")
			if h:
				total_instances += h.count
			else:
				total_instances += 1
				
		var count := mini(total_instances, MAX_INSTANCES_PER_TYPE)
		var mm := _get_or_create_multimesh(key, count)
		_update_instances(mm, instances, key, count)

	_is_rebuilding = false


func _get_or_create_multimesh(species_key: String, count: int) -> MultiMesh:
	if not _multimeshes.has(species_key):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _get_mesh(species_key)
		mm.instance_count = count

		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "Fauna_" + species_key

		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.no_depth_test = false
		mat.albedo_texture = _get_letter_texture(species_key)
		mmi.material_override = mat

		add_child(mmi)
		_multimeshes[species_key] = mm
	else:
		_multimeshes[species_key].instance_count = count
	return _multimeshes[species_key]


func _set_instance_count(species_key: String, count: int) -> void:
	if _multimeshes.has(species_key):
		_multimeshes[species_key].instance_count = count


func _get_mesh(species_key: String) -> Mesh:
	if _mesh_cache.has(species_key):
		return _mesh_cache[species_key]
	var sz: float = SPRITE_SIZE.get(species_key, 1.0) * (GameConfig.PLANET_RADIUS / 100.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(sz, sz)
	_mesh_cache[species_key] = quad
	return quad


func _get_letter_texture(species_key: String) -> Texture2D:
	if _texture_cache.has(species_key):
		return _texture_cache[species_key]

	var tex_size := 64
	var letter: String = SPECIES_LETTER.get(species_key, "?")
	var bg_color: Color = SPECIES_COLORS.get(species_key, Color.WHITE)

	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	var center := float(tex_size) / 2.0
	var radius := float(tex_size) / 2.0 - 2.0
	for py in range(tex_size):
		for px in range(tex_size):
			var dx := float(px) - center
			var dy := float(py) - center
			var dist := sqrt(dx * dx + dy * dy)
			if dist < radius:
				var edge := clampf(1.0 - (dist - (radius - 2.0)) / 2.0, 0.0, 1.0)
				img.set_pixel(px, py, Color(bg_color.r, bg_color.g, bg_color.b, edge))
			else:
				img.set_pixel(px, py, Color(0, 0, 0, 0))

	_draw_letter_on_image(img, letter, tex_size)

	var tex := ImageTexture.create_from_image(img)
	_texture_cache[species_key] = tex
	return tex


func _draw_letter_on_image(img: Image, letter: String, tex_size: int) -> void:
	var patterns := _get_letter_pattern(letter)
	var grid_size := 5
	var cell := float(tex_size) / float(grid_size + 2)
	var ox := (float(tex_size) - float(grid_size) * cell) / 2.0
	var oy := (float(tex_size) - float(grid_size) * cell) / 2.0

	for row in range(patterns.size()):
		var line: String = patterns[row]
		for col in range(line.length()):
			if line[col] == "#":
				var cx := int(ox + col * cell)
				var cy := int(oy + row * cell)
				for py in range(cy, cy + int(cell)):
					for px in range(cx, cx + int(cell)):
						img.set_pixel(px, py, Color.WHITE)


func _get_letter_pattern(letter: String) -> Array[String]:
	match letter:
		"D":
			return ["###  ", "#  # ", "#  # ", "#  # ", "###  "]
		"W":
			return ["#   #", "#   #", "# # #", "## ##", "#   #"]
		"R":
			return ["#### ", "#   #", "#### ", "#  # ", "#   #"]
		"B":
			return ["#### ", "#   #", "#### ", "#   #", "#### "]
		"E":
			return ["#### ", "#    ", "###  ", "#    ", "#### "]
		"F":
			return ["#### ", "#    ", "###  ", "#    ", "#    "]
		"S":
			return [" ####", "#    ", " ### ", "    #", "#### "]
		_:
			return ["#####", "#   #", "#   #", "#   #", "#####"]


func _update_instances(mm: MultiMesh, instances: Array, species_key: String, count: int) -> void:
	var base_color: Color = SPECIES_COLORS.get(species_key, Color.WHITE)
	
	var instance_idx := 0
	for data in instances:
		if instance_idx >= count:
			break
			
		var pos: ComPosition = data["pos"]
		var species: ComFaunaSpecies = data["species"]
		var ai: ComAiState = data["ai"]
		var herd: ComHerd = data["herd"]
		var eid: int = data["eid"]
		
		var animals_to_spawn := 1
		var radius := 0.0
		if herd:
			animals_to_spawn = herd.count
			radius = herd.radius
			
		# Determine base color modifiers from AI state
		var col := base_color
		if ai != null:
			match ai.current_state:
				DefEnums.AIState.HUNTING:
					col = base_color.lerp(Color.RED, 0.3)
				DefEnums.AIState.FLEEING:
					col = base_color.lerp(Color.YELLOW, 0.4)
				DefEnums.AIState.SLEEPING:
					col = base_color.darkened(0.4)
				DefEnums.AIState.MATING:
					col = base_color.lerp(Color.MAGENTA, 0.3)

		for j in range(animals_to_spawn):
			if instance_idx >= count:
				break
				
			# Jitter position around herd center based on entity ID and animal index
			var wp := _get_interpolated_pos(pos, species)
			
			if animals_to_spawn > 1:
				var hash_val := _jitter_hash(eid, j, 2)
				var angle := hash_val * TAU
				var r := sqrt(_jitter_hash(eid, j, 3)) * radius
				
				# Get local tangent vectors to distribute around the point
				var up := wp.normalized()
				var right := up.cross(Vector3.FORWARD)
				if right.length_squared() < 0.001:
					right = up.cross(Vector3.RIGHT)
				right = right.normalized()
				var fwd := up.cross(right).normalized()
				
				# We want the radius in world space relative to planet size
				var planet_scale := GameConfig.PLANET_RADIUS / 100.0
				wp += (right * cos(angle) + fwd * sin(angle)) * (r * planet_scale)
				
			var up := wp.normalized()
			var sz: float = SPRITE_SIZE.get(species_key, 1.0)
			
			# Slight size variation per animal
			var size_var := 1.0 + (_jitter_hash(eid, j, 4) - 0.5) * 0.2
			
			var t := Transform3D()
			t.origin = wp + up * sz * 0.6 * size_var
			
			# Slight color variation per animal
			var final_col := col
			var h_shift := (_jitter_hash(eid, j, 5) - 0.5) * 0.05
			var v_shift := (_jitter_hash(eid, j, 6) - 0.5) * 0.1
			final_col = Color.from_hsv(
				wrapf(final_col.h + h_shift, 0.0, 1.0),
				final_col.s,
				clampf(final_col.v + v_shift, 0.0, 1.0),
				final_col.a
			)

			mm.set_instance_transform(instance_idx, t)
			mm.set_instance_color(instance_idx, final_col)
			instance_idx += 1

func _jitter_hash(eid: int, idx: int, channel: int) -> float:
	var n := eid * 374761393 + idx * 668265263 + channel * 1274126177
	n = (n ^ (n >> 13)) * 1103515245
	return float(n & 0xFFFF) / 65535.0

func _get_interpolated_pos(pos: ComPosition, species: ComFaunaSpecies) -> Vector3:
	if _projector == null or _grid == null:
		return Vector3.ZERO
	var target := _get_surface_pos(pos, species)
	if pos.prev_world_pos.length_squared() < 0.01 or pos.lerp_t >= 1.0:
		return target
	var t := smoothstep(0.0, 1.0, pos.lerp_t)
	var prev_dir := pos.prev_world_pos.normalized()
	var target_dir := target.normalized()
	var dir := prev_dir.slerp(target_dir, t)
	var r := lerpf(pos.prev_world_pos.length(), target.length(), t)
	return dir * r


func _get_surface_pos(pos: ComPosition, species: ComFaunaSpecies) -> Vector3:
	if _projector == null or _grid == null:
		return Vector3.ZERO
	var fx := float(pos.grid_x) + 0.5
	var fy := float(pos.grid_y) + 0.5
	var h := _grid.get_height(pos.grid_x, pos.grid_y)
	if species.is_aquatic:
		h = minf(h, GameConfig.SEA_LEVEL)
	var dir := _projector.grid_to_sphere(fx, fy).normalized()
	return dir * (_projector.radius + h * _projector.height_scale)

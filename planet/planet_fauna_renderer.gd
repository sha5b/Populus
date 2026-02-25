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

const SPECIES_COLORS: Dictionary = {
	"deer": Color(0.6, 0.4, 0.2),
	"wolf": Color(0.5, 0.5, 0.5),
	"rabbit": Color(0.85, 0.85, 0.8),
	"bear": Color(0.35, 0.2, 0.1),
	"eagle": Color(0.8, 0.7, 0.3),
	"fish": Color(0.3, 0.5, 0.8),
	"bison": Color(0.4, 0.3, 0.15),
}

const SPRITE_SIZE: Dictionary = {
	"deer": 1.2,
	"wolf": 1.0,
	"rabbit": 0.6,
	"bear": 1.5,
	"eagle": 0.8,
	"fish": 0.5,
	"bison": 1.4,
}

const SPECIES_LETTER: Dictionary = {
	"deer": "D",
	"wolf": "W",
	"rabbit": "R",
	"bear": "B",
	"eagle": "E",
	"fish": "F",
	"bison": "N",
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
	_rebuild_timer += delta
	if _rebuild_timer < REBUILD_INTERVAL:
		return
	_rebuild_timer = 0.0
	_rebuild_all()


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


func _rebuild_all() -> void:
	if _ecs == null or _projector == null:
		return

	var by_species: Dictionary = {}

	var fauna_comps := _ecs.get_components("ComFaunaSpecies")
	var positions := _ecs.get_components("ComPosition")
	var ai_states := _ecs.get_components("ComAiState")

	for eid in fauna_comps.keys():
		if not positions.has(eid):
			continue
		var species: ComFaunaSpecies = fauna_comps[eid]
		var pos: ComPosition = positions[eid]
		var ai: ComAiState = ai_states.get(eid) as ComAiState

		var key := species.species_key
		if not by_species.has(key):
			by_species[key] = []

		by_species[key].append({
			"pos": pos,
			"species": species,
			"ai": ai,
		})

	for key in SPECIES_COLORS:
		if not by_species.has(key):
			_set_instance_count(key, 0)
			continue
		var instances: Array = by_species[key]
		var count := mini(instances.size(), MAX_INSTANCES_PER_TYPE)
		var mm := _get_or_create_multimesh(key, count)
		_update_instances(mm, instances, key, count)


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
	var sz: float = SPRITE_SIZE.get(species_key, 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(sz, sz)
	_mesh_cache[species_key] = quad
	return quad


func _get_letter_texture(species_key: String) -> ImageTexture:
	if _texture_cache.has(species_key):
		return _texture_cache[species_key]
	var letter: String = SPECIES_LETTER.get(species_key, "?")
	var bg_color: Color = SPECIES_COLORS.get(species_key, Color.WHITE)
	var tex_size := 64
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := tex_size / 2
	var radius := tex_size / 2 - 2
	for py in range(tex_size):
		for px in range(tex_size):
			var dx := px - center
			var dy := py - center
			var dist := sqrt(float(dx * dx + dy * dy))
			if dist < radius:
				var edge := clampf(1.0 - (dist - float(radius - 2)) / 2.0, 0.0, 1.0)
				img.set_pixel(px, py, Color(bg_color.r, bg_color.g, bg_color.b, 0.85 * edge))
	_draw_letter_on_image(img, letter, tex_size)
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[species_key] = tex
	return tex


func _draw_letter_on_image(img: Image, letter: String, tex_size: int) -> void:
	var patterns := _get_letter_pattern(letter)
	var grid_size := 5
	var cell := tex_size / (grid_size + 2)
	var ox := (tex_size - grid_size * cell) / 2
	var oy := (tex_size - grid_size * cell) / 2
	for row in range(patterns.size()):
		var line: String = patterns[row]
		for col in range(line.length()):
			if line[col] == "#":
				for py in range(cell):
					for px in range(cell):
						var ix := ox + col * cell + px
						var iy := oy + row * cell + py
						if ix >= 0 and ix < tex_size and iy >= 0 and iy < tex_size:
							img.set_pixel(ix, iy, Color.WHITE)


func _get_letter_pattern(letter: String) -> Array[String]:
	match letter:
		"D": return ["###.", "#..#", "#..#", "#..#", "###."]
		"W": return ["#..#", "#..#", "#.##", "##.#", "#..#"]
		"R": return ["###.", "#..#", "###.", "#.#.", "#..#"]
		"B": return ["###.", "#..#", "###.", "#..#", "###."]
		"E": return ["####", "#...", "###.", "#...", "####"]
		"F": return ["####", "#...", "###.", "#...", "#..."]
		"N": return ["#..#", "##.#", "#.##", "#..#", "#..#"]
		_: return ["####", "#..#", "#..#", "#..#", "####"]


func _update_instances(mm: MultiMesh, instances: Array, species_key: String, count: int) -> void:
	var base_color: Color = SPECIES_COLORS.get(species_key, Color.WHITE)

	for i in range(count):
		var data: Dictionary = instances[i]
		var pos: ComPosition = data["pos"]
		var species: ComFaunaSpecies = data["species"]
		var ai: ComAiState = data["ai"]

		var wp := _get_interpolated_pos(pos, species)
		var up := wp.normalized()
		var sz: float = SPRITE_SIZE.get(species_key, 1.0)
		var t := Transform3D()
		t.origin = wp + up * sz * 0.6

		mm.set_instance_transform(i, t)

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
		mm.set_instance_color(i, col)


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

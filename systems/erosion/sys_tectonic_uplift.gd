extends System
class_name SysTectonicUplift

var grid: TorusGrid = null
var heightmap_gen: GenHeightmap = null
var projector: PlanetProjector = null

var _timer: float = 0.0
var _chunk_offset: int = 0

const TICK_INTERVAL := 3.0
const CHUNK_SIZE := 4096
const UPLIFT_RATE := 0.0004
const SUBSIDENCE_RATE := 0.0001
const ISOSTATIC_RATE := 0.0002
const SEA_FLOOR_SPREAD_RATE := 0.00005


func setup(g: TorusGrid, hgen: GenHeightmap, proj: PlanetProjector) -> void:
	grid = g
	heightmap_gen = hgen
	projector = proj


func update(_world: Node, delta: float) -> void:
	if grid == null or heightmap_gen == null:
		return
	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	_timer -= TICK_INTERVAL
	
	heightmap_gen.tick_tectonics(TICK_INTERVAL)
	_uplift_chunk()


func _uplift_chunk() -> void:
	var w := grid.width
	var h := grid.height
	var total := w * h
	var end_idx := mini(_chunk_offset + CHUNK_SIZE, total)

	for i in range(_chunk_offset, end_idx):
		var x := i % w
		var y := int(float(i) / float(w))
		var current_h := grid.get_bedrock(x, y)

		var dir: Vector3
		if projector:
			dir = projector.grid_to_sphere(float(x), float(y)).normalized()
		else:
			var lon := float(x) / float(w) * TAU
			var lat := float(y) / float(h) * PI - PI * 0.5
			dir = Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))

		# The current tile's plate determines its movement vector
		var plate_id := grid.crust_plate[i]
		var plate_axis := heightmap_gen._plate_axes[plate_id]
		var plate_speed := heightmap_gen._plate_speeds[plate_id] * TICK_INTERVAL * 0.1 # Slow down for mesh updates
		
		# Calculate the velocity vector for this tile on the sphere
		var velocity := dir.cross(plate_axis).normalized() * plate_speed
		if velocity.length_squared() > 0.0001:
			var target_dir := (dir + velocity).normalized()
			# Determine what's at the target location (collision check)
			var target_plate_info := heightmap_gen._get_plate_info(target_dir)
			var target_plate_id: int = target_plate_info[3]
			
			if target_plate_id != plate_id:
				# Collision with another plate!
				var target_is_cont: bool = heightmap_gen._plate_is_continental[target_plate_id]
				var self_is_cont: bool = heightmap_gen._plate_is_continental[plate_id]
				
				# Subduction: oceanic plates dive under continental plates
				if self_is_cont and not target_is_cont:
					# We are riding over them, push us up
					current_h += UPLIFT_RATE * 5.0
				elif not self_is_cont and target_is_cont:
					# We are diving under them, pull us down
					current_h -= SUBSIDENCE_RATE * 5.0
				else:
					# Mountain building (cont vs cont or ocean vs ocean)
					current_h += UPLIFT_RATE * 3.0
		
		# Also get standard boundary info for general uplift/spreading
		var plate_info := heightmap_gen._get_plate_info(dir)
		var boundary_factor: float = plate_info[0]
		var is_convergent: bool = plate_info[1]
		var is_continental: bool = plate_info[2]

		var uplift := 0.0

		# Convergent plate boundaries push terrain up (mountain building)
		if boundary_factor > 0.0 and is_convergent:
			uplift += boundary_factor * UPLIFT_RATE * (1.0 + current_h * 0.5)

		# Continental interiors get mild uplift (isostatic rebound)
		if is_continental and current_h > GameConfig.SEA_LEVEL:
			uplift += ISOSTATIC_RATE * clampf(0.3 - current_h, 0.0, 0.3)

		# Divergent boundaries: sea floor spreading pushes up slightly
		if boundary_factor > 0.0 and not is_convergent:
			if current_h < GameConfig.SEA_LEVEL:
				uplift += SEA_FLOOR_SPREAD_RATE * boundary_factor

		# Very high terrain slowly subsides under its own weight
		if current_h > 0.6:
			uplift -= SUBSIDENCE_RATE * (current_h - 0.6)

		# Ocean floor far from boundaries slowly subsides
		if current_h < -0.1 and boundary_factor < 0.1:
			uplift -= SUBSIDENCE_RATE * 0.5

		grid.set_bedrock(x, y, current_h + uplift)
		
		# Periodically update the crust_plate array to reflect the moving plates
		if randf() < 0.05:
			grid.crust_plate[i] = heightmap_gen.get_plate_id(dir)

	grid.is_dirty = true
	_chunk_offset = end_idx if end_idx < total else 0

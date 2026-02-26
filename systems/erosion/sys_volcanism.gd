extends System
class_name SysVolcanism

var grid: TorusGrid = null
var heightmap_gen: GenHeightmap = null
var projector: PlanetProjector = null
var temperature_map: PackedFloat32Array

var magma_pressure: PackedFloat32Array
var _pressure_next: PackedFloat32Array

var _timer: float = 0.0
var _chunk_offset: int = 0
var _rng: RandomNumberGenerator
var _hotspots: Array[Vector3] = []


func setup(g: TorusGrid, hgen: GenHeightmap, proj: PlanetProjector, temp: PackedFloat32Array) -> void:
	grid = g
	heightmap_gen = hgen
	projector = proj
	temperature_map = temp

	_rng = RandomNumberGenerator.new()
	_rng.seed = int(GameConfig.WORLD_SEED) + 990133

	var total := g.width * g.height
	magma_pressure = PackedFloat32Array()
	magma_pressure.resize(total)
	magma_pressure.fill(0.0)
	_pressure_next = PackedFloat32Array()
	_pressure_next.resize(total)
	_pressure_next.fill(0.0)

	_hotspots.clear()
	var count := maxi(GameConfig.VOLC_HOTSPOT_COUNT, 0)
	for _i in range(count):
		_hotspots.append(_random_unit_vector())


func update(_world: Node, delta: float) -> void:
	if grid == null or heightmap_gen == null:
		return

	_timer += delta
	if _timer < GameConfig.VOLC_TICK_INTERVAL:
		return
	_timer -= GameConfig.VOLC_TICK_INTERVAL

	_process_chunk()


func _process_chunk() -> void:
	var w := grid.width
	var h := grid.height
	var total := w * h
	var start_idx := _chunk_offset
	var end_idx := mini(_chunk_offset + GameConfig.VOLC_CHUNK_SIZE, total)

	for i in range(_chunk_offset, end_idx):
		var x := i % w
		var y := int(float(i) / float(w))

		var dir := _tile_dir(x, y)
		var plate_info := heightmap_gen._get_plate_info(dir)
		var boundary_factor: float = plate_info[0]
		var is_convergent: bool = plate_info[1]

		var p := magma_pressure[i]
		p *= GameConfig.VOLC_PRESSURE_DECAY

		if boundary_factor > 0.0:
			if is_convergent:
				p += boundary_factor * GameConfig.VOLC_INJECT_CONVERGENT
			else:
				p += boundary_factor * GameConfig.VOLC_INJECT_DIVERGENT

		p += _hotspot_injection(dir)
		p = clampf(p, 0.0, 1.0)

		var avg_n := _neighbor_avg_pressure(x, y, w)
		
		# Laplacian diffusion to conserve mass
		var laplacian := avg_n - p
		var diffused := p + laplacian * GameConfig.VOLC_DIFFUSION
		
		_pressure_next[i] = clampf(diffused, 0.0, 1.0)

	_chunk_offset = end_idx if end_idx < total else 0

	for i in range(start_idx, end_idx):
		magma_pressure[i] = _pressure_next[i]

	_process_eruptions(start_idx, end_idx, w)


func _process_eruptions(start_idx: int, end_idx: int, w: int) -> void:
	for i in range(start_idx, end_idx):
		var p := magma_pressure[i]
		if p < GameConfig.VOLC_ERUPT_THRESHOLD:
			continue
		if _rng.randf() > GameConfig.VOLC_ERUPT_CHANCE:
			continue

		var x := i % w
		var y := int(float(i) / float(w))
		_apply_eruption(x, y, p)

		magma_pressure[i] = p * 0.35


func _apply_eruption(cx: int, cy: int, strength: float) -> void:
	var w := grid.width
	var r := int(ceil(GameConfig.VOLC_ERUPT_RADIUS))

	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var dist := sqrt(float(dx * dx + dy * dy))
			if dist > GameConfig.VOLC_ERUPT_RADIUS:
				continue
			var falloff := 1.0 - dist / GameConfig.VOLC_ERUPT_RADIUS
			var x := grid.wrap_x(cx + dx)
			var y := grid.wrap_y(cy + dy)
			var idx := y * w + x

			var uplift := GameConfig.VOLC_ERUPT_UPLIFT * (0.35 + strength) * falloff
			var current_h := grid.get_height(x, y)
			var new_h := minf(current_h + uplift, GameConfig.VOLC_MAX_TERRAIN_H)
			grid.set_height(x, y, new_h)

			if idx >= 0 and idx < temperature_map.size():
				temperature_map[idx] = clampf(temperature_map[idx] + GameConfig.VOLC_TEMP_BOOST * falloff, 0.0, 1.0)


func _hotspot_injection(dir: Vector3) -> float:
	if _hotspots.is_empty():
		return 0.0
	var inject := 0.0
	for hs in _hotspots:
		var d := dir.dot(hs)
		if d > GameConfig.VOLC_HOTSPOT_RADIUS_DOT:
			var t := (d - GameConfig.VOLC_HOTSPOT_RADIUS_DOT) / (1.0 - GameConfig.VOLC_HOTSPOT_RADIUS_DOT)
			inject += GameConfig.VOLC_HOTSPOT_INJECT * t
	return inject


func _neighbor_avg_pressure(x: int, y: int, w: int) -> float:
	var idx_l := y * w + grid.wrap_x(x - 1)
	var idx_r := y * w + grid.wrap_x(x + 1)
	var idx_u := grid.wrap_y(y - 1) * w + x
	var idx_d := grid.wrap_y(y + 1) * w + x
	return (magma_pressure[idx_l] + magma_pressure[idx_r] + magma_pressure[idx_u] + magma_pressure[idx_d]) * 0.25


func _tile_dir(x: int, y: int) -> Vector3:
	if projector:
		return projector.grid_to_sphere(float(x), float(y)).normalized()
	var lon := float(x) / float(grid.width) * TAU
	var lat := float(y) / float(grid.height) * PI - PI * 0.5
	return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)).normalized()


func _random_unit_vector() -> Vector3:
	var theta := _rng.randf() * TAU
	var z := _rng.randf_range(-1.0, 1.0)
	var r := sqrt(maxf(1.0 - z * z, 0.0))
	return Vector3(r * cos(theta), z, r * sin(theta)).normalized()

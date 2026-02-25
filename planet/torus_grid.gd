class_name TorusGrid

var width: int
var height: int
var heights: PackedFloat32Array


func _init(w: int = 128, h: int = 128) -> void:
	width = w
	height = h
	heights = PackedFloat32Array()
	heights.resize(width * height)
	heights.fill(0.0)


func wrap_x(x: int) -> int:
	return ((x % width) + width) % width


func wrap_y(y: int) -> int:
	return ((y % height) + height) % height


func _index(x: int, y: int) -> int:
	return wrap_y(y) * width + wrap_x(x)


func get_height(x: int, y: int) -> float:
	return heights[_index(x, y)]


func set_height(x: int, y: int, h: float) -> void:
	heights[_index(x, y)] = h


func get_tile_center_height(tx: int, ty: int) -> float:
	var h0 := get_height(tx, ty)
	var h1 := get_height(tx + 1, ty)
	var h2 := get_height(tx, ty + 1)
	var h3 := get_height(tx + 1, ty + 1)
	return (h0 + h1 + h2 + h3) * 0.25


func is_flat(tx: int, ty: int, tolerance: float = 0.1) -> bool:
	var h0 := get_height(tx, ty)
	var h1 := get_height(tx + 1, ty)
	var h2 := get_height(tx, ty + 1)
	var h3 := get_height(tx + 1, ty + 1)
	var min_h := minf(minf(h0, h1), minf(h2, h3))
	var max_h := maxf(maxf(h0, h1), maxf(h2, h3))
	return (max_h - min_h) < tolerance


func is_underwater(tx: int, ty: int) -> bool:
	return get_tile_center_height(tx, ty) < GameConfig.SEA_LEVEL


func get_neighbors_4(tx: int, ty: int) -> Array[Vector2i]:
	return [
		Vector2i(wrap_x(tx), wrap_y(ty - 1)),
		Vector2i(wrap_x(tx), wrap_y(ty + 1)),
		Vector2i(wrap_x(tx - 1), wrap_y(ty)),
		Vector2i(wrap_x(tx + 1), wrap_y(ty)),
	]


func get_neighbors_8(tx: int, ty: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			result.append(Vector2i(wrap_x(tx + dx), wrap_y(ty + dy)))
	return result


func torus_distance(a: Vector2i, b: Vector2i) -> float:
	var dx := absf(float(a.x - b.x))
	var dy := absf(float(a.y - b.y))
	dx = minf(dx, float(width) - dx)
	dy = minf(dy, float(height) - dy)
	return sqrt(dx * dx + dy * dy)


func fill_circle(cx: int, cy: int, radius: float, height_delta: float) -> void:
	var r_int := int(ceil(radius))
	for dy in range(-r_int, r_int + 1):
		for dx in range(-r_int, r_int + 1):
			var dist := sqrt(float(dx * dx + dy * dy))
			if dist <= radius:
				var wx := wrap_x(cx + dx)
				var wy := wrap_y(cy + dy)
				var falloff := 1.0 - (dist / radius)
				set_height(wx, wy, get_height(wx, wy) + height_delta * falloff)


func flatten_area(cx: int, cy: int, radius: float) -> void:
	var r_int := int(ceil(radius))
	var total := 0.0
	var count := 0
	for dy in range(-r_int, r_int + 1):
		for dx in range(-r_int, r_int + 1):
			if sqrt(float(dx * dx + dy * dy)) <= radius:
				total += get_height(wrap_x(cx + dx), wrap_y(cy + dy))
				count += 1
	if count == 0:
		return
	var avg := total / float(count)
	for dy in range(-r_int, r_int + 1):
		for dx in range(-r_int, r_int + 1):
			if sqrt(float(dx * dx + dy * dy)) <= radius:
				set_height(wrap_x(cx + dx), wrap_y(cy + dy), avg)

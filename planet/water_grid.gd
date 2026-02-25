class_name WaterGrid

var width: int
var height: int

var water_depth: PackedFloat32Array
var flow_vx: PackedFloat32Array
var flow_vy: PackedFloat32Array
var water_temp: PackedFloat32Array
var wave_height: PackedFloat32Array
var surface_height: PackedFloat32Array


func initialize(w: int, h: int, terrain_grid: TorusGrid, temperature_map: PackedFloat32Array) -> void:
	width = w
	height = h
	var total := w * h

	water_depth = PackedFloat32Array()
	water_depth.resize(total)
	flow_vx = PackedFloat32Array()
	flow_vx.resize(total)
	flow_vy = PackedFloat32Array()
	flow_vy.resize(total)
	water_temp = PackedFloat32Array()
	water_temp.resize(total)
	wave_height = PackedFloat32Array()
	wave_height.resize(total)
	surface_height = PackedFloat32Array()
	surface_height.resize(total)

	for i in range(total):
		var x := i % w
		var y := int(i / w)
		var terrain_h := terrain_grid.get_height(x, y)

		if terrain_h < GameConfig.SEA_LEVEL:
			water_depth[i] = GameConfig.SEA_LEVEL - terrain_h
		else:
			water_depth[i] = 0.0

		flow_vx[i] = 0.0
		flow_vy[i] = 0.0
		wave_height[i] = 0.0
		surface_height[i] = maxf(terrain_h, GameConfig.SEA_LEVEL)

		if i < temperature_map.size():
			water_temp[i] = temperature_map[i]
		else:
			water_temp[i] = 0.5


func get_index(x: int, y: int) -> int:
	return (y % height + height) % height * width + (x % width + width) % width


func get_depth(x: int, y: int) -> float:
	return water_depth[get_index(x, y)]


func get_flow(x: int, y: int) -> Vector2:
	var idx := get_index(x, y)
	return Vector2(flow_vx[idx], flow_vy[idx])


func get_surface(x: int, y: int) -> float:
	return surface_height[get_index(x, y)]


func get_temperature(x: int, y: int) -> float:
	return water_temp[get_index(x, y)]


func is_water(x: int, y: int) -> bool:
	return water_depth[get_index(x, y)] > 0.001

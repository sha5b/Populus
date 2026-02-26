extends RefCounted
class_name HydroGrid

var width: int
var height: int
var bed_z: PackedFloat32Array
var h: PackedFloat32Array
var hu: PackedFloat32Array
var hv: PackedFloat32Array


func initialize_from_terrain(g: TorusGrid, res_w: int, res_h: int) -> void:
	width = res_w
	height = res_h
	var total := width * height
	bed_z = PackedFloat32Array()
	bed_z.resize(total)
	h = PackedFloat32Array()
	h.resize(total)
	hu = PackedFloat32Array()
	hu.resize(total)
	hv = PackedFloat32Array()
	hv.resize(total)

	for cy in range(height):
		for cx in range(width):
			var gx := int(float(cx) / float(width) * float(g.width))
			var gy := int(float(cy) / float(height) * float(g.height))
			bed_z[cy * width + cx] = g.get_height(gx, gy)
			h[cy * width + cx] = 0.0
			hu[cy * width + cx] = 0.0
			hv[cy * width + cx] = 0.0


func initialize_from_watergrid(g: TorusGrid, wg: WaterGrid, res_w: int, res_h: int) -> void:
	initialize_from_terrain(g, res_w, res_h)
	for cy in range(height):
		for cx in range(width):
			var gx0 := int(float(cx) / float(width) * float(g.width))
			var gy0 := int(float(cy) / float(height) * float(g.height))
			var gx1 := int(float(cx + 1) / float(width) * float(g.width))
			var gy1 := int(float(cy + 1) / float(height) * float(g.height))
			gx1 = maxi(gx1, gx0 + 1)
			gy1 = maxi(gy1, gy0 + 1)

			var sum_h := 0.0
			var count := 0
			for gy in range(gy0, mini(gy1, g.height)):
				for gx in range(gx0, mini(gx1, g.width)):
					sum_h += wg.get_depth(gx, gy)
					count += 1
			var avg := sum_h / float(count) if count > 0 else 0.0
			h[cy * width + cx] = maxf(avg, 0.0)


func idx(x: int, y: int) -> int:
	return ((y % height + height) % height) * width + ((x % width + width) % width)


func get_h(x: int, y: int) -> float:
	return h[idx(x, y)]


func set_h(x: int, y: int, v: float) -> void:
	h[idx(x, y)] = v


func get_bed(x: int, y: int) -> float:
	return bed_z[idx(x, y)]

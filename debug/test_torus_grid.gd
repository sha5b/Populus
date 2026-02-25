class_name TestTorusGrid

var _pass_count: int = 0
var _fail_count: int = 0


func run_all() -> void:
	print("\n=== TorusGrid Tests ===")
	_pass_count = 0
	_fail_count = 0

	_test_wrap_negative()
	_test_wrap_overflow()
	_test_height_read_write()
	_test_tile_center_height()
	_test_is_flat_uniform()
	_test_is_flat_varied()
	_test_is_underwater()
	_test_neighbors_4()
	_test_neighbors_8()
	_test_torus_distance_adjacent()
	_test_torus_distance_wrap()
	_test_torus_distance_diagonal()
	_test_fill_circle()
	_test_flatten_area()

	print("=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])


func _assert(condition: bool, test_name: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS: %s" % test_name)
	else:
		_fail_count += 1
		print("  FAIL: %s" % test_name)


func _assert_eq_float(a: float, b: float, test_name: String, tolerance: float = 0.001) -> void:
	_assert(absf(a - b) < tolerance, test_name)


func _test_wrap_negative() -> void:
	var grid := TorusGrid.new(128, 128)
	grid.set_height(127, 0, 5.0)
	_assert_eq_float(grid.get_height(-1, 0), 5.0, "wrap negative x: get_height(-1,0) == get_height(127,0)")


func _test_wrap_overflow() -> void:
	var grid := TorusGrid.new(128, 128)
	grid.set_height(0, 0, 7.0)
	_assert_eq_float(grid.get_height(128, 0), 7.0, "wrap overflow x: get_height(128,0) == get_height(0,0)")


func _test_height_read_write() -> void:
	var grid := TorusGrid.new(128, 128)
	grid.set_height(50, 60, 3.14)
	_assert_eq_float(grid.get_height(50, 60), 3.14, "height read/write at (50,60)")


func _test_tile_center_height() -> void:
	var grid := TorusGrid.new(128, 128)
	grid.set_height(10, 10, 1.0)
	grid.set_height(11, 10, 2.0)
	grid.set_height(10, 11, 3.0)
	grid.set_height(11, 11, 4.0)
	_assert_eq_float(grid.get_tile_center_height(10, 10), 2.5, "tile center height avg of 4 corners")


func _test_is_flat_uniform() -> void:
	var grid := TorusGrid.new(128, 128)
	grid.set_height(20, 20, 5.0)
	grid.set_height(21, 20, 5.0)
	grid.set_height(20, 21, 5.0)
	grid.set_height(21, 21, 5.0)
	_assert(grid.is_flat(20, 20), "is_flat true for uniform heights")


func _test_is_flat_varied() -> void:
	var grid := TorusGrid.new(128, 128)
	grid.set_height(30, 30, 1.0)
	grid.set_height(31, 30, 5.0)
	grid.set_height(30, 31, 1.0)
	grid.set_height(31, 31, 1.0)
	_assert(not grid.is_flat(30, 30), "is_flat false for varied heights")


func _test_is_underwater() -> void:
	var grid := TorusGrid.new(128, 128)
	grid.set_height(40, 40, -1.0)
	grid.set_height(41, 40, -1.0)
	grid.set_height(40, 41, -1.0)
	grid.set_height(41, 41, -1.0)
	_assert(grid.is_underwater(40, 40), "is_underwater true for negative heights")


func _test_neighbors_4() -> void:
	var grid := TorusGrid.new(128, 128)
	var n4 := grid.get_neighbors_4(0, 0)
	_assert(n4.size() == 4, "neighbors_4 returns 4 tiles")
	_assert(n4.has(Vector2i(0, 127)), "neighbors_4 wraps north to 127")


func _test_neighbors_8() -> void:
	var grid := TorusGrid.new(128, 128)
	var n8 := grid.get_neighbors_8(0, 0)
	_assert(n8.size() == 8, "neighbors_8 returns 8 tiles")
	_assert(n8.has(Vector2i(127, 127)), "neighbors_8 wraps diag to (127,127)")


func _test_torus_distance_adjacent() -> void:
	var grid := TorusGrid.new(128, 128)
	_assert_eq_float(grid.torus_distance(Vector2i(0, 0), Vector2i(1, 0)), 1.0, "torus_distance adjacent = 1.0")


func _test_torus_distance_wrap() -> void:
	var grid := TorusGrid.new(128, 128)
	_assert_eq_float(grid.torus_distance(Vector2i(0, 0), Vector2i(127, 0)), 1.0, "torus_distance wrap (0,0)->(127,0) = 1.0")


func _test_torus_distance_diagonal() -> void:
	var grid := TorusGrid.new(128, 128)
	var d := grid.torus_distance(Vector2i(0, 0), Vector2i(127, 127))
	_assert_eq_float(d, sqrt(2.0), "torus_distance diagonal wrap = sqrt(2)")


func _test_fill_circle() -> void:
	var grid := TorusGrid.new(128, 128)
	grid.fill_circle(64, 64, 3.0, 10.0)
	var center_h := grid.get_height(64, 64)
	_assert(center_h > 9.0, "fill_circle: center height > 9.0 (got %.2f)" % center_h)
	var edge_h := grid.get_height(67, 64)
	_assert(edge_h < center_h, "fill_circle: edge height < center (falloff)")
	var outside_h := grid.get_height(70, 64)
	_assert_eq_float(outside_h, 0.0, "fill_circle: outside radius unchanged")


func _test_flatten_area() -> void:
	var grid := TorusGrid.new(128, 128)
	grid.set_height(50, 50, 10.0)
	grid.set_height(51, 50, 20.0)
	grid.set_height(50, 51, 30.0)
	grid.set_height(51, 51, 40.0)
	grid.flatten_area(50, 50, 2.0)
	var h := grid.get_height(50, 50)
	_assert(grid.is_flat(50, 50, 0.01), "flatten_area: tile is flat after flatten (h=%.2f)" % h)

extends System
class_name SysWaterSwe

const HydroGridScript = preload("res://planet/hydro_grid.gd")

var grid: TorusGrid = null
var water: WaterGrid = null
var hydro = null
var weather_system: SysWeather = null
var temperature_map: PackedFloat32Array
var river_map: PackedFloat32Array

var _timer: float = 0.0
var _terrain_timer: float = 0.0
var _resample_offset: int = 0
var _needs_resample: bool = true
var _resample_timer: float = 0.0

var _h_new: PackedFloat32Array
var _hu_new: PackedFloat32Array
var _hv_new: PackedFloat32Array

var _cw: int = 0
var _ch: int = 0
var _x_l: PackedInt32Array
var _x_r: PackedInt32Array
var _y_u: PackedInt32Array
var _y_d: PackedInt32Array

var _resample_chunk_size: int = 8192

func setup(g: TorusGrid, wg: WaterGrid, ws: SysWeather, temp: PackedFloat32Array) -> void:
	grid = g
	water = wg
	weather_system = ws
	temperature_map = temp
	_resample_chunk_size = GameConfig.SWE_RESAMPLE_CHUNK_SIZE

	river_map = PackedFloat32Array()
	river_map.resize(g.width * g.height)
	river_map.fill(0.0)

	var res = mini(GameConfig.SWE_RESOLUTION, mini(g.width, g.height))
	hydro = HydroGridScript.new()
	hydro.initialize_from_watergrid(g, wg, res, res)

	_h_new = PackedFloat32Array()
	_hu_new = PackedFloat32Array()
	_hv_new = PackedFloat32Array()
	_h_new.resize(res * res)
	_hu_new.resize(res * res)
	_hv_new.resize(res * res)

	_cw = hydro.width
	_ch = hydro.height
	_x_l = PackedInt32Array()
	_x_l.resize(_cw)
	_x_r = PackedInt32Array()
	_x_r.resize(_cw)
	for x in range(_cw):
		_x_l[x] = x - 1 if x > 0 else (_cw - 1)
		_x_r[x] = x + 1 if x < _cw - 1 else 0
	_y_u = PackedInt32Array()
	_y_u.resize(_ch)
	_y_d = PackedInt32Array()
	_y_d.resize(_ch)
	for y in range(_ch):
		_y_u[y] = y - 1 if y > 0 else (_ch - 1)
		_y_d[y] = y + 1 if y < _ch - 1 else 0


func update(_world: Node, delta: float) -> void:
	if grid == null or water == null or hydro == null:
		return

	_timer += delta
	_terrain_timer += delta

	if _terrain_timer >= GameConfig.SWE_SAMPLE_TERRAIN_INTERVAL:
		_terrain_timer = 0.0
		_resample_bed_from_terrain()

	if _timer >= GameConfig.SWE_TICK_INTERVAL:
		_timer -= GameConfig.SWE_TICK_INTERVAL
		_step_swe(GameConfig.SWE_TICK_INTERVAL)
		_needs_resample = true

	if _needs_resample:
		_resample_timer += delta
		if _resample_timer >= GameConfig.SWE_RESAMPLE_INTERVAL:
			_resample_timer = 0.0
			_resample_watergrid_chunk()


func _resample_bed_from_terrain() -> void:
	for cy in range(hydro.height):
		for cx in range(hydro.width):
			var gx = int(float(cx) / float(hydro.width) * float(grid.width))
			var gy = int(float(cy) / float(hydro.height) * float(grid.height))
			hydro.bed_z[cy * hydro.width + cx] = grid.get_height(gx, gy)


func _step_swe(dt_total: float) -> void:
	_apply_rain_and_evaporation(dt_total)
	var max_speed = _estimate_max_wave_speed()

	var remaining = dt_total
	var substeps = 0
	while remaining > 0.000001 and substeps < GameConfig.SWE_MAX_SUBSTEPS:
		substeps += 1
		var dt_cfl = remaining
		if max_speed > 0.0001:
			dt_cfl = minf(dt_cfl, GameConfig.SWE_CFL / max_speed)
		var dt = dt_cfl
		_advance_one_substep(dt)
		remaining -= dt


func _apply_rain_and_evaporation(dt: float) -> void:
	var state: int = DefEnums.WeatherState.CLEAR
	if weather_system:
		state = weather_system.current_state

	var rain_rate = 0.0
	if state == DefEnums.WeatherState.RAIN or state == DefEnums.WeatherState.SNOW:
		rain_rate = GameConfig.WATER_RAIN_RATE
	elif state == DefEnums.WeatherState.STORM or state == DefEnums.WeatherState.BLIZZARD:
		rain_rate = GameConfig.WATER_STORM_RAIN_RATE
	elif state == DefEnums.WeatherState.HURRICANE:
		rain_rate = GameConfig.WATER_HURRICANE_RAIN_RATE

	var do_evap = state == DefEnums.WeatherState.CLEAR or state == DefEnums.WeatherState.HEATWAVE
	var evap_mult = GameConfig.WATER_HEATWAVE_EVAP_MULT if state == DefEnums.WeatherState.HEATWAVE else 1.0

	for cy in range(hydro.height):
		for cx in range(hydro.width):
			var i = cy * hydro.width + cx
			var h = hydro.h[i]
			if rain_rate > 0.0:
				h += rain_rate * dt

			if do_evap and h > 0.0:
				var gx = int(float(cx) / float(hydro.width) * float(grid.width))
				var gy = int(float(cy) / float(hydro.height) * float(grid.height))
				var fine_i = gy * grid.width + gx
				var temp = temperature_map[fine_i] if fine_i >= 0 and fine_i < temperature_map.size() else 0.5
				var evap = (GameConfig.WATER_EVAPORATION_BASE + temp * GameConfig.WATER_EVAPORATION_HEAT_FACTOR) * evap_mult
				h = maxf(h - evap * dt, 0.0)

			hydro.h[i] = h


func _estimate_max_wave_speed() -> float:
	var g = GameConfig.SWE_G
	var max_s = 0.0001
	for i in range(hydro.h.size()):
		var h = hydro.h[i]
		if h <= GameConfig.SWE_MIN_H:
			continue
		var inv_h = 1.0 / h
		var u = hydro.hu[i] * inv_h
		var v = hydro.hv[i] * inv_h
		
		# Cap velocity to prevent extreme Mach numbers in shallow water causing dt -> 0
		var speed_sq = u * u + v * v
		if speed_sq > 400.0:
			var factor = 20.0 / sqrt(speed_sq)
			u *= factor
			v *= factor
			hydro.hu[i] = u * h
			hydro.hv[i] = v * h
			
		var c = sqrt(g * h)
		max_s = maxf(max_s, absf(u) + c)
		max_s = maxf(max_s, absf(v) + c)
	return max_s


func _advance_one_substep(dt: float) -> void:
	var w = _cw
	var h = _ch
	var total = w * h
	var g = GameConfig.SWE_G

	for i in range(total):
		_h_new[i] = hydro.h[i]
		_hu_new[i] = hydro.hu[i]
		_hv_new[i] = hydro.hv[i]

	var inv_dx = 1.0
	var min_h = GameConfig.SWE_MIN_H

	# --- X fluxes (Rusanov) ---
	for y in range(h):
		var row = y * w
		for x in range(w):
			var i = row + x
			var ir = row + _x_r[x]

			var hL = maxf(hydro.h[i], 0.0)
			var hR = maxf(hydro.h[ir], 0.0)

			var uL = 0.0
			var vL = 0.0
			var uR = 0.0
			var vR = 0.0
			var huL = hydro.hu[i]
			var hvL = hydro.hv[i]
			var huR = hydro.hu[ir]
			var hvR = hydro.hv[ir]
			if hL > min_h:
				uL = huL / hL
				vL = hvL / hL
			else:
				huL = 0.0
				hvL = 0.0
			if hR > min_h:
				uR = huR / hR
				vR = hvR / hR
			else:
				huR = 0.0
				hvR = 0.0

			var cL = sqrt(g * hL)
			var cR = sqrt(g * hR)
			var smax = maxf(absf(uL) + cL, absf(uR) + cR)

			var f0L = huL
			var f1L = huL * uL + 0.5 * g * hL * hL
			var f2L = huL * vL
			var f0R = huR
			var f1R = huR * uR + 0.5 * g * hR * hR
			var f2R = huR * vR

			var flux0 = 0.5 * (f0L + f0R) - 0.5 * smax * (hR - hL)
			var flux1 = 0.5 * (f1L + f1R) - 0.5 * smax * (huR - huL)
			var flux2 = 0.5 * (f2L + f2R) - 0.5 * smax * (hvR - hvL)

			_h_new[i] -= flux0 * dt * inv_dx
			_hu_new[i] -= flux1 * dt * inv_dx
			_hv_new[i] -= flux2 * dt * inv_dx
			_h_new[ir] += flux0 * dt * inv_dx
			_hu_new[ir] += flux1 * dt * inv_dx
			_hv_new[ir] += flux2 * dt * inv_dx

	# --- Y fluxes (Rusanov) ---
	for y in range(h):
		var row = y * w
		var row_d = _y_d[y] * w
		for x in range(w):
			var i = row + x
			var id = row_d + x

			var hU = maxf(hydro.h[i], 0.0)
			var hD = maxf(hydro.h[id], 0.0)

			var uU = 0.0
			var vU = 0.0
			var uD = 0.0
			var vD = 0.0
			var huU = hydro.hu[i]
			var hvU = hydro.hv[i]
			var huD = hydro.hu[id]
			var hvD = hydro.hv[id]
			if hU > min_h:
				uU = huU / hU
				vU = hvU / hU
			else:
				huU = 0.0
				hvU = 0.0
			if hD > min_h:
				uD = huD / hD
				vD = hvD / hD
			else:
				huD = 0.0
				hvD = 0.0

			var cU = sqrt(g * hU)
			var cD = sqrt(g * hD)
			var smax = maxf(absf(vU) + cU, absf(vD) + cD)

			var g0U = hvU
			var g1U = hvU * uU
			var g2U = hvU * vU + 0.5 * g * hU * hU
			var g0D = hvD
			var g1D = hvD * uD
			var g2D = hvD * vD + 0.5 * g * hD * hD

			var flux0 = 0.5 * (g0U + g0D) - 0.5 * smax * (hD - hU)
			var flux1 = 0.5 * (g1U + g1D) - 0.5 * smax * (huD - huU)
			var flux2 = 0.5 * (g2U + g2D) - 0.5 * smax * (hvD - hvU)

			_h_new[i] -= flux0 * dt * inv_dx
			_hu_new[i] -= flux1 * dt * inv_dx
			_hv_new[i] -= flux2 * dt * inv_dx
			_h_new[id] += flux0 * dt * inv_dx
			_hu_new[id] += flux1 * dt * inv_dx
			_hv_new[id] += flux2 * dt * inv_dx

	for y in range(h):
		var row = y * w
		var row_u = _y_u[y] * w
		var row_d = _y_d[y] * w
		for x in range(w):
			var i = row + x
			var il = row + _x_l[x]
			var ir = row + _x_r[x]
			var iu = row_u + x
			var id = row_d + x
			var hi = maxf(_h_new[i], 0.0)
			if hi <= min_h:
				continue

			var dzdx = (hydro.bed_z[ir] - hydro.bed_z[il]) * 0.5
			var dzdy = (hydro.bed_z[id] - hydro.bed_z[iu]) * 0.5
			_hu_new[i] += (-g * hi * dzdx) * dt
			_hv_new[i] += (-g * hi * dzdy) * dt

			_hu_new[i] *= (1.0 - GameConfig.SWE_FRICTION * dt)
			_hv_new[i] *= (1.0 - GameConfig.SWE_FRICTION * dt)

	for i in range(total):
		var new_h = maxf(_h_new[i], 0.0)
		if new_h < GameConfig.SWE_MIN_H:
			hydro.h[i] = 0.0
			hydro.hu[i] = 0.0
			hydro.hv[i] = 0.0
			continue
		hydro.h[i] = new_h
		hydro.hu[i] = _hu_new[i]
		hydro.hv[i] = _hv_new[i]


func _rusanov_flux_x(iL: int, iR: int, g: float) -> Array[float]:
	var hL = maxf(hydro.h[iL], 0.0)
	var hR = maxf(hydro.h[iR], 0.0)

	var uL = 0.0
	var vL = 0.0
	var uR = 0.0
	var vR = 0.0
	if hL > GameConfig.SWE_MIN_H:
		uL = hydro.hu[iL] / hL
		vL = hydro.hv[iL] / hL
	if hR > GameConfig.SWE_MIN_H:
		uR = hydro.hu[iR] / hR
		vR = hydro.hv[iR] / hR

	var cL = sqrt(g * hL)
	var cR = sqrt(g * hR)
	var smax = maxf(absf(uL) + cL, absf(uR) + cR)

	var f0L = hydro.hu[iL]
	var f1L = hydro.hu[iL] * uL + 0.5 * g * hL * hL
	var f2L = hydro.hu[iL] * vL

	var f0R = hydro.hu[iR]
	var f1R = hydro.hu[iR] * uR + 0.5 * g * hR * hR
	var f2R = hydro.hu[iR] * vR

	var u0 = 0.5 * (f0L + f0R) - 0.5 * smax * (hR - hL)
	var u1 = 0.5 * (f1L + f1R) - 0.5 * smax * (hydro.hu[iR] - hydro.hu[iL])
	var u2 = 0.5 * (f2L + f2R) - 0.5 * smax * (hydro.hv[iR] - hydro.hv[iL])
	return [u0, u1, u2]


func _rusanov_flux_y(iU: int, iD: int, g: float) -> Array[float]:
	var hU = maxf(hydro.h[iU], 0.0)
	var hD = maxf(hydro.h[iD], 0.0)

	var uU = 0.0
	var vU = 0.0
	var uD = 0.0
	var vD = 0.0
	if hU > GameConfig.SWE_MIN_H:
		uU = hydro.hu[iU] / hU
		vU = hydro.hv[iU] / hU
	if hD > GameConfig.SWE_MIN_H:
		uD = hydro.hu[iD] / hD
		vD = hydro.hv[iD] / hD

	var cU = sqrt(g * hU)
	var cD = sqrt(g * hD)
	var smax = maxf(absf(vU) + cU, absf(vD) + cD)

	var g0U = hydro.hv[iU]
	var g1U = hydro.hv[iU] * uU
	var g2U = hydro.hv[iU] * vU + 0.5 * g * hU * hU

	var g0D = hydro.hv[iD]
	var g1D = hydro.hv[iD] * uD
	var g2D = hydro.hv[iD] * vD + 0.5 * g * hD * hD

	var u0 = 0.5 * (g0U + g0D) - 0.5 * smax * (hD - hU)
	var u1 = 0.5 * (g1U + g1D) - 0.5 * smax * (hydro.hu[iD] - hydro.hu[iU])
	var u2 = 0.5 * (g2U + g2D) - 0.5 * smax * (hydro.hv[iD] - hydro.hv[iU])
	return [u0, u1, u2]


func _resample_watergrid_chunk() -> void:
	var total = grid.width * grid.height
	if total <= 0:
		return

	var end_idx = mini(_resample_offset + _resample_chunk_size, total)
	var fine_w = grid.width
	var fine_h = grid.height
	var cw = _cw
	var ch = _ch

	for i in range(_resample_offset, end_idx):
		var x = i % fine_w
		var y = int(float(i) / float(fine_w))

		var fx = (float(x) + 0.5) / float(fine_w) * float(cw)
		var fy = (float(y) + 0.5) / float(fine_h) * float(ch)

		var h_val = _sample_bilinear(hydro.h, fx, fy)
		var hu_val = _sample_bilinear(hydro.hu, fx, fy)
		var hv_val = _sample_bilinear(hydro.hv, fx, fy)

		var depth = maxf(h_val, 0.0)
		if depth < GameConfig.WATER_MIN_DEPTH:
			depth = 0.0

		water.water_depth[i] = depth
		var vx: float = (hu_val / h_val) if h_val > GameConfig.SWE_MIN_H else 0.0
		var vy: float = (hv_val / h_val) if h_val > GameConfig.SWE_MIN_H else 0.0
		water.flow_vx[i] = vx
		water.flow_vy[i] = vy

		var terrain_h = grid.heights[i]
		if terrain_h <= GameConfig.SEA_LEVEL:
			river_map[i] = 0.0
		else:
			var discharge: float = depth * sqrt(vx * vx + vy * vy)
			river_map[i] = clampf(discharge * GameConfig.SWE_RIVER_VIS_SCALE, 0.0, 1.0)
		water.surface_height[i] = terrain_h + depth
		_resample_timer = 0.0

	_resample_offset = end_idx if end_idx < total else 0
	if _resample_offset == 0:
		_needs_resample = false


func _sample_bilinear(field: PackedFloat32Array, fx: float, fy: float) -> float:
	var x0 = int(floor(fx))
	var y0 = int(floor(fy))
	var x1 = x0 + 1
	var y1 = y0 + 1
	var tx = fx - float(x0)
	var ty = fy - float(y0)

	var wx0 = x0
	var wy0 = y0
	var wx1 = x1 if x1 < _cw else 0
	var wy1 = y1 if y1 < _ch else 0
	var v00 = field[wy0 * _cw + wx0]
	var v10 = field[wy0 * _cw + wx1]
	var v01 = field[wy1 * _cw + wx0]
	var v11 = field[wy1 * _cw + wx1]

	return lerpf(lerpf(v00, v10, tx), lerpf(v01, v11, tx), ty)

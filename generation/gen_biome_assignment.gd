class_name GenBiomeAssignment


static var _boundary_noise: FastNoiseLite
static var _boundary_noise2: FastNoiseLite


static func _ensure_boundary_noise() -> void:
	if _boundary_noise != null:
		return
	var freq_scale := 128.0 / float(GameConfig.GRID_WIDTH)
	_boundary_noise = FastNoiseLite.new()
	_boundary_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_boundary_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_boundary_noise.fractal_octaves = 3
	_boundary_noise.frequency = 0.05 * freq_scale
	_boundary_noise.seed = 77777
	_boundary_noise2 = FastNoiseLite.new()
	_boundary_noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_boundary_noise2.fractal_type = FastNoiseLite.FRACTAL_FBM
	_boundary_noise2.fractal_octaves = 2
	_boundary_noise2.frequency = 0.08 * freq_scale
	_boundary_noise2.seed = 88888


static func assign(
	grid: TorusGrid,
	temperature_map: PackedFloat32Array,
	moisture_map: PackedFloat32Array,
	biome_map: PackedInt32Array,
	continentalness_map: PackedFloat32Array = PackedFloat32Array(),
	erosion_map: PackedFloat32Array = PackedFloat32Array(),
	weirdness_map: PackedFloat32Array = PackedFloat32Array()
) -> void:
	_ensure_boundary_noise()
	var w := grid.width
	var h := grid.height
	var total := w * h
	var has_noise_maps := continentalness_map.size() == total
	var counts := {}

	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			var height := grid.get_tile_center_height(x, y)
			var temp := temperature_map[idx]
			var moist := moisture_map[idx]

			# Perturb temp/moisture at biome boundaries for organic edges
			var t_perturb := _boundary_noise.get_noise_2d(float(x), float(y)) * 0.08
			var m_perturb := _boundary_noise2.get_noise_2d(float(x), float(y)) * 0.08
			temp = clampf(temp + t_perturb, 0.0, 1.0)
			moist = clampf(moist + m_perturb, 0.0, 1.0)

			var cont := continentalness_map[idx] if has_noise_maps else 0.5
			var ero := erosion_map[idx] if has_noise_maps else 0.5
			var weird := weirdness_map[idx] if has_noise_maps else 0.0

			var biome := _classify_multinoise(height, temp, moist, cont, ero, weird)
			biome_map[idx] = biome

			if not counts.has(biome):
				counts[biome] = 0
			counts[biome] += 1

	var summary := ""
	for b in counts.keys():
		var bname: String = DefBiomes.BIOME_DATA[b]["name"] if DefBiomes.BIOME_DATA.has(b) else "?"
		var pct := float(counts[b]) / float(total) * 100.0
		if pct > 1.0:
			summary += "%s: %.0f%% | " % [bname, pct]
	print("Biomes assigned (multi-noise): %s" % summary)


static func _classify_multinoise(height: float, temp: float, moist: float, cont: float, erosion: float, weirdness: float) -> int:
	if height < GameConfig.SEA_LEVEL:
		if cont < 0.2:
			return DefEnums.BiomeType.OCEAN
		return DefEnums.BiomeType.OCEAN

	var terrain_cat := _get_terrain_category(cont, erosion, height)

	match terrain_cat:
		0:
			return _pick_coast_biome(temp, moist, weirdness)
		1:
			return _pick_plains_biome(temp, moist, weirdness)
		2:
			return _pick_hills_biome(temp, moist, weirdness)
		3:
			return _pick_mountain_biome(temp, moist, weirdness)
		_:
			return _pick_plains_biome(temp, moist, weirdness)


static func _get_terrain_category(cont: float, erosion: float, height: float) -> int:
	if height < 0.03:
		return 0
	if height > 0.4 or (cont > 0.7 and erosion < 0.3):
		return 3
	if erosion < 0.4 and cont > 0.5:
		return 2
	if erosion > 0.65:
		return 1
	return 1


static func _pick_coast_biome(temp: float, moist: float, weirdness: float) -> int:
	if moist > 0.7 and temp > 0.5:
		if weirdness > 0.7:
			return DefEnums.BiomeType.SWAMP
		return DefEnums.BiomeType.SWAMP
	if temp < 0.2:
		return DefEnums.BiomeType.SNOW_ICE
	return DefEnums.BiomeType.BEACH


static func _pick_plains_biome(temp: float, moist: float, weirdness: float) -> int:
	if temp > 0.7:
		if moist > 0.6:
			return DefEnums.BiomeType.TROPICAL_FOREST
		elif moist > 0.3:
			if weirdness > 0.75:
				return DefEnums.BiomeType.TROPICAL_FOREST
			return DefEnums.BiomeType.SAVANNA
		else:
			return DefEnums.BiomeType.DESERT

	if temp > 0.45:
		if moist > 0.55:
			return DefEnums.BiomeType.TEMPERATE_FOREST
		elif moist > 0.25:
			return DefEnums.BiomeType.GRASSLAND
		else:
			if weirdness > 0.7:
				return DefEnums.BiomeType.SAVANNA
			return DefEnums.BiomeType.STEPPE

	if temp > 0.25:
		if moist > 0.5:
			return DefEnums.BiomeType.BOREAL_FOREST
		else:
			return DefEnums.BiomeType.TAIGA

	if moist > 0.35:
		return DefEnums.BiomeType.TUNDRA
	return DefEnums.BiomeType.SNOW_ICE


static func _pick_hills_biome(temp: float, moist: float, weirdness: float) -> int:
	if temp > 0.6:
		if moist > 0.5:
			return DefEnums.BiomeType.TEMPERATE_FOREST
		elif moist > 0.25:
			if weirdness > 0.7:
				return DefEnums.BiomeType.SAVANNA
			return DefEnums.BiomeType.GRASSLAND
		else:
			return DefEnums.BiomeType.STEPPE

	if temp > 0.35:
		if moist > 0.45:
			return DefEnums.BiomeType.BOREAL_FOREST
		else:
			return DefEnums.BiomeType.TAIGA

	if temp > 0.15:
		return DefEnums.BiomeType.TUNDRA
	return DefEnums.BiomeType.SNOW_ICE


static func _pick_mountain_biome(temp: float, _moist: float, _weirdness: float) -> int:
	if temp < 0.2:
		return DefEnums.BiomeType.SNOW_ICE
	if temp < 0.4:
		return DefEnums.BiomeType.MOUNTAIN
	return DefEnums.BiomeType.MOUNTAIN

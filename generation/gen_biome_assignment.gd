class_name GenBiomeAssignment


static func assign(
	grid: TorusGrid,
	temperature_map: PackedFloat32Array,
	moisture_map: PackedFloat32Array,
	biome_map: PackedInt32Array
) -> void:
	var w := grid.width
	var h := grid.height
	var counts := {}

	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			var height := grid.get_tile_center_height(x, y)
			var temp := temperature_map[idx]
			var moist := moisture_map[idx]
			var biome := _classify(height, temp, moist)
			biome_map[idx] = biome

			if not counts.has(biome):
				counts[biome] = 0
			counts[biome] += 1

	var total := w * h
	var summary := ""
	for b in counts.keys():
		var name: String = DefBiomes.BIOME_DATA[b]["name"] if DefBiomes.BIOME_DATA.has(b) else "?"
		var pct := float(counts[b]) / float(total) * 100.0
		if pct > 1.0:
			summary += "%s: %.0f%% | " % [name, pct]
	print("Biomes assigned: %s" % summary)


static func _classify(height: float, temp: float, moist: float) -> int:
	if height < GameConfig.SEA_LEVEL:
		return DefEnums.BiomeType.OCEAN

	if height > 0.35:
		if temp < 0.2:
			return DefEnums.BiomeType.SNOW_ICE
		return DefEnums.BiomeType.MOUNTAIN

	if height < 0.03:
		if moist > 0.6:
			return DefEnums.BiomeType.SWAMP
		return DefEnums.BiomeType.BEACH

	if temp > 0.75:
		if moist > 0.6:
			return DefEnums.BiomeType.TROPICAL_FOREST
		elif moist > 0.3:
			return DefEnums.BiomeType.SAVANNA
		else:
			return DefEnums.BiomeType.DESERT

	if temp > 0.45:
		if moist > 0.55:
			return DefEnums.BiomeType.TEMPERATE_FOREST
		elif moist > 0.3:
			return DefEnums.BiomeType.GRASSLAND
		else:
			return DefEnums.BiomeType.STEPPE

	if temp > 0.25:
		if moist > 0.5:
			return DefEnums.BiomeType.BOREAL_FOREST
		else:
			return DefEnums.BiomeType.TAIGA

	if moist > 0.4:
		return DefEnums.BiomeType.TUNDRA

	return DefEnums.BiomeType.SNOW_ICE

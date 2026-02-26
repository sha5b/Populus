class_name DefRocks

enum RockType { BOULDER, PEBBLE, PILLAR, FLAT_ROCK }

const ROCK_DATA: Dictionary = {
	RockType.BOULDER: {
		"name": "Boulder",
		"scale_min": 0.8,
		"scale_max": 2.5,
	},
	RockType.PEBBLE: {
		"name": "Pebble",
		"scale_min": 0.2,
		"scale_max": 0.5,
	},
	RockType.PILLAR: {
		"name": "Pillar",
		"scale_min": 1.0,
		"scale_max": 3.0,
	},
	RockType.FLAT_ROCK: {
		"name": "Flat Rock",
		"scale_min": 1.0,
		"scale_max": 2.0,
	}
}

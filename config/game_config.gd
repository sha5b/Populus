extends Node

const GRID_WIDTH: int = 512
const GRID_HEIGHT: int = 512
const SEA_LEVEL: float = 0.0
const TIME_SCALE: float = 60.0
const MAX_POPULATION: int = 200
var WORLD_SEED: int = 0

const OCEAN_DEPTH_MULT: float = 1.8
const OCEAN_DEPTH_POWER: float = 1.1

const PLANET_RADIUS: float = 500.0
const HEIGHT_SCALE: float = 40.0

const HOURS_PER_DAY: int = 24
const DAYS_PER_SEASON: int = 7
const SEASONS_PER_YEAR: int = 4

const WEATHER_CHECK_MIN: float = 20.0
const WEATHER_CHECK_MAX: float = 60.0
const WEATHER_INITIAL_CHECK: float = 15.0
const WEATHER_CLIMATE_SAMPLE_COUNT: int = 2048

const PRECIP_TICK_INTERVAL: float = 2.0
const PRECIP_CHUNK_SIZE: int = 8192
const PRECIP_RAIN_RATE: float = 0.001
const PRECIP_STORM_RATE: float = 0.003
const PRECIP_EVAP_RATE_BASE: float = 0.0002
const PRECIP_HEATWAVE_EVAP_MULT: float = 3.0

const WIND_NOISE_FREQUENCY: float = 0.1
const WIND_TIME_ACC_SCALE: float = 0.005
const WIND_PERTURBATION_STRENGTH: float = 0.3
const WIND_BASE_SPEED: float = 1.5
const WIND_BASE_SPEED_NOISE: float = 0.5
const WIND_MIN_SPEED: float = 0.2

const ATMOS_SIM_INTERVAL: float = 2.0
const ATMOS_ADVECTION_RATE: float = 0.15
const ATMOS_PRESSURE_SMOOTH: float = 0.05
const ATMOS_BUOYANCY_FACTOR: float = 0.02
const ATMOS_CORIOLIS_FACTOR: float = 0.01
const ATMOS_CONDENSATION_RATE: float = 0.1
const ATMOS_EVAPORATION_RATE: float = 0.12
const ATMOS_PRECIP_THRESHOLD: float = 0.5
const ATMOS_PRECIP_DRAIN: float = 0.06
const ATMOS_LATENT_HEAT: float = 2.0
const ATMOS_WIND_DAMPING: float = 0.98
const ATMOS_DIRTY_THRESHOLD: float = 0.02
const ATMOS_MOISTURE_INJECT := {
	0: 0.002,
	1: 0.008,
	2: 0.02,
	3: 0.04,
	4: 0.005,
	5: 0.01,
	6: 0.06,
	7: 0.08,
	8: -0.01,
}

const WATER_TICK_INTERVAL: float = 0.5
const WATER_CHUNK_SIZE: int = 8192
const WATER_OCEAN_CURRENT_INTERVAL: float = 3.0
const WATER_OCEAN_CURRENT_SAMPLE_COUNT: int = 512
const WATER_GRAVITY: float = 0.08
const WATER_FLOW_DAMPING: float = 0.92
const WATER_MIN_DEPTH: float = 0.001
const WATER_RAIN_RATE: float = 0.0003
const WATER_STORM_RAIN_RATE: float = 0.001
const WATER_HURRICANE_RAIN_RATE: float = 0.003
const WATER_BLIZZARD_RAIN_RATE: float = 0.0005
const WATER_EVAPORATION_BASE: float = 0.00005
const WATER_EVAPORATION_HEAT_FACTOR: float = 0.0001
const WATER_HEATWAVE_EVAP_MULT: float = 4.0
const WATER_WAVE_DECAY: float = 0.92
const WATER_STORM_WAVE_BOOST: float = 0.01
const WATER_HURRICANE_WAVE_BOOST: float = 0.04
const WATER_BLIZZARD_WAVE_BOOST: float = 0.015
const WATER_WIND_CURRENT_STRENGTH: float = 0.012
const WATER_HURRICANE_CURRENT_STRENGTH: float = 0.05
const WATER_THERMAL_CURRENT_STRENGTH: float = 0.003
const WATER_CORIOLIS_FACTOR: float = 0.01
const WATER_RIVER_INJECT_RATE: float = 0.002

const DIURNAL_TICK_INTERVAL: float = 0.5
const DIURNAL_CHUNK_SIZE: int = 8192
const DIURNAL_LAND_SWING: float = 0.08
const DIURNAL_OCEAN_SWING: float = 0.03

const RIVER_BASE_RIVER_THRESHOLD: float = 25.0
const RIVER_BASE_CANYON_THRESHOLD: float = 80.0
const RIVER_BASE_CARVE_RATE: float = 0.006
const RIVER_CANYON_CARVE_RATE: float = 0.015
const RIVER_CARVE_PASSES: int = 3
const RIVER_MOISTURE_BOOST: float = 0.10
const RIVER_MOISTURE_RADIUS: int = 2

const USE_SWE_WATER: bool = true
const SWE_RESOLUTION: int = 96
const SWE_TICK_INTERVAL: float = 0.45
const SWE_MAX_SUBSTEPS: int = 6
const SWE_CFL: float = 0.45
const SWE_G: float = 3.5
const SWE_FRICTION: float = 0.06
const SWE_MIN_H: float = 0.0005
const SWE_SAMPLE_TERRAIN_INTERVAL: float = 2.0
const SWE_RIVER_VIS_SCALE: float = 120.0
const SWE_RESAMPLE_INTERVAL: float = 0.06
const SWE_RESAMPLE_CHUNK_SIZE: int = 4096

const VOLC_TICK_INTERVAL: float = 2.0
const VOLC_CHUNK_SIZE: int = 2048
const VOLC_PRESSURE_DECAY: float = 0.985
const VOLC_DIFFUSION: float = 0.08
const VOLC_INJECT_CONVERGENT: float = 0.006
const VOLC_INJECT_DIVERGENT: float = 0.002
const VOLC_HOTSPOT_COUNT: int = 8
const VOLC_HOTSPOT_INJECT: float = 0.004
const VOLC_HOTSPOT_RADIUS_DOT: float = 0.12
const VOLC_ERUPT_THRESHOLD: float = 0.85
const VOLC_ERUPT_CHANCE: float = 0.25
const VOLC_ERUPT_RADIUS: float = 3.0
const VOLC_ERUPT_UPLIFT: float = 0.015
const VOLC_MAX_TERRAIN_H: float = 0.95
const VOLC_TEMP_BOOST: float = 0.05


func _ready() -> void:
	randomize()
	WORLD_SEED = randi()

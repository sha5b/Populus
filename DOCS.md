# Populus — Technical Documentation

> Complete technical specification for recreating Populous: The Beginning as a living world simulator in Godot 4.6 with ECS architecture.

---

## Table of Contents

1. [Deep Analysis of the Original Game](#1-deep-analysis-of-populous-the-beginning)
2. [Planet Geometry & Terrain](#2-planet-geometry--terrain-system)
3. [ECS Architecture](#3-ecs-architecture)
4. [Component Catalog](#4-component-catalog)
5. [System Catalog](#5-system-catalog)
6. [Terrain Generation Pipeline](#6-terrain-generation-pipeline)
7. [Biome System](#7-biome-system)
8. [Unit & Follower System](#8-unit--follower-system)
9. [Building System](#9-building-system)
10. [Spell & Mana System](#10-spell--mana-system)
11. [Tribal AI System](#11-tribal-ai-system)
12. [Fauna Ecosystem](#12-fauna-ecosystem)
13. [Flora Ecosystem](#13-flora-ecosystem)
14. [Weather System](#14-weather-system)
15. [Time System](#15-time-system)
16. [Camera & Rendering](#16-camera--rendering)
17. [Pathfinding](#17-pathfinding)
18. [Event System](#18-event-system)
19. [Performance Considerations](#19-performance-considerations)

---

## 1. Deep Analysis of Populous: The Beginning

### 1.1 Engine Architecture (Original)

- **Renderer**: Software renderer + optional Direct3D (16/32-bit color).
- **World Geometry**: Flat 2D square grid (~128×128 tiles) with **torus topology** (wraps X and Y). Each vertex has an integer height.
- **Sphere Illusion**: Grid projected onto sphere at render time. Confirmed by community analysis: maps are flat squares in external editors, the globe view shows a perfectly smooth sphere (no terrain protrusion at horizon), and gameplay uses non-euclidean wrapping movement.
- **Characters**: 2D billboard sprites in a 3D world.
- **Textures**: Altitude-based blending with masks — vibrant varied landscapes without per-tile artist work.

### 1.2 Core Game Loop (Original)

```
Each Game Tick (~30 FPS):
  1. Process Player Input (spells, unit commands, camera)
  2. AI Decision Making (per non-player tribe)
  3. Follower Autonomous Behavior (build, harvest, house, wander)
  4. Spell Processing (charge with mana, execute effects)
  5. Building Updates (construction, production, training)
  6. Combat Resolution (melee, ranged, conversion, damage, death)
  7. Terrain Updates (spell effects, erosion, water)
  8. Rendering (project grid→sphere, draw everything)
```

### 1.3 Population Mechanics

- **Max Population**: ~200 per tribe per map.
- **Hut Capacity**: Level 1 (Small) = 3, Level 2 (Medium) = 4, Level 3 (Large) = 5 Braves.
- **Hut Upgrading**: Huts auto-upgrade when ≥3 wood piles are at the entrance AND followers are inside. Level 1→2→3.
- **Brave Breeding (from Populous constant.dat)**:
  - Base breeding time depends on hut level: Level 1 = 4000 ticks, Level 2 = 3000 ticks, Level 3 = 2000 ticks.
  - Occupant multiplier: `n * 0.5 + 0.5` where n = number of occupants (0 occupants = 0.5× speed, 1 = 1.0×, 2 = 1.5×, etc.).
  - **Empty huts still breed at 0.5× rate** — this is a key Populous mechanic.
  - Population penalty bands: pop 0-4 → penalty 30, pop 5-9 → 35, pop 10-14 → 40, etc. (slows breeding as pop grows).
  - `effective_breed_time = base_ticks / occupant_multiplier + pop_penalty`
- **Mana Generation (from Populous wiki)**:
  - Per-follower mana rates (per minute): Shaman = 66.6, Brave = 34.6, Other units = 11.3.
  - Mana is split 50/50 between spell charging and follower training. If one is unavailable, 100% goes to the other.
  - **Mana is wasted if neither spell charging nor training is active** — important to keep queues busy.
- **Training**: Consumes 1 Brave → produces 1 trained unit. Population stays same.
- **Shaman Reincarnation**: Respawns at Circle of Reincarnation after delay. No circle + no followers = elimination.

### 1.4 Combat Mechanics

- **Melee**: Warriors deal ~3× Brave damage, ~3× HP.
- **Ranged**: Firewarriors throw fireballs. Damage falloff with distance. Guard Tower extends range.
- **Conversion**: Preachers emit aura, slowly converting nearby enemies. Stacks. Blocks enemy preacher conversion.
- **Spy**: Disguises as enemy. Can sabotage buildings (burn). Detection = death.
- **Shaman**: Weak HP but devastating spells. Kill enemy Shaman = strategic victory.

### 1.5 Terrain Manipulation

The defining mechanic. Height is per-vertex, integer-stepped.

- **Flatten**: Most important. Required for building placement.
- **Raise/Lower**: Simple height change.
- **Landbridge**: Raises sea floor to connect islands.
- **Erode**: Gradually lowers terrain, sinking coastlines/buildings.
- **Volcano**: Massive height spike + lava damage.
- **Earthquake**: Randomizes heights → destroys buildings on now-uneven ground.

### 1.6 Building Rules

- All require flat terrain of sufficient area.
- All (except Circle of Reincarnation) require wood.
- Multiple Braves speed up construction.
- Destroyed by: attacks, terrain manipulation, spells.

---

## 2. Planet Geometry & Terrain System

### 2.1 The Torus Grid

A 2D grid with wrapping edges (flat torus):

```
Grid: GRID_WIDTH × GRID_HEIGHT (default 128×128)
Wrapping: x_wrapped = x % WIDTH, y_wrapped = y % HEIGHT
Neighbors: N/S/E/W/diagonals, all wrapped
```

Each **vertex** stores: `height: float`.
Each **tile** (cell between 4 vertices) stores: `biome_type, occupant_id, walkable, is_water`.

### 2.2 Sphere Projection (Render Only)

Game logic always uses flat grid. Projection is a vertex shader:

```
longitude = (gx / WIDTH) * 2π
latitude  = (gy / HEIGHT) * π - π/2
base_pos  = R * (cos(lat)*cos(lon), sin(lat), cos(lat)*sin(lon))
normal    = normalize(base_pos)
final_pos = base_pos + normal * height * HEIGHT_SCALE
```

### 2.3 Dual View Modes

| Mode | Projection | Detail |
|---|---|---|
| **Globe** | Full sphere, smooth | Political colors, simplified |
| **Close-Up** | Near-flat, slight curvature | Full detail, buildings/units |

Camera interpolates between modes by zoom distance.

### 2.4 Heightmap Data Structure

```gdscript
class TorusGrid:
    var width: int = 128
    var height: int = 128
    var vertices: PackedFloat32Array  # width * height
    var sea_level: float = 0.0

    func get_height(x: int, y: int) -> float:
        return vertices[wrap_y(y) * width + wrap_x(x)]

    func set_height(x: int, y: int, h: float) -> void:
        vertices[wrap_y(y) * width + wrap_x(x)] = h

    func wrap_x(x: int) -> int:
        return ((x % width) + width) % width

    func wrap_y(y: int) -> int:
        return ((y % height) + height) % height

    func is_flat(x: int, y: int, tolerance: float = 0.1) -> bool:
        var h = get_height(x, y)
        return (abs(get_height(x+1, y) - h) < tolerance and
                abs(get_height(x, y+1) - h) < tolerance and
                abs(get_height(x+1, y+1) - h) < tolerance)
```

---

## 3. ECS Architecture

### 3.1 Why ECS

- **Massive Entity Count**: Thousands of tiles, followers, animals, trees.
- **Composable**: Deer = Position+Health+Hunger+Prey+Herd. Wolf = Position+Health+Hunger+Predator. No inheritance.
- **Drag-and-Drop Systems**: New Disease system? Add `CompDisease` + `SysDisease` → register. Zero changes elsewhere.
- **Separation**: Components = data. Systems = logic. Easy to test, parallelize, disable at runtime.

### 3.2 Framework: Own Lightweight ECS

We roll our own ECS inspired by the Godot-ECS-Starter pattern. Four files, ~80 lines total:

| File | Role |
|---|---|
| `ecs/entity.gd` | Entity = just an int ID (`extends Resource`) |
| `ecs/component.gd` | Base class: `extends Resource`, `get_type() -> String` |
| `ecs/system.gd` | Base class: `update(world, delta)` |
| `ecs/world.gd` | Entity store, component store, `query()`, system runner |

No external dependencies. No runners, no schedulers, no parallel mode. Systems execute in registration order via `World._process()`. KISS.

### 3.3 System Execution Order

Systems are registered in `main.gd` in a deliberate order:

```
Camera → Brave AI → Tribal AI → Fauna AI → Wildmen AI →
Time → DayNight → Season → Weather → Wind → Precipitation →
FloraGrowth → SeedDispersal → FireSpread → Hunger →
PredatorPrey → Herd → Reproduction → Migration → Mana → Population →
Pathfinding → Movement → Combat → Damage → Conversion →
SpellCasting → SpellEffect → TerrainManip → Construction →
Production → Garrison → Death →
TerrainRender → UnitRender → BuildingRender → WeatherRender → UIRender
```

If we need phase grouping later, we create multiple World instances or a simple phase tag.

### 3.4 Adding a New System

```gdscript
# 1. Component (pure data) — components/com_disease.gd
extends Component
class_name ComDisease
func get_type() -> String: return "ComDisease"
var severity: float = 0.0
var contagion_radius: float = 5.0

# 2. System (pure logic) — systems/sys_disease.gd
extends System
class_name SysDisease
func update(world, delta: float) -> void:
    for id in world.query(["ComHealth", "ComDisease"]):
        var hp = world.get_component(id, "ComHealth")
        var dis = world.get_component(id, "ComDisease")
        dis.severity += 0.01 * delta
        hp.current_hp -= dis.severity * 10.0 * delta

# 3. Register in main.gd
world.add_system(SysDisease.new())
# Done. No other files changed.
```

---

## 4. Component Catalog

### Spatial
| Component | Key Fields |
|---|---|
| `CompPosition` | `grid_x, grid_y, world_pos: Vector3` |
| `CompVelocity` | `direction: Vector2, speed: float` |

### Terrain
| Component | Key Fields |
|---|---|
| `CompTile` | `grid_x, grid_y, is_flat, is_water, occupant_id` |
| `CompHeightmap` | `corner_heights: Array[float]` |
| `CompBiome` | `biome_type, temperature, moisture, fertility` |

### Unit
| Component | Key Fields |
|---|---|
| `CompHealth` | `max_hp, current_hp, regen_rate` |
| `CompCombat` | `attack_damage, attack_range, attack_speed, armor` |
| `CompTribe` | `tribe_id, tribe_color` |
| `CompRole` | `role_type` (Brave/Warrior/Firewarrior/Preacher/Spy/Shaman/Wildman) |
| `CompInventory` | `wood: int` |
| `CompConversion` | `conversion_power, conversion_range, progress: Dict` |
| `CompDisguise` | `disguised_as_tribe, is_active, detection_chance` |

### AI
| Component | Key Fields |
|---|---|
| `CompAIState` | `current_state, previous_state, state_timer` |
| `CompTask` | `task_type, target_position, target_entity, priority` |
| `CompPathfinding` | `path: Array[Vector2i], path_index, is_pathing` |
| `CompNeed` | `hunger, rest, safety` |

### Building
| Component | Key Fields |
|---|---|
| `CompBuilding` | `building_type, tribe_id, size: Vector2i` |
| `CompConstruction` | `progress, required_wood, consumed_wood, builders` |
| `CompProduction` | `production_type, timer, interval` |
| `CompGarrison` | `max_occupants, occupants: Array, range_bonus` |

### Spell
| Component | Key Fields |
|---|---|
| `CompSpellCaster` | `known_spells, active_spell, cast_timer` |
| `CompMana` | `current_mana, max_mana, regen_rate` |
| `CompSpellEffect` | `spell_type, position, radius, duration, timer` |
| `CompSpellCharge` | `spell_type, charges, max_charges, recharge_timer` |

### Fauna
| Component | Key Fields |
|---|---|
| `CompHunger` | `current, max, starvation_rate, eat_rate` |
| `CompPredator` | `prey_types, hunt_range, attack_damage` |
| `CompPrey` | `flee_speed_bonus, awareness_range, is_fleeing` |
| `CompHerd` | `herd_id, herd_role, separation_dist, cohesion_dist` |
| `CompReproduction` | `maturity_age, gestation_period, offspring_count, cooldown` |
| `CompMigration` | `preferred_biome, migration_threshold, target` |
| `CompSpecies` | `species_name, diet_type, preferred_biomes` |

### Flora
| Component | Key Fields |
|---|---|
| `CompGrowth` | `stage, growth_rate, age, max_age` |
| `CompSeedDispersal` | `method, range, seed_timer, seed_interval` |
| `CompResource` | `wood_yield, food_yield, is_harvestable` |
| `CompFireSusceptibility` | `flammability, is_burning, burn_timer` |
| `CompPlantSpecies` | `species_name, preferred_biomes, water_need` |

### Weather & Time
| Component | Key Fields |
|---|---|
| `CompTemperature` | `value, base_value` |
| `CompMoisture` | `value, base_value` |
| `CompWind` | `direction: Vector2, speed` |
| `CompAge` | `age, max_age` |
| `CompSchedule` | `wake_hour, sleep_hour, is_active` |

---

## 5. System Catalog

See [DOCS_SYSTEMS.md](DOCS_SYSTEMS.md) for detailed system specifications including:
- Full state machines for Brave AI, Tribal AI, Fauna AI
- Spell effect processing pipeline
- Weather state machine
- Predator-prey dynamics
- Flora growth and seed dispersal

### System Execution Order (Registration Order in main.gd)

```
sys_camera_input → sys_brave_ai → sys_warrior_ai → sys_shaman_ai →
sys_tribal_ai → sys_wildmen_ai → sys_fauna_ai →
sys_time → sys_day_night → sys_season → sys_weather → sys_wind → sys_precipitation →
sys_flora_growth → sys_seed_dispersal → sys_fire_spread → sys_hunger →
sys_predator_prey → sys_herd → sys_reproduction → sys_migration →
sys_mana → sys_population →
sys_pathfinding → sys_movement → sys_combat → sys_damage → sys_conversion →
sys_spell_casting → sys_spell_effect → sys_terrain_manipulation →
sys_construction → sys_production → sys_garrison → sys_death →
sys_terrain_render → sys_biome_render → sys_water_render → sys_ui_render
```

Systems execute sequentially in this order every frame via `World._process()`. No phase runners needed.

---

## 6. Terrain Generation Pipeline

```
 1. Create blank 128×128 grid (all height = 0)
 2. Apply continental noise (FBM, freq=0.015, octaves=6) → continents/oceans
 3. Apply detail noise (FBM, freq=0.08, octaves=4, weight=0.3) → hills/valleys
 4. Set sea_level = 0.0, clamp heights, ensure 40-60% land
 5. Generate temperature (latitude-based + altitude cooling + noise)
 6. Generate moisture (water proximity + wind patterns + noise)
 7. Assign biomes via Whittaker diagram (temp × moisture × altitude)
 8. Place flora (density per biome: forest=dense, desert=sparse)
 9. Place fauna (appropriate species per biome region)
10. Place tribes (flat coastal areas with nearby trees, min distance apart)
11. Place special objects (Vaults, Stone Heads, Wildmen clusters)
```

Uses Godot's built-in `FastNoiseLite` (OpenSimplex2, FBM fractal).

---

## 7. Biome System

### Whittaker Classification

```
                 Dry         Medium       Wet
    Hot    │  Desert    │  Savanna   │  Tropical Forest
    Mid    │  Steppe    │  Grassland │  Temperate Forest
    Cold   │  Tundra    │  Taiga     │  Boreal Forest

Overrides: high altitude → Mountain, very high+cold → Snow,
           very low+wet → Swamp, below sea → Ocean
```

### Biome Gameplay Effects

| Biome | Build Speed | Move Speed | Flora Growth | Fauna | Special |
|---|---|---|---|---|---|
| Tropical Forest | 1× | 0.7× | 2× | High | Rapid regrowth |
| Desert | 1× | 0.8× | 0.1× | Very Low | Heat damage |
| Grassland | 1.2× | 1× | 1× | High | Best for settlements |
| Tundra | 0.7× | 0.8× | 0.3× | Low | Cold damage |
| Mountain | 0.5× | 0.5× | 0.2× | Low | Combat height advantage |
| Swamp | 0.6× | 0.5× | 1.5× | Medium | Disease risk |

---

## 8. Unit & Follower System

### Unit Stats

| Unit | HP | Damage | Range | Speed | Special |
|---|---|---|---|---|---|
| Brave | 30 | 5 | 1 | 3.0 | Builds, harvests, generates mana when housed |
| Warrior | 100 | 15 | 1.5 | 2.5 | Strongest melee fighter |
| Firewarrior | 40 | 20 | 8 | 2.8 | Ranged attacker, low HP |
| Preacher | 50 | 0 | 0 | 2.5 | Conversion aura (range 6) |
| Spy | 35 | 8 | 1 | 3.5 | Disguise + sabotage |
| Shaman | 80 | 10 | 1 | 3.0 | Spells, reincarnation |
| Wildman | 20 | 0 | 0 | 2.0 | Convertible neutral |

### Entity Composition Examples

```
Brave:    com_position + com_velocity + com_health + com_combat + com_tribe +
          com_role(BRAVE) + com_ai_state + com_task + com_pathfinding + com_inventory

Wolf:     com_position + com_velocity + com_health + com_hunger + com_predator +
          com_reproduction + com_species + com_ai_state + com_pathfinding + com_age

Oak Tree: com_position + com_health + com_growth + com_seed_dispersal +
          com_resource(wood=10) + com_flammable + com_plant_species + com_age

Hut:      com_position + com_building(HUT_LARGE) + com_production + com_garrison +
          com_health + com_tribe
```

---

## 9. Building System

### Building Stats

| Building | Size | Wood | Build Time | HP | Function |
|---|---|---|---|---|---|
| Hut (Lv1/2/3) | 2×2 / 2×2 / 3×3 | 3/5/7 | 10/15/20s | 100/150/200 | Houses 3/4/5 Braves, breeds Braves |
| Guard Tower | 1×1 | 3 | 12s | 150 | Garrison 1 unit, extends range |
| Warrior Training | 3×3 | 5 | 15s | 120 | Brave → Warrior (8s) |
| Temple of Fire | 3×3 | 5 | 15s | 120 | Brave → Firewarrior (10s) |
| Temple | 3×3 | 5 | 15s | 120 | Brave → Preacher (10s) |
| Spy Training | 2×2 | 4 | 12s | 100 | Brave → Spy (12s) |
| Boat House | 3×2 | 5 | 15s | 100 | Produces boats (coastal) |
| Balloon Hut | 3×3 | 6 | 18s | 100 | Produces balloons |
| Circle of Reincarnation | 2×2 | 0 | 5s | 200 | Shaman respawn point |

### Hut Breeding Mechanics (from Populous constant.dat)

```
Base breeding time (game ticks):
  Level 1 (Small)  = 4000 ticks
  Level 2 (Medium) = 3000 ticks
  Level 3 (Large)  = 2000 ticks

Occupant speed multiplier = n * 0.5 + 0.5
  0 occupants = 0.5× (empty huts STILL breed, just slower)
  1 occupant  = 1.0×
  2 occupants = 1.5×
  3 occupants = 2.0×
  5 occupants = 3.0× (max in Large Hut)

Population penalty bands (slows breeding as tribe grows):
  Pop 0-4   → +30 ticks
  Pop 5-9   → +35 ticks
  Pop 10-14 → +40 ticks
  Pop 15-19 → +45 ticks
  ... (+5 per 5-pop band)

effective_breed_time = base_ticks / occupant_multiplier + pop_penalty
```

Hut auto-upgrades when ≥3 wood piles are deposited at the entrance AND at least one follower is inside.

### Construction Flow

```
1. Brave finds flat terrain of required size
2. Places construction ghost (entity with com_construction)
3. Walks to site, deposits wood, works
4. progress += num_builders * build_speed * delta
5. progress >= 1.0 → building complete → add com_building + com_production/com_garrison
```

---

## 10. Spell & Mana System

### Mana Flow (Exact Populous Formulas)

Mana is generated per-follower, not per-hut. Different unit types generate at different rates:

```
Mana Rates (per minute, from Populous wiki):
  Shaman        = 66.6 mana/min  (1.11 mana/sec)
  Brave (housed)= 34.6 mana/min  (0.577 mana/sec)
  Other units   = 11.3 mana/min  (0.188 mana/sec)
  (Warrior, Firewarrior, Preacher, Spy)

Total tribe mana income = sum of all followers' individual rates
```

**Mana Splitting**:
- If both spell charging AND training are active: mana splits **50/50** between them.
- If only one is active: **100%** goes to that one.
- If **neither** is active: **mana is wasted** (lost). This is a key strategic consideration.

**Spell Charges**:
```
Each spell has a mana_cost_per_charge.
When accumulated mana >= cost → +1 charge (up to max_charges).
Casting consumes 1 charge.
One-shot spells (from Stone Heads/Obelisks) have no charge cost.
```

### Complete Spell List (26 Spells)

**Terrain**: Raise(5), Lower(5), Hill(8), Valley(8), Flatten(10), Landbridge(20), Erode(15)

**Offensive**: Blast(8), Lightning(25), Tornado(40), Swamp(20), Firestorm(60), Earthquake(50), Volcano(80), Angel of Death(100)

**Support**: Convert(15), Ghost Army(30), Invisibility(20), Magical Shield(30), Hypnotise(15), Bloodlust(25), Teleport(15), Swarm(15)

**Guest/Special**: Burn, Forge World, Trees, Wildmen, Armageddon

Numbers in parentheses = mana cost.

### Terrain Spell Effect Processing

```
1. sys_spell_casting validates charges + range + target
2. Creates SpellEffect entity with com_spell_effect
3. sys_spell_effect processes: FLATTEN → avg height, VOLCANO → cone + lava, etc.
4. sys_terrain_manipulation writes height changes to TorusGrid
5. sys_terrain_render updates mesh
6. sys_construction checks buildings on now-uneven ground → destroy
```

---

## 11. Tribal AI System

### Strategic States

```
EARLY_GAME (pop<20):  Build huts, harvest, Convert wildmen
MID_GAME (pop 20-80): Train army, build Guard Towers, learn spells
LATE_GAME (pop>80):   Mass assault on weakest enemy
UNDER_ATTACK:         Rally defense, Shaman casts defensive spells
WINNING:              Overwhelming force or Armageddon
```

### Brave AI State Machine

```
IDLE → (trees nearby?) → HARVESTING
IDLE → (flat land, no hut?) → PLANNING_BUILD
IDLE → (hut with space?) → ENTERING_HUT
HARVESTING → chop tree → get wood → BUILDING
BUILDING → contribute wood+labor → complete → IDLE
ENTERING_HUT → housed → generate mana → (exit when ordered/destroyed)
FOLLOWING_ORDER → execute player command → IDLE
```

---

## 12. Fauna Ecosystem

### Species (6 initial)

| Species | Diet | HP | Speed | Biomes | Social |
|---|---|---|---|---|---|
| Deer | Herbivore | 30 | 4.0 | Grassland, Temperate Forest | Herd (3-8) |
| Wolf | Carnivore | 50 | 5.0 | Temperate Forest, Taiga | Pack (2-5) |
| Rabbit | Herbivore | 10 | 5.5 | Grassland, Temperate Forest | Group (2-6) |
| Bear | Omnivore | 100 | 3.5 | Temperate/Boreal Forest | Solitary |
| Eagle | Carnivore | 20 | 8.0 | Mountain, Grassland | Solitary, Flying |
| Fish | Herbivore | 5 | 3.0 | Ocean | School (5-20) |
| Bison | Herbivore | 80 | 3.0 | Grassland, Steppe | Herd (5-15) |

### Fauna AI States

```
IDLE → FORAGING (hunger>50%) → eat → IDLE
     → FLEEING (predator detected, prey only)
     → HUNTING (predator, prey found) → attack → eat → IDLE
     → MATING (mature + cooldown) → gestation → spawn offspring
     → MIGRATING (bad biome conditions) → path to better biome
     → SLEEPING (night, schedule-based)
     → DYING (HP≤0 or age≥max or starved)
```

### Predator-Prey Dynamics (Lotka-Volterra Inspired)

Natural equilibrium emerges: too many predators → prey drops → predators starve → predator drops → prey recovers. Biome fertility = carrying capacity for herbivores.

---

## 13. Flora Ecosystem

### Species (6 initial)

| Species | Type | Biomes | Wood | Growth | Max Age | Seed Method |
|---|---|---|---|---|---|---|
| Oak | Tree | Temperate, Grassland | 10 | 0.01/s | 500 | Wind |
| Pine | Tree | Taiga, Boreal, Mountain | 8 | 0.008/s | 600 | Wind |
| Tropical Palm | Tree | Tropical, Savanna | 6 | 0.015/s | 300 | Animal |
| Berry Bush | Bush | Temperate, Grassland | 0 | 0.02/s | 200 | Animal |
| Cactus | Bush | Desert | 0 | 0.005/s | 400 | — |
| Reed | Aquatic | Swamp | 0 | 0.03/s | 100 | Water |

### Growth Stages

`seed → sapling → young → mature → old → dead`

Each tick: check survival conditions (biome, water, light) → advance growth → seed dispersal (if mature) → fire response.

### Seed Dispersal

- **Wind**: Random offset within range, biased by wind direction
- **Water**: Downstream along water flow
- **Animal**: Deposited when herbivore eats and moves to new location

---

## 14. Weather System

### Weather State Machine

```
CLEAR (60% base) → CLOUDY → RAIN/SNOW → STORM → CLEAR
                                ↑                    |
                                └────────────────────┘

Transitions influenced by: season, biome temperature, moisture, randomness
Storm duration: 30-120 game seconds
```

### Weather Effects

| Weather | Effect |
|---|---|
| **Rain** | +moisture on tiles, extinguishes fire, grows vegetation, floods low areas |
| **Snow** | Slows movement, increases building decay, accumulates on cold tiles |
| **Storm** | Lightning strikes (random fire/damage), heavy rain, wind speed spike |
| **Wind** | Affects cloud movement, fire spread direction, balloon travel, seed dispersal |
| **Fog** | Reduces visibility range for all units |
| **Heat Wave** | Increases fire risk, reduces stamina in hot/dry biomes |

---

## 15. Time System

### Game Clock

```
1 real second = 1 game minute (configurable via time_scale)
24 game minutes = 1 game day
4 game days = 1 game season (Spring → Summer → Autumn → Winter)
16 game days = 1 game year
```

### Day/Night Effects

| Period | Light | Unit Behavior | Fauna | Flora |
|---|---|---|---|---|
| Dawn (5-7) | Rising | Wake up | Wake, start foraging | — |
| Day (7-18) | Full | Full activity | Active | Photosynthesis active |
| Dusk (18-20) | Setting | Return to huts | Return to dens | — |
| Night (20-5) | Dark | Sleep (reduced awareness) | Nocturnal predators active | Growth slowed |

### Seasonal Effects

| Season | Temperature | Moisture | Flora | Fauna |
|---|---|---|---|---|
| Spring | Rising | High | Fast growth, seeds sprout | Breeding season |
| Summer | Peak | Medium | Full growth, fruiting | Peak activity |
| Autumn | Falling | Medium | Leaves fall, dormancy begins | Migration triggers |
| Winter | Low | Low (snow) | Dormant, no growth | Reduced activity, hibernation |

---

## 16. Camera & Rendering

### Orbital Camera

```
Controls:
  - WASD/Arrow: Pan across planet surface
  - Mouse wheel: Zoom (globe ↔ close-up, continuous)
  - Middle mouse drag: Rotate view
  - Q/E: Rotate around vertical axis

Zoom levels:
  0.0 = Full globe view (sphere projection, simplified)
  0.5 = Mid view (curved terrain, some detail)
  1.0 = Close-up (near-flat, full detail)
```

### Placeholder Rendering

All visuals are procedural (no sprites/imported assets):

| Entity | Placeholder Visual |
|---|---|
| Terrain | Colored mesh (biome-based vertex colors or shader) |
| Water | Blue semi-transparent plane with simple wave shader |
| Brave | Small colored capsule + text label |
| Warrior | Larger colored capsule + text label |
| Shaman | Capsule with glow effect + text label |
| Hut | Colored box (size varies) |
| Guard Tower | Tall thin box |
| Tree | Green cone on brown cylinder |
| Bush | Small green sphere |
| Deer | Brown ellipsoid |
| Wolf | Gray ellipsoid |

---

## 17. Pathfinding

### A* on Torus Grid

Standard A* with wrapping distance heuristic:

```gdscript
func heuristic(a: Vector2i, b: Vector2i) -> float:
    var dx = min(abs(a.x - b.x), grid_width - abs(a.x - b.x))
    var dy = min(abs(a.y - b.y), grid_height - abs(a.y - b.y))
    return sqrt(dx * dx + dy * dy)
```

Movement cost modifiers: biome type, slope (height difference), water (impassable for land units), buildings (impassable).

### Flow Fields

For large armies moving to same target, use **flow field** instead of per-unit A*: compute distance field from target, each unit follows gradient. Much cheaper for 50+ units.

---

## 18. Event System

Decoupled inter-system communication via event bus:

```
Events:
  ENTITY_DIED(entity_id)
  BUILDING_COMPLETED(building_id, tribe_id)
  SPELL_CAST(spell_type, caster_id, target_pos)
  TERRAIN_CHANGED(tile_x, tile_y, new_height)
  WEATHER_CHANGED(old_state, new_state)
  SEASON_CHANGED(new_season)
  TRIBE_ELIMINATED(tribe_id)
  FAUNA_BORN(species, position)
  FLORA_GROWN(species, position, new_stage)
  FIRE_STARTED(position)
  FIRE_EXTINGUISHED(position)
```

Systems emit events; other systems subscribe. No direct system-to-system coupling.

---

## 19. Performance Considerations

### Entity Budget

| Entity Type | Expected Count | ECS Strategy |
|---|---|---|
| Tiles | 16,384 (128×128) | Stored in flat arrays, not individual ECS entities |
| Followers (all tribes) | 200-800 | Full ECS entities |
| Fauna | 100-500 | Full ECS entities |
| Flora (trees) | 500-2000 | Full ECS entities |
| Flora (grass/ground) | 16,384 | Tile data, not entities |
| Active spell effects | 0-20 | Temporary ECS entities |
| Buildings | 50-200 | Full ECS entities |

### Optimization Strategies

- **Tiles as flat arrays**: Not ECS entities. Accessed by index.
- **Spatial hashing**: For neighbor queries (combat range, predator detection).
- **LOD for fauna/flora**: Distant entities skip AI ticks (reduced update frequency).
- **System LOD**: Heavy systems (weather, flora growth) can skip ticks for distant entities.
- **Shader-based terrain**: Heightmap → mesh done in GPU vertex shader.
- **Flow fields**: Reuse pathfinding for groups instead of per-unit A*.

---

*For the implementation roadmap, see [PLAN.md](PLAN.md).*
*For detailed system implementations, see [DOCS_SYSTEMS.md](DOCS_SYSTEMS.md).*
*For project overview, see [README.md](README.md).*

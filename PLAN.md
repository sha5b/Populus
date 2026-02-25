# Populus — Implementation Plan (v2)

> Precise, phased roadmap. **World-first**: the entire planet must live, breathe, and simulate autonomously before any player interaction is added. Player controls (except debug camera) come last.

---

## Design Philosophy

1. **World-First** — Every system is built to run autonomously. Tribes, fauna, flora, weather all operate without a human player. The player is an observer until the world proves it can sustain itself.
2. **Own Lightweight ECS** — We roll our own ECS inspired by the Godot-ECS-Starter pattern (`Component extends Resource`, `System.update(world, delta)`, `World.query()`). No external dependency. Simple, debuggable, extensible.
3. **Generic Folder Structure** — Every file's purpose is obvious from its path alone. The project can grow to 200+ systems without confusion.
4. **Incremental Verification** — Each phase ends with a concrete, observable test. If the test fails, the phase isn't done.

---

## Overview

### Estimated Phases: 14
### Estimated Total Duration: 20-30 weeks

```
PART A — FOUNDATION (the planet exists, you can look at it)
  Phase 0:  Project Setup, ECS Core, Folder Scaffold ........... Week 1
  Phase 1:  Torus Grid & Heightmap Data ....................... Week 1-2
  Phase 2:  Sphere Projection & Terrain Mesh .................. Week 2-3
  Phase 3:  Procedural Terrain Generation ..................... Week 3-4
  Phase 4:  Biome Assignment & Rendering ...................... Week 4-5
  Phase 5:  Debug Camera (orbit, zoom, pan) ................... Week 5

PART B — NATURE LIVES (no humans yet, planet ecology runs itself)
  Phase 6:  Time System (clock, day/night, seasons) ........... Week 5-6
  Phase 7:  Weather System (rain, wind, storms) ............... Week 6-7
  Phase 8:  Flora System (trees grow, spread seeds, burn) ..... Week 7-9
  Phase 9:  Fauna System (animals eat, hunt, flee, breed) ..... Week 9-12

PART C — CIVILIZATION LIVES (tribes run themselves, no player tribe)
  Phase 10: Tribes, Followers & Autonomous Settlement ......... Week 12-16
  Phase 11: Buildings, Mana, Population & Training ............ Week 16-19
  Phase 12: Spells, Terrain Manipulation & Combat ............. Week 19-23

PART D — PLAYER ENTERS (now the human can interact)
  Phase 13: Player Tribe, Input, UI, Save/Load ............... Week 23-28
```

---

## Folder Structure

This is the single most important design decision for long-term maintainability. Every file must be findable by path alone. The naming convention is: **`snake_case`, domain prefix in folder name, purpose suffix in file name**.

```
populus/
│
├── project.godot
├── README.md
├── DOCS.md
├── DOCS_SYSTEMS.md
├── PLAN.md                                    # ← this file
│
├── ecs/                                       # ─── ECS CORE (never changes) ───
│   ├── entity.gd                              # Entity = just an int ID
│   ├── component.gd                           # Base class: extends Resource, get_type()
│   ├── system.gd                              # Base class: update(world, delta)
│   └── world.gd                               # Entity store, component store, query(), system runner
│
├── components/                                # ─── ALL COMPONENTS (pure data, one file = one component) ───
│   │
│   ├── com_position.gd                        # grid_x, grid_y, world_pos
│   ├── com_velocity.gd                        # direction, speed
│   ├── com_health.gd                          # max_hp, current_hp, regen
│   ├── com_age.gd                             # age, max_age
│   │
│   ├── com_tile.gd                            # grid coords, is_flat, is_water, occupant
│   ├── com_heightmap.gd                       # corner heights for a tile
│   ├── com_biome.gd                           # biome_type, temperature, moisture, fertility
│   │
│   ├── com_tribe.gd                           # tribe_id, tribe_color
│   ├── com_role.gd                            # role_type enum (Brave, Warrior, etc.)
│   ├── com_inventory.gd                       # wood count, carried items
│   ├── com_combat.gd                          # attack_damage, range, speed, armor
│   ├── com_conversion.gd                      # power, range, progress dict
│   ├── com_disguise.gd                        # spy disguise state
│   │
│   ├── com_ai_state.gd                        # current_state, previous_state, timer
│   ├── com_task.gd                            # task_type, target_pos, target_entity
│   ├── com_pathfinding.gd                     # path array, path_index, is_pathing
│   ├── com_need.gd                            # hunger, rest, safety (for fauna/units)
│   │
│   ├── com_building.gd                        # building_type, tribe_id, size
│   ├── com_construction.gd                    # progress, required_wood, builders
│   ├── com_production.gd                      # what it produces, timer, interval
│   ├── com_garrison.gd                        # max_occupants, occupant list, range_bonus
│   │
│   ├── com_spell_caster.gd                    # known_spells, active_spell, cast_timer
│   ├── com_mana.gd                            # current, max, regen_rate (per tribe)
│   ├── com_spell_effect.gd                    # type, pos, radius, duration, timer
│   ├── com_spell_charge.gd                    # type, charges, max, recharge timer
│   │
│   ├── com_species.gd                         # name, diet, preferred biomes (fauna)
│   ├── com_predator.gd                        # prey_types, hunt_range, damage
│   ├── com_prey.gd                            # flee_bonus, awareness_range
│   ├── com_herd.gd                            # herd_id, separation, cohesion
│   ├── com_reproduction.gd                    # maturity, gestation, offspring
│   ├── com_migration.gd                       # preferred_biome, threshold, target
│   ├── com_hunger.gd                          # current, max, rates
│   │
│   ├── com_plant_species.gd                   # name, biomes, water/light need
│   ├── com_growth.gd                          # stage, rate, age, max_age
│   ├── com_seed_dispersal.gd                  # method, range, timer
│   ├── com_resource.gd                        # wood_yield, food_yield, harvestable
│   ├── com_flammable.gd                       # flammability, is_burning, burn_timer
│   │
│   ├── com_temperature.gd                     # value, base_value (per tile weather)
│   ├── com_moisture.gd                        # value, base_value
│   ├── com_wind.gd                            # direction, speed
│   └── com_schedule.gd                        # wake_hour, sleep_hour, is_active
│
├── systems/                                   # ─── ALL SYSTEMS (pure logic, one file = one system) ───
│   │
│   │  # ── PART A: Foundation ──
│   ├── sys_terrain_generation.gd              # one-shot: noise → heightmap
│   ├── sys_terrain_render.gd                  # heightmap → mesh update
│   ├── sys_water_render.gd                    # water plane at sea level
│   ├── sys_biome_assignment.gd                # temp + moisture + altitude → biome
│   ├── sys_biome_render.gd                    # biome → vertex colors / shader
│   │
│   │  # ── PART B: Nature ──
│   ├── sys_time.gd                            # advance game clock, emit hour/day/season
│   ├── sys_day_night.gd                       # light changes, toggle schedules
│   ├── sys_season.gd                          # modify temp/moisture per season
│   ├── sys_weather.gd                         # state machine: clear/cloudy/rain/storm
│   ├── sys_wind.gd                            # wind direction/speed drift
│   ├── sys_precipitation.gd                   # rain → moisture, snow → slow
│   │
│   ├── sys_flora_spawning.gd                  # one-shot: initial plants per biome
│   ├── sys_flora_growth.gd                    # age, stage advance, death
│   ├── sys_seed_dispersal.gd                  # wind/water/animal seed spread
│   ├── sys_fire_spread.gd                     # fire propagation, extinguish
│   │
│   ├── sys_fauna_spawning.gd                  # one-shot: initial animals per biome
│   ├── sys_fauna_ai.gd                        # master state machine per animal
│   ├── sys_hunger.gd                          # hunger tick, starvation damage
│   ├── sys_predator_prey.gd                   # hunt/flee resolution
│   ├── sys_herd.gd                            # boids flocking
│   ├── sys_reproduction.gd                    # mating, gestation, offspring
│   ├── sys_migration.gd                       # seasonal biome migration
│   │
│   │  # ── PART C: Civilization ──
│   ├── sys_settlement_spawning.gd             # one-shot: place tribes on map
│   ├── sys_brave_ai.gd                        # auto-harvest, auto-build, auto-house
│   ├── sys_wildmen_ai.gd                      # wander near trees/water
│   ├── sys_tribal_ai.gd                       # strategic: expand/build army/attack/defend
│   ├── sys_shaman_ai.gd                       # spell selection, targeting
│   ├── sys_warrior_ai.gd                      # patrol, engage, guard
│   │
│   ├── sys_pathfinding.gd                     # A* on torus grid
│   ├── sys_movement.gd                        # move entities along paths
│   │
│   ├── sys_construction.gd                    # building progress, completion
│   ├── sys_production.gd                      # huts spawn braves, training converts
│   ├── sys_garrison.gd                        # enter/exit, range bonus
│   │
│   ├── sys_mana.gd                            # housed followers → mana pool → charges
│   ├── sys_population.gd                      # brave spawning, pop cap
│   ├── sys_conversion.gd                      # preacher aura tick
│   │
│   ├── sys_spell_casting.gd                   # validate, consume charge, create effect
│   ├── sys_spell_effect.gd                    # process each spell type
│   ├── sys_terrain_manipulation.gd            # height changes from spells → grid
│   │
│   ├── sys_combat.gd                          # melee/ranged attack resolution
│   ├── sys_damage.gd                          # apply damage, armor, knockback
│   ├── sys_death.gd                           # remove dead, shaman reincarnation
│   │
│   │  # ── PART D: Player ──
│   ├── sys_player_input.gd                    # click select, right-click orders
│   ├── sys_camera_input.gd                    # debug/player camera control
│   └── sys_ui_render.gd                       # HUD, minimap, spell panel
│
├── data/                                      # ─── STATIC DEFINITIONS (readonly config) ───
│   ├── def_biomes.gd                          # BiomeType enum + per-biome data dict
│   ├── def_units.gd                           # RoleType enum + per-role stats dict
│   ├── def_buildings.gd                       # BuildingType enum + per-building stats dict
│   ├── def_spells.gd                          # SpellType enum + per-spell stats dict
│   ├── def_fauna.gd                           # species name → stats dict
│   ├── def_flora.gd                           # species name → stats dict
│   └── def_enums.gd                           # shared enums (AIState, TaskType, Season, etc.)
│
├── planet/                                    # ─── PLANET GEOMETRY (not ECS, pure math/rendering) ───
│   ├── torus_grid.gd                          # 2D wrapping grid data structure
│   ├── sphere_projector.gd                    # grid coords ↔ 3D sphere position
│   ├── planet_mesh.gd                         # ArrayMesh generation from heightmap
│   └── planet_camera.gd                       # orbital camera (debug + player)
│
├── generation/                                # ─── PROCEDURAL GENERATION (one-shot helpers) ───
│   ├── gen_heightmap.gd                       # noise → heightmap
│   ├── gen_biome.gd                           # temp + moisture → biome map
│   ├── gen_flora.gd                           # place initial trees/bushes
│   ├── gen_fauna.gd                           # place initial animals
│   └── gen_settlement.gd                      # place initial tribes
│
├── shaders/                                   # ─── GPU SHADERS ───
│   ├── terrain.gdshader                       # height-based coloring, biome blending
│   ├── water.gdshader                         # animated water plane
│   └── sky.gdshader                           # simple sky gradient
│
├── scenes/                                    # ─── GODOT SCENES ───
│   └── main.tscn                              # root scene
│
├── config/                                    # ─── RUNTIME CONFIGURATION ───
│   └── game_config.gd                         # autoload: grid size, time scale, all tuning knobs
│
└── debug/                                     # ─── DEBUG TOOLS ───
    ├── debug_overlay.gd                       # F3 toggle: FPS, entity count, tile info
    └── debug_commands.gd                      # console commands: spawn, kill, set weather, etc.
```

### Naming Conventions

| Kind | Prefix | Example | Why |
|---|---|---|---|
| **Component** | `com_` | `com_health.gd` | Instantly know it's pure data |
| **System** | `sys_` | `sys_combat.gd` | Instantly know it's pure logic |
| **Definition** | `def_` | `def_spells.gd` | Instantly know it's static config |
| **Generator** | `gen_` | `gen_heightmap.gd` | Instantly know it's one-shot generation |
| **ECS Core** | none | `world.gd` | Framework layer, never touched |

### Rules

1. **Flat components/ folder** — no subfolders. When you have 60 components, you `Ctrl+P` and type `com_health` — done. Subfolders add navigation friction.
2. **Flat systems/ folder** — same logic. The `sys_` prefix + descriptive name is enough.
3. **One file = one class** — never two classes in one file.
4. **Alphabetical sorting works** — `sys_brave_ai` is near `sys_building`, `com_combat` is near `com_construction`. The prefix groups things naturally.

---

## ECS Core Design

We build our own lightweight ECS based on the pattern from the reference Godot-ECS-Starter project. No external dependencies.

### `ecs/entity.gd`
```gdscript
extends Resource
class_name Entity
var id: int
func _init(_id: int): id = _id
```

### `ecs/component.gd`
```gdscript
extends Resource
class_name Component
func get_type() -> String: return "Component"
```

### `ecs/system.gd`
```gdscript
extends Resource
class_name System
func update(world, delta: float) -> void: pass
```

### `ecs/world.gd`
```gdscript
extends Node
class_name World

var _next_id: int = 1
var entities: Dictionary = {}       # id → Entity
var components: Dictionary = {}     # type_string → { id → Component }
var systems: Array[System] = []

func create_entity() -> Entity:
    var e = Entity.new(_next_id)
    entities[_next_id] = e
    _next_id += 1
    return e

func add_component(entity: Entity, component: Component) -> void:
    var t = component.get_type()
    if not components.has(t):
        components[t] = {}
    components[t][entity.id] = component

func get_component(entity_id: int, comp_type: String) -> Component:
    if components.has(comp_type) and components[comp_type].has(entity_id):
        return components[comp_type][entity_id]
    return null

func get_components(comp_type: String) -> Dictionary:
    return components.get(comp_type, {})

func query(required: Array[String]) -> Array[int]:
    if required.is_empty(): return []
    var base = get_components(required[0])
    var result: Array[int] = []
    for id in base.keys():
        var ok = true
        for i in range(1, required.size()):
            if not get_components(required[i]).has(id):
                ok = false
                break
        if ok:
            result.append(id)
    return result

func remove_entity(entity_id: int) -> void:
    entities.erase(entity_id)
    for comp_type in components.keys():
        components[comp_type].erase(entity_id)

func add_system(system: System) -> void:
    systems.append(system)

func _process(delta: float) -> void:
    for system in systems:
        system.update(self, delta)
```

**Key design choice**: No runners, no schedulers, no parallel mode. Systems execute in registration order. That's it. If we need phase grouping later, we create multiple World instances (one per phase) or a simple phase tag. KISS.

---

## Phase 0: Project Setup, ECS Core, Folder Scaffold

**Goal**: Empty project runs, ECS framework works, all folders exist, one test system prints to console.

### Tasks

- [x] **0.1** Create every folder in the structure above (empty `.gdkeep` files where needed)
- [x] **0.2** Create the 4 ECS core files: `ecs/entity.gd`, `ecs/component.gd`, `ecs/system.gd`, `ecs/world.gd`
- [x] **0.3** Create `config/game_config.gd` as Autoload singleton
  ```
  GRID_WIDTH = 128
  GRID_HEIGHT = 128
  SEA_LEVEL = 0.0
  TIME_SCALE = 60.0        # 1 real sec = 60 game sec
  MAX_POPULATION = 200
  WORLD_SEED = 0           # 0 = random
  ```
- [x] **0.4** Create `data/def_enums.gd` with all enums (BiomeType, RoleType, BuildingType, SpellType, AIState, TaskType, GrowthStage, DietType, Season, WeatherState, etc.)
- [x] **0.5** Create `scenes/main.tscn` + `main.gd` that instantiates World, registers a dummy test system
- [x] **0.6** Create a `sys_test.gd` system that prints "Tick" once per second to verify ECS loop works
- [x] **0.7** Verify: entity creation, component attachment, `world.query()` returns correct IDs

### Verification
```
Console output on run:
  "World created. 0 entities."
  "Test system tick at 0.0s"
  "Test system tick at 1.0s"
  ...
```

---

## Phase 1: Torus Grid & Heightmap Data

**Goal**: The TorusGrid data structure works perfectly — wrapping, height read/write, flatness checks.

### Tasks

- [x] **1.1** Create `planet/torus_grid.gd`
  - `PackedFloat32Array` of size `(width+1) * (height+1)` for vertex heights (vertices, not tiles — there are width+1 vertices per row, but they wrap, so index with modulo)
  - `get_height(x, y) -> float` with wrapping
  - `set_height(x, y, h)` with wrapping
  - `wrap_x(x) -> int`, `wrap_y(y) -> int`
  - `get_tile_center_height(tx, ty) -> float` (average of 4 corners)
  - `is_flat(tx, ty, tolerance) -> bool` (max corner difference < tolerance)
  - `is_underwater(tx, ty) -> bool` (center height < sea_level)
  - `get_neighbors_4(tx, ty) -> Array[Vector2i]` (N/S/E/W wrapped)
  - `get_neighbors_8(tx, ty) -> Array[Vector2i]` (+ diagonals)
  - `torus_distance(a: Vector2i, b: Vector2i) -> float` (shortest wrapped distance)
  - `fill_circle(cx, cy, radius, height_delta)` — raise/lower circular area
  - `flatten_area(cx, cy, radius)` — set all vertices in circle to average

- [x] **1.2** Write tests in `debug/test_torus_grid.gd`
  - Wrap: `get_height(-1, 0)` == `get_height(width-1, 0)`
  - Wrap: `get_height(width, 0)` == `get_height(0, 0)`
  - `torus_distance(Vector2i(0,0), Vector2i(127,0))` == 1.0 (for 128-width grid)
  - `is_flat` returns true for uniform heights
  - `fill_circle` modifies correct vertices
  - `flatten_area` produces uniform height

### Verification
```
All tests pass in console output.
```

---

## Phase 2: Sphere Projection & Terrain Mesh

**Goal**: The torus grid renders as a 3D sphere you can see in the viewport.

### Tasks

- [x] **2.1** Create `planet/sphere_projector.gd`
  - `grid_to_sphere(gx: float, gy: float, height: float, radius: float) -> Vector3`
    ```
    lon = (gx / width) * TAU
    lat = (gy / height) * PI - PI/2
    r = radius + height * HEIGHT_SCALE
    return Vector3(r * cos(lat) * cos(lon), r * sin(lat), r * cos(lat) * sin(lon))
    ```
  - `sphere_to_grid(world_pos: Vector3) -> Vector2i` (inverse for raycasting)
  - `get_sphere_normal(gx, gy) -> Vector3` (normalize sphere position)

- [x] **2.2** Create `planet/planet_mesh.gd` (extends `MeshInstance3D`)
  - `build_mesh(grid: TorusGrid, projector: SphereProjector)` — creates `ArrayMesh`
  - Each tile → 2 triangles (4 vertices, 6 indices)
  - Vertex positions from `grid_to_sphere()`
  - Vertex colors from height (blue < sea, green, brown, white)
  - UV from grid coords (u = gx/width, v = gy/height)
  - `update_region(cx, cy, radius)` — rebuild only affected triangles

- [x] **2.3** Create `shaders/terrain.gdshader`
  - Fragment: use vertex color for now (height-based)
  - Later phases will add biome blending

- [x] **2.4** Create `shaders/water.gdshader`
  - Transparent blue sphere at sea_level radius
  - Simple sine-wave vertex displacement for waves

- [x] **2.5** Create `sys_terrain_render.gd` (handled in main.gd for now) — a system that calls `planet_mesh.build_mesh()` once, and `update_region()` when terrain changes
- [x] **2.6** Create `sys_water_render.gd` (handled in main.gd for now) — creates water sphere mesh

### Verification
```
A colored 3D sphere appears in the viewport. All heights are 0 → smooth sphere.
Manually set some heights in code → visible bumps on the sphere.
No seams at the grid wrap boundary.
```

---

## Phase 3: Procedural Terrain Generation

**Goal**: Each run generates a unique planet with continents, oceans, mountains, and varied terrain.

### Tasks

- [x] **3.1** Create `gen_heightmap.gd`
  - Uses `FastNoiseLite` (Godot built-in)
  - **Continental layer**: OpenSimplex2, FBM, freq=0.015, octaves=6, lacunarity=2.0, gain=0.5
  - **Detail layer**: OpenSimplex2, FBM, freq=0.08, octaves=4, weight=0.3
  - **Combine**: `h = continental + detail * 0.3`
  - **Normalize**: shift/scale so ~45% of tiles are below sea level (adjustable)
  - **Seed**: from `GameConfig.WORLD_SEED` (0 = random)

- [x] **3.2** Create `gen_biome.gd` (data prep, not rendering yet)
  - **Temperature map**: base from latitude (`gy/height` → equator hot, poles cold) + altitude cooling (`-height * 0.3`) + noise variation (freq=0.03, weight=0.15)
  - **Moisture map**: BFS flood fill from water tiles (distance-based falloff) + noise variation + simple prevailing wind bias (east→west moisture transport)
  - Store per-tile: `temperature: float`, `moisture: float`

- [x] **3.3** Register as one-shot: in `main.gd`, call generation before starting the ECS loop

### Verification
```
Each run: different continent shapes (or same with fixed seed).
Console prints: "Generated heightmap. Land: 47%, Water: 53%"
Sphere shows varied terrain with oceans, hills, mountains.
```

---

## Phase 4: Biome Assignment & Rendering

**Goal**: Every tile has a biome. The planet is color-coded by biome.

### Tasks

- [x] **4.1** Create `data/def_biomes.gd`
  - BiomeType enum: OCEAN, BEACH, TROPICAL_FOREST, DESERT, SAVANNA, TEMPERATE_FOREST, GRASSLAND, STEPPE, TUNDRA, TAIGA, BOREAL_FOREST, MOUNTAIN, SNOW_ICE, SWAMP
  - Per biome: `color`, `tree_density`, `fauna_density`, `movement_cost`, `fertility`, `flammability`

- [x] **4.2** Create `generation/gen_biome_assignment.gd` (static Whittaker classifier)
  - One-shot system: for each tile, look up `(temperature, moisture, altitude) → BiomeType` using Whittaker thresholds
  - Override rules: altitude > mountain_threshold → MOUNTAIN, very_high + cold → SNOW_ICE, very_low + wet → SWAMP, underwater → OCEAN, adjacent to ocean + low → BEACH

- [x] **4.3** Biome rendering via `planet_mesh._get_tile_color()` using biome_map
  - Update vertex colors on planet mesh based on biome color
  - Smooth blending at biome borders (average neighbor colors)

- [x] **4.4** Terrain shader uses vertex colors (biome-driven)

### Verification
```
Planet shows: green forests, yellow deserts, white snow caps, blue oceans,
brown mountains, dark green tropics. No desert at poles. No snow at equator.
Biome distribution looks geographically plausible.
```

---

## Phase 5: Debug Camera

**Goal**: Orbit camera lets you inspect the whole planet — zoom from globe to close-up, pan, rotate.

### Tasks

- [x] **5.1** Create `planet/planet_camera.gd` (extends Camera3D)
  - **Orbit**: camera always looks at a point on the sphere surface
  - **Zoom**: scroll wheel changes distance. Min = close (5 units above surface), Max = far (see whole globe)
  - **Pan**: WASD moves the look-at point across the sphere surface (in grid coordinates, wrapped)
  - **Rotate**: Q/E or middle-mouse rotates around the look-at vector
  - **Smooth**: all transitions lerp'd

- [x] **5.2** Camera input handled in `planet_camera.gd` directly — reads input, updates camera
- [ ] **5.3** Grid-to-screen picking (deferred): click on sphere → determine which tile → print tile info to console (height, biome, temperature, moisture)

### Verification
```
WASD pans across the planet. Scroll zooms. Q/E rotates.
At max zoom-out: see the full globe.
At max zoom-in: see individual tiles with biome colors.
Click a tile → console prints: "Tile (45, 67): height=0.34, biome=GRASSLAND, temp=0.6, moisture=0.4"
```

---

## Phase 6: Time System

**Goal**: A game clock ticks. Day/night cycle changes lighting. Seasons rotate.

### Tasks

- [x] **6.1** Create `sys_time.gd`
  - `game_time += delta * GameConfig.TIME_SCALE`
  - Track: `hour` (0-23), `day` (0+), `season` (SPRING/SUMMER/AUTUMN/WINTER), `year`
  - Emit signals or set globals: `EventBus.hour_changed`, `EventBus.day_changed`, `EventBus.season_changed`
  - Config: 24 hours = 1 day, 7 days = 1 season, 28 days = 1 year

- [x] **6.2** Day/night handled in `sys_time.gd` (sun rotation + color by hour)
  - Adjust DirectionalLight3D color and intensity by hour
  - Dawn (5-7): warm orange, rising
  - Day (7-18): bright white
  - Dusk (18-20): warm orange, falling
  - Night (20-5): dark blue, dim

- [x] **6.3** Create `sys_season.gd`
  - Modify global temperature offset by season: Spring=+0, Summer=+0.15, Autumn=-0.05, Winter=-0.2
  - Modify global moisture offset: Spring=+0.1, Summer=0, Autumn=0, Winter=-0.1

- [x] **6.4** Debug HUD in main.gd showing: `Day 3, 14:00, Summer, Year 1 | FPS | Entities`

### Verification
```
The lighting smoothly cycles from day to night and back.
Seasons advance every 7 game days.
Debug HUD shows correct time.
Console: "Season changed: SPRING → SUMMER"
```

---

## Phase 7: Weather System

**Goal**: Weather changes autonomously. Rain makes things wet. Storms produce lightning. Wind blows.

### Tasks

- [x] **7.1** Create `sys_weather.gd`
  - Global weather state machine: CLEAR → CLOUDY → RAIN → STORM → CLEARING → CLEAR
  - Transition check every 30-60 game seconds (randomized)
  - Transition probabilities vary by season (more rain in spring, more clear in summer)

- [x] **7.2** Create `sys_wind.gd`
  - Global wind direction (Vector2) and speed (float)
  - Slowly drifts over time with noise
  - Storms spike wind speed

- [x] **7.3** Create `sys_precipitation.gd`
  - RAIN state: increase tile moisture by `rain_rate * delta`
  - SNOW (rain + cold biome): same but flag tiles as snowy
  - STORM: same as rain but stronger + random lightning strikes on land tiles

- [x] **7.4** Lightning strike effect: pick random land tile, deal damage to any entity there, chance to start fire

- [x] **7.5** Debug HUD shows: `Clear | Wind: NE 1.2 m/s`

### Verification
```
Weather visibly changes over time (log messages for now, visual effects later).
During rain: tile moisture values increase (visible in click-to-inspect).
Lightning strikes printed: "Lightning strike at (45, 67)!"
Wind direction drifts smoothly.
```

---

## Phase 8: Flora System

**Goal**: Trees and bushes spawn, grow through life stages, spread seeds, catch fire, and die. All autonomous.

### Tasks

- [ ] **8.1** Create `data/def_flora.gd` — 6 species: oak, pine, tropical_palm, berry_bush, cactus, reed. Each with: preferred_biomes, growth_rate, max_age, wood_yield, seed_method, seed_range, seed_interval, water_need, light_need, flammability

- [ ] **8.2** Create components: `com_plant_species.gd`, `com_growth.gd`, `com_seed_dispersal.gd`, `com_resource.gd`, `com_flammable.gd`

- [ ] **8.3** Create `gen_flora.gd` — initial placement
  - For each land tile: roll against biome's `tree_density`
  - If hit: pick a random species valid for this biome → create entity at MATURE stage
  - Respect density caps (max N trees per biome region)

- [ ] **8.4** Create `sys_flora_growth.gd`
  - Each flora entity each tick:
    - `age += delta`
    - Check survival: is biome still suitable? Is moisture sufficient? → if not, `growth_rate *= 0.1`
    - Advance `growth_progress += growth_rate * fertility * delta`
    - Stage transitions: SEED(0-0.1) → SAPLING(0.1-0.3) → YOUNG(0.3-0.5) → MATURE(0.5-0.8) → OLD(0.8-1.0) → DEAD
    - At DEAD: schedule entity removal

- [ ] **8.5** Create `sys_seed_dispersal.gd`
  - Only MATURE and OLD plants disperse
  - Timer per plant; on trigger:
    - WIND: target = current_pos + random_offset(seed_range) biased by wind direction
    - WATER: target = random adjacent water-flow tile within range
    - ANIMAL: deferred — triggered by fauna eating (Phase 9 will hook in)
  - If target tile is land, not occupied, biome-compatible: spawn new SEED entity

- [ ] **8.6** Create `sys_fire_spread.gd`
  - Burning entities: `burn_timer -= delta`. When burn_timer reaches 0 → entity dies.
  - Each tick: burning entity checks neighbors within 1-2 tiles. If neighbor has `com_flammable` and `is_burning == false`: roll against `flammability * wind_factor`. If hit → ignite.
  - Rain extinguishes: if weather == RAIN and is_burning → `burn_timer += extinguish_rate * delta`
  - Debug command: `ignite(tile_x, tile_y)` to manually start a fire

- [ ] **8.7** Placeholder rendering:
  - SEED: tiny green dot
  - SAPLING: small green triangle (height = 0.3)
  - MATURE tree: green cone on brown cylinder (height = 1.0)
  - OLD tree: darker/smaller
  - BURNING: red/orange tint
  - Use MultiMeshInstance3D for performance

### Verification
```
Planet starts covered in biome-appropriate trees.
Speed up time → watch trees age from SEED → MATURE → DEAD.
New trees sprout from seed dispersal (count increases then stabilizes).
Debug ignite a tree → fire spreads to neighbors → burns out.
Rain extinguishes fire.
After 10 game years: forest has naturally regrown.
Population count of trees oscillates but doesn't explode or crash to zero.
```

---

## Phase 9: Fauna System

**Goal**: Animals roam, eat, hunt, flee, form herds, breed, migrate, and die. All autonomous.

### Tasks

- [ ] **9.1** Create `data/def_fauna.gd` — 7 species: deer, wolf, rabbit, bear, eagle, fish, bison. Full stats from DOCS.md.

- [ ] **9.2** Create components: `com_species.gd`, `com_hunger.gd`, `com_predator.gd`, `com_prey.gd`, `com_herd.gd`, `com_reproduction.gd`, `com_migration.gd`, `com_need.gd`

- [ ] **9.3** Create `gen_fauna.gd` — initial placement
  - Per biome region: spawn herds (herbivores) and solitary/packs (predators)
  - Fish only in water, eagles only on mountains/grassland
  - Respect density limits

- [ ] **9.4** Create `sys_fauna_ai.gd` — master state machine per animal
  - States: IDLE, FORAGING, HUNTING, FLEEING, MATING, SLEEPING, MIGRATING, DYING
  - Each state delegates to specific logic (see DOCS_SYSTEMS.md for full pseudocode)

- [ ] **9.5** Create `sys_hunger.gd`
  - `hunger += hunger_rate * delta` each tick for all fauna
  - Hunger > max → starvation damage: `health -= starvation_rate * delta`

- [ ] **9.6** Create `sys_predator_prey.gd`
  - Predators in HUNTING state: find nearest prey within hunt_range
  - Chase → in range → deal damage → prey dies → predator eats (hunger -= 60%)
  - Prey in FLEEING state: move away at flee_speed

- [ ] **9.7** Create `sys_herd.gd` — Boids flocking
  - Separation: steer away from nearby herd members
  - Cohesion: steer toward herd center
  - Alignment: match herd velocity
  - Applied as velocity modifier for herding animals in IDLE/FORAGING/WANDERING states

- [ ] **9.8** Create `sys_reproduction.gd`
  - Mature + cooldown expired + near mate → gestation timer starts
  - Gestation complete → spawn N offspring (SEED-stage equivalent for animals: small, hungry, near parent)
  - Hard cap per species per map prevents explosion

- [ ] **9.9** Create `sys_migration.gd`
  - Triggered by: season change (autumn → migrate), biome quality decline
  - Find tile in preferred_biome within migration range → path there

- [ ] **9.10** Placeholder rendering:
  - Colored ellipsoids per species. Brown=deer, gray=wolf, white=rabbit, dark brown=bear, gold=eagle
  - Scale by species size
  - Debug label: species name + AI state

- [ ] **9.11** Population balancing:
  - Per-species hard cap
  - Carrying capacity = biome fertility * area → limits herbivore count
  - Predators limited by prey availability naturally (starvation feedback loop)

### Verification
```
Deer graze on grasslands in herds of 3-8.
Wolves hunt deer. Successful kills reduce wolf hunger.
Rabbit population controlled by wolf predation.
Animals breed → population grows → hits carrying capacity → stabilizes.
Remove all wolves (debug) → deer population explodes → food depletes → deer starve.
Add wolves back → equilibrium restores.
Seasonal migration visible: animals move between biomes in autumn.
Fish swim in ocean tiles.
10 game years: all species still present, populations stable within bounds.
```

---

## Phase 10: Tribes, Followers & Autonomous Settlement

**Goal**: Human tribes appear and autonomously build a civilization. No player tribe — all tribes are AI-controlled.

### Critical Mechanics (from original constant.dat research)

**Mana Generation (exact from Populous wiki):**
- Every follower generates mana just by existing
- Mana rates per minute: Shaman=66.6, Brave=34.6, Warrior=11.3, Firewarrior=11.3, Preacher=11.3, Spy=11.3
- Mana is split 50/50 between spell charging and follower training. If only one sink exists, 100% goes there. If neither, mana is wasted.
- Mana allocated to spells is divided equally among all spells currently charging
- Mana allocated to training is divided equally among all active training huts

**Breeding Rate (exact from constant.dat):**
- Base breeding time per hut level: Level 1 = 4000 ticks, Level 2 = 3000 ticks, Level 3 = 2000 ticks
- Occupant multiplier: 0 braves = 0.5×, 1 = 1.0×, 2 = 1.5×, 3 = 2.0×, ... (n = n*0.5 + 0.5)
- Population band penalty (slows as pop grows): pop 0-4 = 30, pop 5-9 = 35, pop 10-14 = 40, ... (increases by 5 per band)
- Empty huts still breed (at 0.5× multiplier)

**Hut Upgrades:**
- Level 1 (small): holds 3 followers. Costs 2 wood piles.
- Level 2 (medium): holds 4 followers. Upgrades automatically when hut has ≥3 wood at entrance.
- Level 3 (large): holds 5 followers. Same auto-upgrade mechanism.
- Upgrade speed proportional to occupants.

### Tasks

- [ ] **10.1** Create `data/def_units.gd` — all 7 unit types with exact stats
- [ ] **10.2** Create `data/def_buildings.gd` — all building types with exact stats including breeding formulas
- [ ] **10.3** Create components: `com_tribe.gd`, `com_role.gd`, `com_inventory.gd`, `com_combat.gd`, `com_ai_state.gd`, `com_task.gd`, `com_building.gd`, `com_construction.gd`, `com_production.gd`, `com_garrison.gd`

- [ ] **10.4** Create `gen_settlement.gd`
  - For each tribe (4 tribes: Blue, Red, Yellow, Green):
    - Find flat coastal area with ≥5 trees within 10 tiles
    - Minimum distance between tribes: 40 tiles (torus distance)
    - Spawn: 1 Shaman, 6 Braves, 1 Circle of Reincarnation (pre-built)
    - Also spawn Wildmen clusters: 3-5 wildmen near trees/water, 4-6 clusters per map

- [ ] **10.5** Create `sys_pathfinding.gd` — A* on torus grid
  - Heuristic: `torus_distance()` from TorusGrid
  - Cost: base 1.0 × biome movement_cost × slope_factor
  - Impassable: water tiles (for land units), buildings (unless own garrison)
  - Path cache: don't re-path every frame, only when target changes or path blocked

- [ ] **10.6** Create `sys_movement.gd`
  - Entities with `com_pathfinding` + `com_velocity`: move along path at speed
  - When reaching path end: clear path, set `is_pathing = false`

- [ ] **10.7** Create `sys_brave_ai.gd` — the core autonomous behavior
  ```
  State priorities (evaluated top to bottom, first match wins):
    1. Has player/tribal order? → FOLLOWING_ORDER
    2. Nearby incomplete construction needing wood I carry? → BUILDING
    3. Inventory empty + trees nearby? → HARVESTING
    4. Tribe needs more huts + I have wood + flat land available? → PLANNING_BUILD
    5. Hut with space available? → ENTERING_HUT
    6. Nothing to do → WANDERING
  ```
  - HARVESTING: path to nearest tree → chop (2-3 sec) → remove tree entity → add wood to inventory → re-evaluate
  - BUILDING: path to construction → deposit wood → work on it (progress += per tick) → if complete: transition building entity → re-evaluate
  - PLANNING_BUILD: find flat area (2×2 or 3×3 tiles, all `is_flat`) not occupied → create construction entity → switch to BUILDING
  - ENTERING_HUT: path to hut → enter garrison → mark self as "housed" → stops updating AI (passive mana generation)
  - WANDERING: pick random nearby walkable tile → path there → wait 3s → re-evaluate

- [ ] **10.8** Create `sys_wildmen_ai.gd`
  - Wander near trees/water (pick random adjacent tile near a tree or water edge)
  - No combat, no building, no tribe
  - Can be converted (later, by Preacher/Shaman spell)

- [ ] **10.9** Placeholder rendering:
  - Colored capsule (tribe color). Height varies by role.
  - Wildmen: white/gray capsule
  - Text label: role + AI state (debug)

### Verification
```
4 tribes spawn in suitable locations.
Braves immediately begin: harvest trees → build huts → enter huts.
After 5 game minutes: each tribe has 3-5 huts, population growing.
Wildmen wander peacefully.
No Brave gets stuck (pathfinding works across wrap boundary).
After 15 game minutes: tribes have 20-30 followers each.
Debug: select a Brave → see state transitions in console log.
```

---

## Phase 11: Buildings, Mana, Population & Training

**Goal**: Full building lifecycle, mana economy, population growth, and military training all run autonomously.

### Tasks

- [ ] **11.1** Create `sys_construction.gd`
  - Track progress per building entity with `com_construction`
  - Multiple builders = faster: `progress += num_builders * build_speed * delta`
  - Wood consumption: builders deposit wood from inventory → `consumed_wood` increases
  - When `progress >= 1.0` and `consumed_wood >= required_wood`:
    - Remove `com_construction`, add `com_building` + `com_production` + `com_garrison`
    - Log: "Tribe RED built a WARRIOR_TRAINING at (45, 67)"

- [ ] **11.2** Create `sys_production.gd`
  - Huts: implement exact breeding formula from constant.dat
    ```
    base_time = [4000, 3000, 2000][hut_level - 1]
    occupant_multiplier = occupants * 0.5 + 0.5
    pop_band_penalty = 30 + (total_population / 5) * 5
    effective_rate = occupant_multiplier / (base_time * pop_band_penalty)
    breeding_progress += effective_rate * delta
    if breeding_progress >= 1.0: spawn_brave()
    ```
  - Training buildings: when a Brave enters → consume Brave → start training timer → produce trained unit → eject

- [ ] **11.3** Create `sys_garrison.gd`
  - Enter: add entity ID to garrison occupant list, mark entity as housed
  - Exit: remove from list, re-activate entity AI
  - Hut garrison: housed followers generate mana
  - Guard Tower garrison: extends garrisoned unit's effective range

- [ ] **11.4** Create `sys_mana.gd`
  - Per tribe each tick:
    ```
    raw_mana = sum of all followers' mana_per_minute / 60.0 * delta
    if has_spells_charging AND has_training:
        spell_mana = raw_mana * 0.5
        training_mana = raw_mana * 0.5
    elif has_spells_charging:
        spell_mana = raw_mana
    elif has_training:
        training_mana = raw_mana
    else:
        # mana wasted
    spell_mana split equally among all spells currently charging
    training_mana split equally among all active training buildings
    ```

- [ ] **11.5** Create `sys_population.gd`
  - Track per-tribe: total_population, housed_count, military_count
  - Enforce MAX_POPULATION cap: if total >= max, huts stop breeding
  - Hut auto-upgrade: if hut has enough wood piles nearby → upgrade level

- [ ] **11.6** Update `sys_brave_ai.gd` to build military buildings when tribal AI requests
- [ ] **11.7** Update `sys_tribal_ai.gd` with basic expansion logic:
  - EARLY_GAME: focus on huts, harvest, populating
  - MID_GAME: build 1 Warrior Training + 1 Temple of Fire, start training
  - Train balanced: 40% Warriors, 30% Firewarriors, 20% Preachers, 10% Spies

### Verification
```
Tribes autonomously grow from 6 followers to 50+ over 20 game minutes.
Mana accumulates (visible in debug). Spells charge (once spell system exists).
Training buildings convert Braves → Warriors visible.
Population stabilizes at cap.
Huts auto-upgrade from small → medium → large.
Log: mana income per tribe per minute matches expected formula.
```

---

## Phase 12: Spells, Terrain Manipulation & Combat

**Goal**: Shamans cast spells, terrain deforms, tribes fight and can be eliminated.

### Tasks

- [ ] **12.1** Create `data/def_spells.gd` — all 26 spells with exact stats
- [ ] **12.2** Create components: `com_spell_caster.gd`, `com_mana.gd`, `com_spell_effect.gd`, `com_spell_charge.gd`

- [ ] **12.3** Create `sys_spell_casting.gd`
  - AI Shaman selects spell based on tribal AI priority
  - Validate: alive, in range, charges available
  - Consume charge → create SpellEffect entity

- [ ] **12.4** Create `sys_spell_effect.gd` — process each spell type (see DOCS_SYSTEMS.md for full per-spell logic)
  - Terrain spells: Flatten, Raise, Lower, Hill, Valley, Landbridge, Erode
  - Offensive: Blast, Lightning, Tornado, Swamp, Firestorm, Earthquake, Volcano, Angel of Death
  - Support: Convert, Ghost Army, Invisibility, Shield, Hypnotise, Bloodlust, Teleport, Swarm

- [ ] **12.5** Create `sys_terrain_manipulation.gd`
  - Apply height changes to TorusGrid from spell effects
  - Trigger `sys_terrain_render` mesh update for affected region
  - Check buildings: if foundation no longer flat → destroy building

- [ ] **12.6** Create `sys_combat.gd`
  - Melee: if enemy within attack_range → deal damage per attack_speed
  - Ranged: Firewarrior fires at enemies within range, damage falloff with distance
  - Guard Tower bonus: garrisoned unit's range multiplied

- [ ] **12.7** Create `sys_damage.gd` — apply damage, respect armor, knockback
- [ ] **12.8** Create `sys_conversion.gd` — Preacher aura: tick conversion progress on nearby enemies
- [ ] **12.9** Create `sys_death.gd`
  - HP <= 0 → remove entity
  - Shaman dies → check for Circle of Reincarnation → respawn after delay, or tribe eliminated
  - Tribe eliminated when: Shaman dead + no circle + no followers
  - Log: "Tribe GREEN has been eliminated by RED"

- [ ] **12.10** Create `sys_shaman_ai.gd` — spell selection by tribal AI state
  - EXPAND: cast Flatten for building space, Convert wildmen
  - ATTACK: cast Lightning/Tornado/Volcano on enemy base
  - DEFEND: cast Shield/Blast on own army

- [ ] **12.11** Create `sys_warrior_ai.gd` — patrol, engage, guard
- [ ] **12.12** Create full `sys_tribal_ai.gd` — strategic decision making (see DOCS_SYSTEMS.md)
  - Threat evaluation → priority: DEFEND > EXPAND > BUILD_ARMY > ATTACK
  - Attack: identify weakest enemy, marshal army, lead with Shaman

- [ ] **12.13** Create `sys_movement.gd` flow field variant for large army groups (>10 units same target)

### Verification
```
Tribes fight autonomously.
Shamans cast spells: Flatten (for building), Lightning (for combat), etc.
Terrain visibly deforms from Volcano/Earthquake spells.
Warriors engage in melee, Firewarriors shoot from range.
Preachers convert enemies.
After 30+ game minutes: one tribe conquers all others.
Log shows full game narrative: expansion → conflict → elimination.
Fire from Firestorm spreads to nearby trees (connects to flora system).
```

---

## Phase 13: Player Tribe, Input, UI, Save/Load

**Goal**: One tribe becomes player-controlled. Full HUD. Save/load. The game is playable.

### Tasks

- [ ] **13.1** Create `sys_player_input.gd`
  - Left-click: select unit/building (shows info panel)
  - Right-click: issue move/attack/build order to selected units
  - Box-drag: multi-select
  - Keyboard shortcuts: spell panel, building panel

- [ ] **13.2** Modify `sys_brave_ai.gd`: player-tribe Braves still auto-build/harvest, but player orders override

- [ ] **13.3** Create `sys_ui_render.gd` — full HUD:
  - **Top bar**: mana pool, population count, current season/time
  - **Bottom bar**: spell panel (text labels, charge counts)
  - **Side panel**: selected unit info, selected building info
  - **Minimap**: top-down planet render with tribe colors
  - **Notifications**: "Your settlement is under attack!", "Spell learned: Tornado"

- [ ] **13.4** Camera switch: player controls the debug camera, but now with click-to-interact

- [ ] **13.5** Save/Load:
  - Serialize: all entities + components + TorusGrid + game time + weather state
  - Use Godot's `FileAccess` + JSON or binary format
  - Auto-save every 5 real minutes

- [ ] **13.6** Game speed controls: Pause, 1×, 2×, 4×, 8×

- [ ] **13.7** Vault of Knowledge + Stone Head placement and interaction
  - Special map objects that grant permanent/temporary spells
  - Shaman worships (path to, wait) → learns spell / gains charges

- [ ] **13.8** Win/Lose conditions:
  - Win: all enemy tribes eliminated
  - Lose: Shaman dies with no circle and no followers

### Verification
```
Player selects Blue tribe.
Can order Braves to build specific buildings.
Can select Shaman, click spell, click target → spell casts.
Save game → close → load → world state matches exactly.
Play full game to victory or defeat.
All 3 enemy tribes play competently against each other AND the player.
```

---

## Dependency Graph

```
Phase 0 (ECS + Scaffold)
  ↓
Phase 1 (Grid Data)
  ↓
Phase 2 (Sphere Mesh)
  ↓
Phase 3 (Terrain Gen)
  ↓
Phase 4 (Biomes)
  ↓
Phase 5 (Camera) ←── can now inspect the world
  ↓
  ├──→ Phase 6 (Time)
  │      ↓
  │    Phase 7 (Weather) ──┐
  │                         │
  ├──→ Phase 8 (Flora) ←───┘ weather affects flora
  │      ↓
  └──→ Phase 9 (Fauna) ←── fauna eats flora, disperses seeds
         ↓
       Phase 10 (Tribes + Braves) ←── braves harvest flora (trees)
         ↓
       Phase 11 (Buildings + Mana + Population)
         ↓
       Phase 12 (Spells + Combat + Tribal AI)
         ↓
       Phase 13 (Player Interaction)
```

---

## Risk Register

| Risk | Impact | Mitigation |
|---|---|---|
| Sphere projection seam at grid wrap | High | Test wrap boundary extensively in Phase 2. Vertex shader approach. |
| Pathfinding too slow for 800 units | High | Flow field for groups. LOD: distant units path less often. Path caching. |
| Fauna population explosion | Medium | Hard caps + carrying capacity. Tune in Phase 9. |
| ECS query too slow at 5000+ entities | Medium | Profile in Phase 8. Use typed component dictionaries, avoid linear scans. |
| AI tribes too dumb | Medium | Extensive tuning in Phase 12. Difficulty levels later. |
| Fire destroys all trees on planet | Medium | Fire spread rate tuning. Rain extinguish. Regrowth. |
| Save/load with thousands of entities | Medium | Test serialization early with small saves. Profile. |

---

*See [README.md](README.md) for project overview. See [DOCS.md](DOCS.md) and [DOCS_SYSTEMS.md](DOCS_SYSTEMS.md) for full technical specifications.*

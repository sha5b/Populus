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
  Phase 0:  Project Setup, ECS Core, Folder Scaffold ........... ✅ DONE
  Phase 1:  Torus Grid & Heightmap Data ....................... ✅ DONE
  Phase 2:  Sphere Projection & Terrain Mesh .................. ✅ DONE
  Phase 3:  Procedural Terrain (Multi-Noise, Minecraft-style) . ✅ DONE
  Phase 4:  Biome Assignment (Multi-Noise Table Lookup) ....... ✅ DONE
  Phase 4b: Weather ↔ Erosion Feedback Loop ................... ✅ DONE
  Phase 5:  Debug Camera (orbit, zoom, pan) ................... ✅ DONE

PART B — NATURE LIVES (no humans yet, planet ecology runs itself)
  Phase 6:  Time System (clock, day/night, seasons) ........... ✅ DONE
  Phase 7:  Weather System (rain, wind, storms) ............... ✅ DONE
  Phase 7b: Terrain Erosion (hydraulic, thermal, wind, river) . ✅ DONE
  Phase 7c: Weather & Atmosphere Visuals ...................... ✅ DONE
  Phase 7d: Tectonic Simulation ............................... PLANNED
  Phase 7e: Volumetric Cloud System (cube sphere + fluid) ..... ✅ DONE
  Phase 8:  Flora System (trees grow, spread seeds, burn) ..... ✅ DONE
  Phase 9:  Fauna System (animals eat, hunt, flee, breed) ..... ✅ DONE
  Phase 9b: Fauna Utility AI & Optimization ................... ✅ DONE
  Phase 9c: River & Canyon Formation .......................... ✅ DONE
  Phase 9d: Micro-Biome System ................................ ✅ DONE
  Phase 9e: Weather Visuals Fix (rain/lightning/fog) .......... ✅ DONE
  Phase 9f: Water Dynamics System ............................. ✅ DONE

PART C — CIVILIZATION LIVES (tribes run themselves, no player tribe)
  Phase 10: Tribes, Followers & Autonomous Settlement ......... IN PROGRESS
  Phase 11: Buildings, Mana, Population & Training ............ IN PROGRESS
  Phase 12: Spells, Terrain Manipulation & Combat ............. IN PROGRESS

PART D — PLAYER ENTERS (now the human can interact)
  Phase 13: Player Tribe, Input, UI, Save/Load ............... PLANNED

PART E — UPGRADES (post-gameplay polish)
  Phase 14: Voxel Terrain Upgrade (Astroneer-scale) .......... PLANNED
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
│   ├── com_energy.gd                          # current, max, drain_rate, rest_rate
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
│   ├── time/                                  # ── Time & Season ──
│   │   ├── sys_time.gd                        # game clock, day/night, sun rotation
│   │   └── sys_season.gd                      # seasonal temp/moisture offsets
│   │
│   ├── weather/                               # ── Weather & Atmosphere ──
│   │   ├── sys_weather.gd                     # state machine: clear/cloudy/rain/storm
│   │   ├── sys_wind.gd                        # latitude-dependent wind bands
│   │   ├── sys_precipitation.gd               # rain → moisture, snow → slow
│   │   ├── sys_weather_visuals.gd             # connects weather data → cloud/rain/lightning
│   │   └── sys_atmosphere_fluid.gd            # Navier-Stokes fluid dynamics for clouds
│   │
│   ├── erosion/                               # ── Terrain Erosion (weather-linked) ──
│   │   ├── sys_hydraulic_erosion.gd           # particle-based water erosion (rain × 2-4)
│   │   ├── sys_thermal_erosion.gd             # slope slumping (winter × 2.5)
│   │   ├── sys_coastal_erosion.gd             # wave action on shorelines
│   │   ├── sys_wind_erosion.gd                # aeolian sand transport (storm × 3)
│   │   └── sys_river_formation.gd             # persistent flow paths + lakes
│   │
│   │  # ── Future: Flora & Fauna ──
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
│   ├── def_micro_biomes.gd                    # MicroBiomeType enum + tint/modifier data
│   └── def_enums.gd                           # shared enums (AIState, TaskType, Season, etc.)
│
├── planet/                                    # ─── PLANET GEOMETRY (not ECS, pure math/rendering) ───
│   ├── torus_grid.gd                          # 2D wrapping grid data structure
│   ├── planet_projector.gd                    # grid coords  3D sphere + cube sphere projection
│   ├── planet_mesh.gd                         # ArrayMesh generation from heightmap
│   ├── planet_camera.gd                       # orbital camera (debug + player)
│   ├── planet_cloud_layer.gd                  # volumetric cloud chunk manager (96 MeshInstance3D)
│   ├── planet_atmosphere.gd                   # atmospheric glow shell
│   ├── planet_rain.gd                         # planet-local rain/snow emitters (8 GPUParticles3D)
│   ├── planet_water_mesh.gd                   # cube-sphere water mesh (depth/flow/temp vertex data)
│   ├── water_grid.gd                          # per-tile water data (depth, flow, temp, waves)
│   ├── atmosphere_grid.gd                     # cube sphere 3D atmospheric data (6×16×16×8)
│   └── cloud_mesh_generator.gd                # marching cubes mesh from cloud density field
│
├── generation/                                # ─── PROCEDURAL GENERATION (one-shot helpers) ───
│   ├── gen_heightmap.gd                       # multi-noise terrain (5 maps + splines)
│   ├── gen_biome.gd                           # temperature + moisture maps
│   ├── gen_biome_assignment.gd                # multi-noise table lookup biome classifier
│   ├── gen_flora.gd                           # place initial trees/bushes
│   ├── gen_fauna.gd                           # place initial animals
│   └── gen_settlement.gd                      # place initial tribes
│
├── shaders/                                   # ─── GPU SHADERS ───
│   ├── terrain.gdshader                       # height-based coloring, biome blending
│   ├── water.gdshader                         # animated water plane
│   ├── clouds.gdshader                        # procedural cloud billboard shader
│   ├── cloud_volume.gdshader                  # volumetric cloud mesh shader (vertex colors)
│   └── atmosphere.gdshader                    # atmospheric fresnel glow
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

## Phase 3: Procedural Terrain Generation (Multi-Noise, Minecraft-Style)

**Goal**: Each run generates a unique planet with continents, oceans, mountains, and varied terrain using multiple interacting noise maps inspired by Minecraft 1.18's multi-noise system.

### Architecture — Multi-Noise Terrain

Like Minecraft 1.18, terrain is shaped by **5 independent noise maps** that interact via **spline curves**:

1. **Continentalness** — How far inland (low = ocean, high = deep continent interior)
   - Controls base elevation: ocean basins vs continental shelves vs inland highlands
   - Fractal FBM, low frequency (large features)

2. **Erosion** — How eroded/flat the terrain is (low = rugged peaks, high = flat plains)
   - Modulates height variance: low erosion → dramatic terrain, high erosion → flat
   - Fractal FBM, medium frequency

3. **Peaks & Valleys (PV)** — Local terrain drama (high = peaks, low = valleys)
   - Adds local height variation: ridges, valleys, plateaus
   - Fractal Ridged noise for sharp peaks

4. **Temperature** — Latitude-based + altitude cooling + noise variation
   - Used for biome selection, NOT terrain shape

5. **Humidity** — Water proximity + noise + wind patterns
   - Used for biome selection, NOT terrain shape

**Terrain Height Formula**:
```
base_height = spline(continentalness)
height_variance = spline(1.0 - erosion)
final_height = base_height + peaks_valleys * height_variance + detail_noise * 0.1
```

The spline functions create non-linear mappings:
- Continental spline: flat ocean floor → steep coastal rise → gentle inland plateau
- Erosion spline: high erosion → squash height variance, low → allow full range

### Tasks

- [x] **3.1** Create `gen_heightmap.gd` — Multi-noise terrain generator
  - ~~Uses 2 noise layers~~
  - **v2**: Uses 5 noise maps: continentalness, erosion, peaks_valleys, plus detail
  - Spline-based blending for dramatic terrain variety
  - Continental shelves, mountain ranges, flat plains emerge naturally
  - Seed-based reproducibility

- [x] **3.2** Create `gen_biome.gd` — Temperature + Humidity maps
  - **Temperature**: latitude gradient + altitude cooling + noise
  - **Humidity**: water distance BFS + noise + wind bias
  - Store per-tile: `temperature: float`, `moisture: float`

- [x] **3.3** Register as one-shot in `main.gd`

- [ ] **3.4** Expose noise maps as debug data (continentalness, erosion, PV viewable in HUD)

### Verification
```
Each run: different continent shapes with natural-looking coastlines.
Mountains clustered in low-erosion zones, not random spikes.
Flat plains in high-erosion areas.
Sharp peaks from ridged PV noise.
Console prints: "Generated heightmap (5 noise maps). Land: 47%, Water: 53%"
```

---

## Phase 4: Biome Assignment & Rendering (Multi-Noise Table Lookup)

**Goal**: Every tile has a biome selected from a multi-dimensional lookup table using continentalness, erosion, temperature, and humidity — not simple if/else thresholds.

### Architecture — Minecraft-Style Biome Table

Biome selection uses a **2-stage lookup**:

**Stage 1: Terrain Category** (from continentalness × erosion):
```
                Low Erosion          Mid Erosion         High Erosion
Low Continent   Deep Ocean           Shallow Ocean       Coast
Mid Continent   Mountain Slopes      Hills               Plains
High Continent  High Mountains       Plateau             Flat Interior
```

**Stage 2: Biome Selection** (from temperature × humidity within each terrain category):
```
                Dry          Medium       Wet
Hot             Desert       Savanna      Tropical Forest
Warm            Steppe       Grassland    Temperate Forest
Cool            Taiga        Boreal       Boreal Forest
Cold            Snow/Ice     Tundra       Tundra
```

Additional rules:
- **Weirdness noise** (6th noise): when high, spawn variant biomes (bamboo jungle, ice spikes, mushroom fields)
- **Beach**: coast category + moderate temp
- **Swamp**: coast/plains + high humidity + warm
- **Mountain**: overrides based on altitude, temp determines snow cap vs rocky

### Tasks

- [x] **4.1** Create `data/def_biomes.gd`
  - BiomeType enum + per-biome properties (color, tree_density, fertility, etc.)

- [x] **4.2** Create `generation/gen_biome_assignment.gd`
  - ~~Simple Whittaker classifier~~
  - **v2**: Multi-noise table lookup using continentalness, erosion, temperature, humidity
  - 2-stage: terrain category → biome selection
  - Weirdness noise for rare variant biomes

- [x] **4.3** Biome rendering via vertex colors
- [x] **4.4** Terrain shader uses vertex colors

### Verification
```
Planet shows geographically plausible biome distribution.
Deserts only in hot dry interior regions, not random patches.
Tropical forests on hot humid coasts. Snow only at poles + high mountains.
Mountain biomes only where erosion is low and continentalness is high.
Adjacent biomes make geographic sense (no desert next to tundra).
```

---

## Phase 4b: Weather ↔ Erosion Feedback Loop

**Goal**: Weather actively drives erosion. Rain causes hydraulic erosion, temperature swings drive thermal erosion, wind drives aeolian erosion. Erosion reshapes terrain, which changes biomes over time.

### Tasks

- [x] **4b.1** Link weather state to hydraulic erosion intensity
  - RAIN: erosion_rate × 2.0, particles_per_batch × 1.5
  - STORM: erosion_rate × 4.0, particles_per_batch × 3.0
  - CLEAR: erosion_rate × 0.3 (minimal baseline)
  - FOG: erosion_rate × 0.5 (light moisture)

- [x] **4b.2** Link temperature to thermal erosion
  - Freeze-thaw: thermal_rate increases when temperature oscillates near freezing
  - Winter: thermal_rate × 2.5, Spring: × 1.8, Autumn: × 1.3, Summer: × 0.8

- [x] **4b.3** Link wind to aeolian erosion
  - wind_erosion_rate scales with actual wind speed from SysWind
  - Storm winds: 3× erosion rate
  - Rain: 0.5× (wet soil resists)

- [x] **4b.4** Periodic biome reassignment
  - `systems/biome/sys_biome_reassign.gd` — every 20s, scans all tiles for height delta > 0.008
  - Tracks `_last_heights` snapshot, only reassigns tiles where terrain actually changed
  - Uses `GenBiomeAssignment._classify_multinoise()` for consistent biome selection
  - Updates both `biome_map` and `grid.set_biome()` for changed tiles
  - Mesh receives updated `biome_map` on every periodic rebuild

### Verification
```
After prolonged rain: visible river valleys deepen, sediment at coastlines.
After winter: mountain slopes show more scree (thermal erosion).
Windy deserts: dunes shift slowly over time.
Biomes slowly evolve: a drying region transitions grassland → steppe → desert.
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

## Phase 7b: Terrain Evolution — Erosion, Rivers & Geological Processes

**Goal**: The terrain is alive — water carves rivers, slopes crumble, wind sculpts deserts, coastlines erode, and sediment accumulates. The world visibly changes over time.

### Tasks

- [x] **7b.1** Create `sys_hydraulic_erosion.gd` — Particle-based (snowball/raindrop) hydraulic erosion
  - Drop N virtual water particles per tick on random land tiles (biased toward high rainfall areas)
  - Each particle traces downhill using surface normals, carrying sediment
  - **Erosion**: particle picks up sediment proportional to speed × slope × rock hardness
  - **Deposition**: particle deposits sediment when speed decreases (flat area, pool, coast)
  - **Parameters**: `erosion_rate`, `deposition_rate`, `friction`, `max_iterations`, `particles_per_tick`
  - Accumulates over game time → rivers carve valleys, deltas form at coastlines
  - Only runs on above-sea-level tiles

- [x] **7b.2** Create `sys_thermal_erosion.gd` — Slope-based material slumping
  - For each tile pair (tile + neighbor): if height difference > `talus_angle` threshold
  - Transfer material from higher to lower: `transfer = (diff - talus) * thermal_rate * delta`
  - Creates smooth slopes, scree fields at mountain bases, rounded hills
  - **Parameters**: `talus_angle` (0.3 default), `thermal_rate` (0.01)
  - Runs every N game-hours (not every frame — periodic batch)

- [x] **7b.3** Create `sys_coastal_erosion.gd` — Wave action on shorelines
  - Identify coastal tiles (land adjacent to ocean)
  - Lower coastal tile height by `wave_erosion_rate * delta`
  - Rate modified by: wave energy (wind speed × fetch distance), rock hardness
  - Creates beaches, cliffs, sea stacks over long periods
  - Deposits eroded material as shallow underwater sediment nearby

- [x] **7b.4** Create `sys_wind_erosion.gd` — Aeolian processes
  - Active in dry biomes (DESERT, STEPPE) and beaches
  - Pick up fine sediment from exposed dry tiles, deposit downwind
  - Rate = `wind_speed * dryness_factor * wind_erosion_rate * delta`
  - Creates sand dunes (height accumulation downwind), desert pavements
  - Only operates where moisture < 0.2 (dry surfaces)

- [x] **7b.5** Create `sys_river_formation.gd` — Persistent water flow paths
  - After hydraulic erosion accumulates: detect tiles where water consistently flows
  - Trace flow paths: from high points, follow steepest descent to sea/lake
  - Tiles with persistent flow → mark as `is_river = true`, lower height slightly
  - River tiles increase local moisture for neighboring tiles (+0.3 moisture radius 3)
  - Rivers merge (confluences) and widen downstream
  - Lakes form in enclosed basins (fill until overflow → outflow river)

- [x] **7b.6** Sediment tracking (integrated into hydraulic erosion deposition) — Long-term geological accumulation
  - Track sediment_depth per tile (separate from rock height)
  - Sediment increases fertility (good for flora)
  - River deltas: high sediment deposit at river mouths → flat fertile land
  - Volcanic tiles (from spells later): deposit mineral-rich sediment

- [x] **7b.7** Update `planet_mesh` — dirty flag + periodic rebuild every 5s in main._process
  - Dirty flag system: when `sys_*_erosion` modifies heights, mark affected region
  - In `sys_terrain_render` (or main._process): if dirty → `planet_mesh.update_region()`
  - Rebuild biome assignments for significantly changed tiles

- [ ] **7b.8** Add terrain hardness property (deferred — biome-based hardness) to biomes/tiles
  - Mountain/rock = high hardness (slow erosion)
  - Sand/beach = low hardness (fast erosion)
  - Frozen = very high hardness (winter slows erosion)
  - Store in `com_tile` or as a parallel grid

- [x] **7b.9** Performance: batch erosion (hydraulic=1h, thermal=6h, coastal/wind=12h, rivers=seasonal)
  - Hydraulic erosion: process 100-500 particles per game-hour (not per frame)
  - Thermal erosion: run every 6 game-hours as a batch pass
  - Coastal/wind: run every 12 game-hours
  - River recalculation: run every game-season (expensive, infrequent)

### Verification
```
After 5 game years:
- Visible river valleys carved from mountains to coast
- Mountain slopes are smoother than initial generation
- Sediment deltas visible at river mouths (slightly raised flat land)
- Desert dunes shift with wind direction
- Coastlines show erosion (retreated from original line)
- Console: "Hydraulic erosion: 50000 particles, avg sediment moved: 0.003"
- Console: "Rivers formed: 12 rivers, 3 lakes"
- Mesh updates are smooth, no visible popping
```

---

## Phase 7d: Tectonic Simulation, Earthquakes, Tsunamis & Volcanism

**Goal**: The planet has tectonic plates that drift slowly. Plate boundaries produce earthquakes, volcanic eruptions, and tsunamis. These are rare, dramatic events that reshape terrain and threaten settlements.

### Tasks

- [ ] **7d.1** Create `generation/gen_tectonic_plates.gd` — Initial plate assignment
  - Seed N plates (6-10) using Voronoi regions on the torus grid
  - Each plate: id, drift_direction (Vector2), drift_speed (0.001-0.005), density (continental vs oceanic)
  - Store `plate_id` per tile in `PackedInt32Array`
  - Continental plates: higher base elevation, oceanic plates: lower

- [ ] **7d.2** Create `systems/sys_plate_tectonics.gd` — Slow plate drift
  - Every game-year: shift plate boundaries slightly in drift direction
  - **Convergent boundaries** (plates moving toward each other):
    - Continental-continental → mountain building (raise height at boundary +0.02/year)
    - Oceanic-continental → subduction (lower oceanic side, raise continental, volcanic arc)
    - Oceanic-oceanic → trench formation + island arc volcanoes
  - **Divergent boundaries** (plates moving apart):
    - Create rift valleys, mid-ocean ridges (raise height slightly)
    - New crust at boundary (height = sea level)
  - **Transform boundaries** (plates sliding past):
    - Earthquake risk zone, no height change

- [ ] **7d.3** Create `systems/sys_earthquake.gd` — Seismic events
  - Probability per game-year at plate boundaries proportional to stress accumulation
  - Stress accumulates each year at convergent/transform boundaries
  - When stress > threshold → earthquake event:
    - Magnitude 1-5 scale (exponential energy)
    - Shake nearby tiles: randomly offset height ±0.01-0.05
    - Damage buildings within radius (future phase hook)
    - Console: "Earthquake! Magnitude 3.2 at (45, 67)"
  - Stress resets after quake

- [ ] **7d.4** Create `systems/sys_tsunami.gd` — Water displacement waves
  - Triggered by: underwater earthquake (magnitude ≥ 3), volcanic eruption in ocean
  - Wave propagation: BFS from epicenter outward at 2 tiles/game-second
  - Wave height decreases with distance: `h = magnitude * 0.5 / sqrt(distance)`
  - When wave hits coastline:
    - Temporarily raise water level on coastal tiles
    - Flood inland tiles 1-3 deep depending on wave height
    - Damage/destroy entities on flooded tiles (future phase hook)
    - Erosion boost on hit tiles
  - Wave dissipates after reaching all shores or traveling max distance
  - Visual: temporary height pulse on water mesh vertices (shader uniform)

- [ ] **7d.5** Create `systems/sys_volcanism.gd` — Volcanic eruptions
  - Volcanoes spawn at: convergent boundaries, hotspots (random, rare)
  - Track volcanic_pressure per volcano tile (accumulates slowly)
  - When pressure > threshold → eruption:
    - Raise height dramatically at eruption site (+0.1-0.3)
    - Deposit material in cone shape (radius 3-5, height falloff)
    - Lava flow: trace downhill path from summit, raise height along path
    - Set tiles along lava path as `is_burning` (kills flora/fauna)
    - Ash cloud: increase cloud coverage locally, reduce temperature in radius 10 for 1 season
  - Dormant period after eruption (50-200 game years)
  - Volcanic soil: high fertility bonus after cooling (10 game years)

- [ ] **7d.6** Create `shaders/water_wave.gdshader` — Tsunami visual
  - Modify water shader to accept wave_positions array + wave_heights
  - Vertex displacement ring expanding from epicenter
  - Fade out over time

- [ ] **7d.7** Integrate plate data into terrain generation
  - `gen_heightmap.gd` uses plate boundaries to bias continental vs oceanic elevation
  - Mountain ranges align with convergent boundaries
  - Ocean trenches at subduction zones

- [ ] **7d.8** Performance: tectonic processing
  - Plate drift: once per game-year (very cheap)
  - Stress calculation: once per game-year
  - Earthquake check: once per game-month
  - Tsunami propagation: real-time BFS during event (batched, max 100 steps/frame)

### Verification
```
After 50 game years:
- Mountain ranges grow slowly at convergent boundaries
- Occasional earthquake messages: "Earthquake! Magnitude 2.7 at (34, 89)"
- Rare tsunami from undersea quake: visible wave ring on water surface
- 1-2 volcanic eruptions: visible cone growth, lava trail, ash effects
- Volcanic soil enriches nearby biomes after cooling
- Plate boundaries visible as lines of seismic activity
- Terrain at divergent boundaries shows rift features
```

---

## Phase 7c: Weather & Atmosphere Visuals

**Goal**: Weather isn't just data — you see clouds drifting, rain falling, snow settling, lightning cracking, and fog rolling in. The planet has an atmospheric glow visible from orbit.

### Tasks

- [x] **7c.1** Create `shaders/clouds.gdshader` — Procedural cloud layer
  - Rendered on a sphere mesh slightly larger than the planet (radius = planet + 2.0)
  - Fragment shader: layered FBM noise scrolling with wind direction + time
  - `cloud_coverage` uniform (0.0–1.0) driven by weather state:
    - CLEAR=0.1, CLOUDY=0.5, RAIN=0.7, STORM=0.9, FOG=0.3, SNOW=0.6
  - Cloud color: white/grey, darker for storm, slightly blue-tinted at night
  - Alpha: clouds are semi-transparent, thicker = more opaque
  - Noise UV scrolls in wind direction at wind speed
  - Poles get less cloud coverage (latitude fade)

- [x] **7c.2** Create `planet/cloud_layer.gd` (extends MeshInstance3D)
  - SphereMesh slightly larger than planet
  - Applies `clouds.gdshader` as ShaderMaterial
  - `set_coverage(value: float)` → updates shader uniform
  - `set_wind(direction: Vector2, speed: float)` → updates scroll uniforms
  - `set_time_of_day(hour: float)` → adjusts cloud brightness (darker at night)
  - Rotates slowly with wind for visual movement

- [x] **7c.3** Create `shaders/atmosphere.gdshader` — Atmospheric scattering glow
  - Rendered on a sphere mesh larger than clouds (radius = planet + 5.0)
  - Fresnel-based glow: stronger at edges (limb), transparent at center
  - Color shifts with time of day: blue day, orange sunrise/sunset, dark blue night
  - `atmosphere_density` uniform for haze during fog/rain
  - Additive blending (no depth write)

- [x] **7c.4** Create `planet/atmosphere_shell.gd` (extends MeshInstance3D)
  - Setup + uniform updates from time system

- [x] **7c.5** Create `systems/sys_weather_visuals.gd` — Connects weather data → visuals
  - Each tick: read `SysWeather.current_state`, `SysWind`, `SysTime.hour`
  - Update cloud_layer: coverage, wind scroll, brightness
  - Update atmosphere_shell: density, color
  - Transition smoothly (lerp coverage over 3-5 seconds on weather change)
  - Update environment fog: CLEAR=0, RAIN=light fog, FOG=heavy fog, STORM=medium fog

- [x] **7c.6** Create rain particle effect
  - GPUParticles3D node, child of camera (follows player view)
  - Particles: small white/blue streaks falling downward relative to planet surface
  - Emitting only when weather == RAIN or STORM
  - STORM: more particles, faster, slight wind angle bias
  - Rain amount scales: 500 particles (RAIN), 2000 particles (STORM)

- [x] **7c.7** Create snow particle effect
  - GPUParticles3D node, same setup as rain but:
  - Slower fall speed, slight drift/wobble
  - White dots instead of streaks
  - Active when weather == RAIN or STORM AND temperature < 0.25 at camera position

- [x] **7c.8** Create lightning effect (flash via sun energy spike)
  - During STORM: random lightning flash every 3-10 seconds
  - Flash: brief spike of DirectionalLight energy (0.15 → 3.0 → 0.15 over 0.2s)
  - Optional: spawn a short-lived glowing line mesh from cloud to ground at strike tile
  - Screen tint flash (white overlay 0.1s via CanvasLayer)

- [x] **7c.9** Create fog effect (environment fog density driven by weather)
  - Use Godot's built-in Environment volumetric fog or depth fog
  - FOG weather: `fog_density` ramps up, `fog_light_energy` dims
  - Transition: smooth 5-second ramp

- [ ] **7c.10** Snow accumulation visual (deferred — needs per-tile snow_depth tracking)
  - When snowing: lerp tile vertex colors toward white over time
  - When not snowing + warm: lerp back to biome color
  - Track `snow_depth` per tile (0.0–1.0) — visual only, no gameplay yet
  - Shader: mix biome color with white based on snow_depth uniform or vertex color alpha

### Verification
```
CLEAR: Blue sky, thin wispy clouds, atmosphere glow at edges.
CLOUDY: Thicker cloud coverage, clouds drift with wind.
RAIN: Dark clouds, rain streaks falling near camera, ground appears wet.
STORM: Very dark clouds, heavy rain, lightning flashes illuminate planet,
       thunder-like screen shake (subtle), lightning bolts visible.
FOG: Ground fog obscures terrain, reduced visibility, muted atmosphere.
SNOW: White particles drifting, terrain gradually turns white in cold biomes.
Day/night: Clouds darken at night, atmosphere shifts orange at dawn/dusk.
Transitions: All changes smooth, no popping.
```

---

## Phase 7e: Volumetric Cloud System (Voxel Meshes + Fluid Dynamics)

**Goal**: Replace flat billboard cloud patches with true 3D volumetric cloud meshes generated from a density field. Clouds form, evolve, and dissipate based on atmospheric fluid dynamics — moisture advection, condensation, evaporation, and wind shear. Different cloud types (cumulus, stratus, cirrus) emerge naturally from the simulation.

### Architecture

#### Atmospheric Grid (Cube Sphere)
- 3D grid on cube sphere: 6 faces × 16×16 × 8 altitude layers (no pole convergence)
- Each cell stores: `moisture`, `temperature`, `pressure`, `wind_u/v/w`, `cloud_density`
- Cube sphere projection eliminates lat/lon pole hotspots — uniform cell distribution
- PlanetProjector provides `cube_sphere_point()` and `world_to_cube_face()` mapping

#### Fluid Dynamics (Simplified Navier-Stokes)
- **Advection**: moisture and temperature carried by wind velocity field
- **Pressure solve**: high pressure flows to low pressure (drives wind convergence/divergence)
- **Buoyancy**: warm moist air rises, cool dry air sinks
- **Coriolis force**: deflects horizontal wind based on latitude (already in wind bands)
- **Condensation**: when moisture > saturation threshold (temp-dependent) → cloud density increases, releases latent heat (warms cell, drives further uplift)
- **Evaporation**: when moisture < saturation → cloud density decreases
- **Precipitation**: when cloud density exceeds threshold → rain/snow forms, depletes moisture

#### Cloud Mesh Generation
- For each atmospheric column: if any cell has cloud density > threshold → generate 3D mesh
- Use **metaball / marching cubes** on the density field to produce smooth blobby cloud geometry
- Cloud mesh is an ArrayMesh with vertex colors (white core, grey edges, dark underside)
- Meshes regenerated every N frames (not every frame) to amortize cost
- LOD: far clouds use simpler geometry (fewer marching cubes steps)

#### Cloud Types (Emergent)
- **Cumulus** (puffy): strong vertical uplift, high moisture, moderate altitude → tall dense blobs
- **Stratus** (flat layers): stable atmosphere, uniform moisture → thin horizontal sheets
- **Cirrus** (wispy): high altitude, low moisture, strong wind shear → stretched thin wisps
- **Cumulonimbus** (storm): extreme uplift + moisture → very tall, dark, triggers lightning/heavy rain

### Tasks

- [x] **7e.1** Create `planet/atmosphere_grid.gd` — 3D atmospheric data grid
  - Cube sphere 6 faces × 32×32 × 4 altitude
  - Each cell: moisture, temperature, pressure, wind velocity (u/v/w), cloud_density
  - Initialize from biome data via PlanetProjector cube sphere projection
  - Temperature computed from world-position latitude (asin), moisture bilinearly interpolated
  - 8×8 chunks per face = 384 total chunks

- [x] **7e.2** Create `systems/weather/sys_atmosphere_fluid.gd` — Fluid dynamics simulation
  - Runs every 1.5s, iterates all 6 faces × 32×32 × 4 altitude
  - **Advection**: semi-Lagrangian moisture/temperature transport (pre-allocated buffers)
  - **Pressure**: ideal gas law, gradient drives wind convergence
  - **Coriolis**: latitude-dependent wind deflection (cached in `_lat_cache[]`)
  - **Buoyancy**: warm moist air rises, cool dry air sinks
  - **Condensation/Evaporation**: saturation curve → cloud_density changes + latent heat
  - **Precipitation**: dense clouds drain moisture downward
  - **Weather injection**: state-dependent moisture injection (CLEAR=0.002, STORM=0.04)
  - Only marks changed chunks dirty (density delta > 0.02)

- [x] **7e.3** Cloud density: **Noise-driven** (Horizon Zero Dawn inspired)
  - `get_cloud_density_at()` samples **3D noise at world positions** (seamless across cube faces)
  - Low-freq Simplex FBM (4 octaves) for cloud shapes
  - High-freq Cellular/Worley FBM (3 octaves) for detail edges
  - Coverage noise (3 octaves) for large-scale weather patterns
  - Fluid sim moisture × temperature modulates coverage (weather map)
  - Vertical profile: ramp up at base, flat in middle, fade at top
  - Polar fade above 85° latitude
  - `wind_offset` drifts with wind direction + planet rotation → clouds move

- [x] **7e.4** Create `planet/cloud_mesh_generator.gd` — Marching cubes
  - Full 256-case marching cubes with edge + triangle lookup tables
  - Density threshold 0.15, density-dependent vertex alpha (0.1–0.85)
  - Sphere-outward normals, correct winding order
  - World positions from `atmo_grid.get_cell_world_pos()` (cube sphere projected)

- [x] **7e.5** Create `planet/planet_cloud_layer.gd` — Manages cloud mesh instances
  - 6 faces × 8×8 chunks per face = 384 MeshInstance3D nodes
  - Rolling rebuild: 12 chunks per frame cycling continuously
  - No dirty tracking needed — noise changes with wind_offset

- [x] **7e.6** Create cloud shader — `shaders/cloud_volume.gdshader`
  - Spatial shader, blend_mix, cull_disabled (double-sided), depth_draw_never, unshaded
  - Uses VERTEX_COLOR for per-vertex lighting + density-based alpha
  - Fresnel rim + edge alpha smoothstep

- [x] **7e.7** Integrate with weather + wind systems
  - `SysWeatherVisuals` calls `atmo_grid.advance_wind()` every frame
  - Wind direction + speed from `SysWind`, planet rotation drift
  - Weather state controls coverage via moisture injection rates
  - Cloud types emerge naturally from noise + coverage interaction

- [ ] **7e.8** Connect rain/snow to cloud positions
  - `PlanetRain` emitters positioned under cloud chunks that are precipitating
  - Rain intensity proportional to precipitation rate from atmosphere sim

- [x] **7e.9** Performance optimization
  - Atmosphere sim: 1.5s tick, cached latitude fractions, pre-allocated advection buffers
  - Only dirty chunks rebuilt in fluid sim; rolling rebuild for noise-driven visuals
  - Shader: vertex colors only, no per-pixel noise
  - Atmosphere halo removed (visual quality insufficient)

### Verification
```
CLEAR weather: Scattered cloud patches (~20% coverage), noise-driven shapes.          ✅
CLOUDY: More patches (~40%), clouds are solid 3D marching-cubes geometry.               ✅
STORM: Heavy coverage (~75%), thick clouds.                                              ✅
Wind: Clouds drift with wind direction + slow planet rotation.                           ✅
No cube face seams: 3D noise sampled at world positions is inherently seamless.          ✅
Zoom in (FPS mode): Clouds visible overhead with depth and 3D shape.                     ✅
Performance: 40+ FPS with rolling rebuild (12 chunks/frame).                             ✅
Weather-responsive: More clouds over warm/moist biomes, fewer over deserts/poles.        ✅
```

---

## Phase 8: Flora System

**Goal**: Trees and bushes spawn, grow through life stages, spread seeds, catch fire, and die. All autonomous.

### Tasks

- [x] **8.1** `data/def_flora.gd` — **25 species** across all 13 land biomes
  - FloraType enum: TREE, BUSH, GRASS, AQUATIC, GROUND_COVER
  - Each species: preferred_biomes, growth_rate, max_age, yields, seed_method, flammability, mesh_color/height
  - `get_species_for_biome()` helper for biome→species lookup

- [x] **8.2** Components (pre-existing): `com_plant_species.gd`, `com_growth.gd`, `com_seed_dispersal.gd`, `com_flammable.gd`, `com_resource.gd`

- [x] **8.3** `generation/gen_flora.gd` — initial biome-based placement
  - Per land tile: roll against biome's `tree_density` × DENSITY_ROLL_SCALE
  - Pick random valid species for biome → entity at MATURE stage
  - World positions placed on terrain surface: `dir * (radius + height * height_scale)`

- [x] **8.4** `systems/flora/sys_flora_growth.gd` — growth lifecycle
  - Ticks every 2s, advances age by tick × TIME_SCALE
  - Fertility from moisture/temperature/biome match
  - Stage transitions: SEED(0-0.1) → SAPLING(0.1-0.3) → YOUNG(0.3-0.5) → MATURE(0.5-0.8) → OLD(0.8-1.0) → DEAD
  - Dead entities removed immediately

- [x] **8.5** `systems/flora/sys_seed_dispersal.gd` — seed spreading
  - Ticks every 3s, max 20 seeds per tick
  - MATURE/OLD plants disperse via WIND (biased by SysWind), WATER, or ANIMAL
  - Target must be land, unoccupied, biome-compatible
  - New seeds placed on terrain surface

- [x] **8.6** `systems/flora/sys_fire_spread.gd` — fire system
  - Lightning ignition during STORM (0.2% chance × flammability)
  - Wind-biased spread to neighbors within 2 tiles
  - Rain/storm extinguishes (burn_timer recovery)
  - Burned entities removed; `ignite_at()` debug method

- [x] **8.7** `planet/planet_flora_renderer.gd` — MultiMeshInstance3D rendering
  - Per flora type: TREE=cone, BUSH=sphere, GRASS=cross-quad, GROUND=flat
  - Stage-dependent scale (SEED=0.15×, MATURE=1.0×, OLD=0.85×)
  - Color from species data, darkened for OLD/SEED, red/orange for BURNING
  - Placed on terrain surface, oriented along sphere normal

- [x] **8.8** Wired in `scenes/main.gd` + `TorusGrid` biomes array

### Verification
```
Planet covered in biome-appropriate flora at startup.                             ✅
25 species across all 13 land biomes.                                             ✅
Trees placed on actual terrain surface (matching erosion/height).                 ✅
Growth system: SEED → MATURE → OLD → DEAD lifecycle.                             ✅
Seed dispersal: wind-biased spreading, biome-compatible targets.                 ✅
Fire: lightning ignition in storms, wind spread, rain extinguish.                ✅
MultiMesh rendering with per-species colors and stage scaling.                   ✅
```

---

## Phase 9: Fauna System

**Goal**: Animals roam, eat, hunt, flee, form herds, breed, migrate, and die. All autonomous.

### Tasks

- [x] **9.1** `data/def_fauna.gd` — 7 species: deer, wolf, rabbit, bear, eagle, fish, bison with full stats

- [x] **9.2** Components: `com_fauna_species.gd` (new), reused `com_hunger.gd`, `com_predator.gd`, `com_prey.gd`, `com_herd.gd`, `com_reproduction.gd`, `com_migration.gd`, `com_health.gd`, `com_ai_state.gd`

- [x] **9.3** `gen_fauna.gd` — biome-aware placement with herd grouping, aquatic/land filtering, 40 cap per species

- [x] **9.4** `sys_fauna_ai.gd` — state machine: IDLE → WANDERING → FORAGING → HUNTING → FLEEING → SLEEPING → MIGRATING → DYING. Night sleep, hunger-driven foraging/hunting.

- [x] **9.5** `sys_hunger.gd` — hunger increments in game-years, starvation damage when full

- [x] **9.6** `sys_predator_prey.gd` — nearest-prey search, chase, kill at range 2, hunger reduction on kill, prey fleeing triggers

- [x] **9.7** `sys_herd.gd` — boids flocking: separation + cohesion with torus-aware wrapping, skips fleeing/sleeping animals

- [x] **9.8** `sys_reproduction.gd` — maturity check, mate proximity search, cooldown, offspring spawning with species caps (15-60 per species)

- [x] **9.9** `sys_migration.gd` — autumn-triggered, searches 30-tile radius for preferred biome, steps toward target

- [x] **9.10** `planet_fauna_renderer.gd` — MultiMeshInstance3D per species, SphereMesh ellipsoids, color-coded by species + AI state tinting

- [x] **9.11** Population balancing: per-species hard caps in reproduction, starvation feedback loop for predator/prey balance, hunger gates breeding

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

## Phase 9b: Fauna Utility AI & Performance Optimization

**Goal**: Replace simple state machine with utility-based AI. Fix FPS degradation from O(N²) scans.

### Tasks

- [x] **9b.1** `com_energy.gd` — new component: current, max, drain_rate, rest_rate
- [x] **9b.2** Rewrite `sys_fauna_ai.gd` to utility-based AI
  - Each tick scores 6 competing needs: forage, hunt, sleep, flee, mate, wander
  - Highest utility wins state selection
  - Hunger urgency → forage (herbivore) or hunt (carnivore)
  - Energy urgency + night → sleep
  - Threat proximity → flee (prey only, via spatial hash)
  - Maturity + fed + rested → mate
  - Baseline 0.3 → wander
- [x] **9b.3** Directed movement behaviors
  - `_move_toward_food()`: evaluates 8 neighbor tiles by biome fertility + tree_density
  - `_move_away_from_threat()`: flee vector = sum of inverse-distance from nearby predators
  - `_try_move()`: shared movement with terrain/water validation
- [x] **9b.4** Spatial hash grid for O(1) neighbor lookup
  - 16×16 tile cells, key = `cy * 1000 + cx`
  - `_rebuild_spatial_predators()`: built once per AI tick
  - `_sense_threat_spatial()`: checks 3×3 cells instead of all entities
- [x] **9b.5** Staggered batch processing
  - `SysFaunaAi`: 40 entities/tick round-robin, 1.0s interval
  - `SysPredatorPrey`: 20 predators/tick, 2.0s interval, spatial prey hash
  - `SysHerd`: 2.0s interval, cap 8 members per boids calculation
  - `SysReproduction`: 5.0s interval, species caps lowered (12-40)
- [x] **9b.6** Fix startup delay: animals spawn in WANDERING/FORAGING with staggered timers
- [x] **9b.7** Add ComEnergy to spawned fauna (gen_fauna.gd + sys_reproduction.gd)

### Verification
```
Animals active immediately on load (no 3s freeze).
FPS stable over time as population grows.
Herbivores seek fertile tiles. Predators hunt via spatial lookup.
Prey flees directionally away from predators.
Animals sleep at night or when energy depleted.
```

---

## Phase 9c: River & Canyon Formation

**Goal**: Visible river channels carved into terrain, flowing from mountains to sea, with canyon formation.

### Tasks

- [x] **9c.1** Rewrite `sys_river_formation.gd`
  - 8-neighbor flow direction (was 4)
  - Moisture-weighted flow accumulation: `1.0 + moisture` per tile
  - Flow threshold lowered: 8.0 (was 15.0) for more tributaries
  - Multi-pass carving: 3 passes at startup
  - Flow-scaled carve rates: `BASE_CARVE_RATE=0.015 × flow/30` (was flat 0.005)
  - Canyon carve rate: `0.04 × flow/60` for flow > 40
  - `_widen_canyon()`: neighbors carved at 30% depth for valley formation
- [x] **9c.2** Execution order fix in `main.gd`
  - River system created during `_generate_terrain()`, after erosion prebake
  - Canyons carved BEFORE biome assignment → affects biome classification
  - `river_map` fed to mesh on first build
  - `time_system` wired later in `_register_systems()`
- [x] **9c.3** River color gradient in `planet_mesh.gd`
  - Shallow streams: `Color(0.2, 0.35, 0.55)`
  - Deep rivers: `Color(0.08, 0.15, 0.45)`
  - Lerp by `river_strength` for natural variation
- [x] **9c.4** `biome_map` promoted to class variable in `main.gd` for system access

### Verification
```
Blue river channels visible from orbit, flowing mountain→sea.
Wider/deeper canyons where flow accumulates.
River valleys affect biome assignment (riparian zones).
Console: "Initial river carving: 3 passes, N river tiles, M lakes"
```

---

## Phase 9d: Micro-Biome System

**Goal**: Add sub-biome variation based on local terrain features for visual and gameplay diversity.

### Tasks

- [x] **9d.1** `data/def_micro_biomes.gd` — 14 micro-biome types with color tints and gameplay modifiers
- [x] **9d.2** `systems/biome/sys_micro_biome.gd` — classification based on slope, aspect, curvature, river proximity, neighbor biomes
- [x] **9d.3** Integration: `micro_biome_map` fed to `PlanetMesh`, color tinting via `_apply_micro_tint()`
- [x] **9d.4** Reassignment every 30 seconds

---

## Phase 9e: Weather Visuals Fix

**Goal**: Make rain, lightning, and fog actually visible in-game.

### Tasks

- [x] **9e.1** Rain fix: particle size 0.06×0.4 (was 0.03×0.25), closer offsets (3 units, was 8), 300 particles, no_depth_test, height 3.5
- [x] **9e.2** Lightning bolt: `ImmediateMesh` triangle strip with 8 jagged segments, emissive glow (energy=8.0), 0.2s visible, random horizontal offset, triggered from `SysWeatherVisuals`
- [x] **9e.3** Fog fix: 3 emitters (was 1), 6.0×3.5 quads (was 4.0×2.5), alpha 0.25 (was 0.12), shows during RAIN+STORM+FOG (was FOG only)

---

## Phase 9f: Water Dynamics System

**Goal**: Replace static water sphere with a full fluid dynamics system. Water flows downhill from mountains, ocean has temperature-driven currents and wind-driven waves, weather affects water levels.

### Architecture

**Data Layer** — `planet/water_grid.gd`:
- Per-tile: `water_depth`, `flow_vx/vy`, `water_temp`, `wave_height`, `surface_height`
- Initialized from terrain: tiles below SEA_LEVEL get depth = SEA_LEVEL - terrain_h
- Temperature seeded from global temperature_map

**Simulation** — `systems/water/sys_water_dynamics.gd`:
- Chunked processing: 2048 tiles every 0.5s (full grid in ~8 ticks = 4s)
- **Shallow water flow**: height gradient → flow velocity → water transfer to downhill neighbors
- **Weather**: rain adds depth (0.0003/tick normal, 0.001 storm), evaporation drains (temp-scaled)
- **River injection**: river tiles continuously feed water at rate proportional to river_strength
- **Wind currents**: deep water (>0.05) gets wind_dir × wind_speed push
- **Coriolis deflection**: latitude-dependent perpendicular force on flow
- **Ocean currents** (every 3s, 512 random tiles):
  - Thermohaline: warm equatorial water flows poleward, cold polar water flows equatorward
  - Temperature diffusion between neighboring water tiles
  - Latitude-based temperature tendency (equator warm, poles cold)
- **Waves**: storm boosts wave_height, exponential decay (0.85/tick)

**Rendering** — `planet/planet_water_mesh.gd`:
- Cube-sphere mesh (6 faces × 64×64) matching terrain mesh topology
- Per-vertex: position from water surface_height, color from depth+temperature, UV from flow velocity
- Rebuilds every 2.0s (performance-gated)
- Depth coloring: shallow=Color(0.15,0.35,0.55) → deep=Color(0.02,0.08,0.35)
- Temperature tint: warm=greenish/turquoise, cold=deep blue
- Zero-depth tiles get alpha=0 (transparent over land)

**Shader** — `shaders/water.gdshader`:
- Multi-octave wave displacement: 3 sine/cosine waves with flow-modulated frequency
- Flow distortion: wave pattern shifts with current direction
- Caustic animation from flow magnitude
- Fresnel edge transparency
- Specular highlights (Schlick GGX)

### Tasks

- [x] **9f.1** `planet/water_grid.gd` — per-tile water data structure
- [x] **9f.2** `systems/water/sys_water_dynamics.gd` — chunked shallow water sim + ocean currents
- [x] **9f.3** `planet/planet_water_mesh.gd` — cube-sphere water mesh with depth/flow/temp vertex data
- [x] **9f.4** `shaders/water.gdshader` — flow-aware waves, depth color, fresnel, specular
- [x] **9f.5** Replace static SphereMesh in `main.gd` with dynamic water mesh + system

### Verification
```
Water visible on ocean tiles with depth-based coloring (dark deep ocean, lighter shallow).
Rivers feed water into downstream tiles.
Rain visibly raises water levels. Evaporation slowly lowers them.
Storm weather creates larger waves.
Ocean currents: warm equatorial water flows poleward (visible as color shift over time).
Wind pushes surface water in wind direction.
No water visible on high terrain (alpha=0).
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

- [x] **12.6** Create `sys_combat.gd`
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
Phase 0 (ECS + Scaffold) ✅
  ↓
Phase 1 (Grid Data) ✅
  ↓
Phase 2 (Sphere Mesh) ✅
  ↓
Phase 3 (Multi-Noise Terrain) ✅
  ↓
Phase 4 (Multi-Noise Biomes) ✅
  ↓
Phase 5 (Camera) ✅ ←── can now inspect the world
  ↓
  ├──→ Phase 6 (Time) ✅
  │      ↓
  │    Phase 7 (Weather) ✅
  │      ├── 7b (Erosion) ✅
  │      ├── 7c (Weather Visuals) ✅
  │      ├── 7d (Tectonics) ⬜
  │      └── 7e (Volumetric Clouds) ✅
  │      ↓
  │    Phase 4b (Weather ↔ Erosion) ✅ ←── rain/wind/temp drive erosion
  │      ↓
  ├──→ Phase 8 (Flora) ← NEXT ←── weather affects flora
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
         ↓
       Phase 14 (Voxel Terrain Upgrade) ←── post-gameplay
```

---

## Phase 14: Voxel Terrain Upgrade (Astroneer-Scale)

**Goal**: Replace the 2D heightmap with a full 3D voxel terrain system. Enables caves, overhangs, arches, tunnels, deformable terrain, and subsurface layers. Inspired by Astroneer's marching cubes approach.

### Why This Is Separate
The current 2D heightmap (Phase 2-3) works well for surface-level gameplay and is sufficient for Phases 8-13. The voxel upgrade is a **major architectural change** that touches rendering, physics, pathfinding, and storage. It should be done after core gameplay is stable.

### Architecture: Astroneer-Style Voxel Planet

#### Data Model
- Replace `TorusGrid` 2D height array with `VoxelGrid` 3D density array
- Each voxel stores: `density: float` (-1.0 = air, +1.0 = solid), `material: int` (rock, soil, sand, ice, lava)
- Spherical mapping: voxel grid wraps around planet center, gravity points inward
- Resolution: 256×256×64 (surface band) — ~4M voxels per planet

#### Chunk System
- Divide voxel grid into chunks (16×16×16 voxels each)
- Only load/mesh chunks near camera + surface chunks visible from orbit
- Chunk states: UNLOADED → LOADED → MESHED → VISIBLE
- Dirty flag per chunk: only re-mesh when voxels change

#### Marching Cubes Polygonization
- Per-chunk: run marching cubes on density field to produce triangle mesh
- Smooth normals from density gradient
- Vertex colors from material type
- Generate collision mesh from same triangles

### Tasks

- [ ] **14.1** Create `planet/voxel_grid.gd` — 3D density + material storage
  - Spherical coordinate system: (r, theta, phi) mapped to voxel indices
  - `get_density(x, y, z) -> float`, `set_density(x, y, z, val)`
  - `get_material(x, y, z) -> int`
  - Wrapping on theta/phi axes (torus topology preserved)
  - Efficient storage: only allocate chunks that contain surface (sparse)

- [ ] **14.2** Create `planet/voxel_chunk.gd` — Single 16³ chunk
  - Stores local density + material arrays
  - `is_dirty: bool` flag for re-meshing
  - `mesh_instance: MeshInstance3D` for rendered geometry
  - `generate_mesh()` — run marching cubes, output ArrayMesh

- [ ] **14.3** Create `planet/marching_cubes.gd` — Polygonization algorithm
  - Standard marching cubes lookup tables (256 cases)
  - Input: 8 corner densities per cube → output: triangles
  - Smooth vertex interpolation along edges based on density values
  - Normal calculation from density gradient (central differences)
  - Material blending at transitions

- [ ] **14.4** Create `planet/voxel_chunk_manager.gd` — LOD + streaming
  - Track camera position, load/unload chunks based on distance
  - LOD levels: L0 (full detail, near camera), L1 (half res), L2 (quarter res, orbit view)
  - Chunk loading queue: max N chunks meshed per frame to avoid stuttering
  - Surface-only optimization: for orbit view, only mesh the outermost shell

- [ ] **14.5** Create `generation/gen_voxel_terrain.gd` — Procedural 3D density
  - Surface layer: 3D noise field, positive below surface, negative above
  - Caves: subtract 3D worm noise (turbulent sine paths through density)
  - Overhangs: anisotropic noise (stronger horizontal than vertical)
  - Biome layers: different material types at different depths
    - Topsoil (0-2 voxels deep): soil/sand/snow based on biome
    - Subsoil (2-8): clay/gravel
    - Bedrock (8+): rock
  - Ore veins: small positive-density blobs of special materials at depth

- [ ] **14.6** Create `systems/sys_terrain_deformation.gd` — Runtime terrain editing
  - `deform_sphere(center: Vector3, radius: float, amount: float)` — add/remove terrain
  - Used by: spell effects (volcano, earthquake, swamp), player terraform tool
  - Marks affected chunks as dirty
  - Recalculate biome/moisture for exposed surfaces

- [ ] **14.7** Migrate existing systems to voxel grid
  - `sys_hydraulic_erosion.gd` → modify surface voxel density instead of height
  - `sys_thermal_erosion.gd` → same
  - `sys_river_formation.gd` → carve river channels by removing voxels
  - `sys_volcanism.gd` → add voxels for lava/ash deposits
  - `gen_biome.gd` → sample surface voxels for temperature/moisture
  - `planet_mesh.gd` → replaced by `voxel_chunk_manager.gd`
  - `PlanetProjector` → updated to work with voxel coords

- [ ] **14.8** Cave system generation
  - Worm caves: 3D turbulent noise paths through subsurface
  - Caverns: large negative density spheres at depth
  - Cave biomes: crystal caves (ice biome), lava tubes (volcanic), fungal caves (forest)
  - Cave flora/fauna: special species that only spawn underground
  - Stalactites/stalagmites: small positive density spikes in caves

- [ ] **14.9** Performance optimization
  - Mesh generation on background thread (Godot 4 threading)
  - Greedy meshing: merge coplanar faces to reduce triangle count
  - Frustum culling per chunk
  - Occlusion: skip chunks fully behind other chunks
  - Memory budget: cap loaded chunks, LRU eviction for distant chunks
  - Target: 60 FPS with 500m view distance, 30 FPS at orbit view

- [ ] **14.10** Transition plan (heightmap → voxel)
  - Keep heightmap system working during transition (feature flag)
  - `convert_heightmap_to_voxels(grid: TorusGrid) -> VoxelGrid` — migration utility
  - Run both systems in parallel for testing
  - Once voxel system is stable: remove old heightmap code

### Verification
```
Terrain renders correctly as smooth surface from orbit (same visual as heightmap).
Zooming in: terrain has smooth marching-cubes geometry, no blocky voxels visible.
Caves visible when camera enters underground.
Deform terrain with debug tool: terrain updates in real-time, only local chunk rebuilds.
Performance: 60 FPS at ground level, 30+ FPS at orbit.
All existing systems (erosion, biomes, flora, fauna) work with voxel grid.
Save/load preserves terrain modifications.
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

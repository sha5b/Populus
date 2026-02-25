# Populus — Detailed System Specifications

> In-depth specifications for every ECS system, including state machines, algorithms, and data flows.

---

## 1. Brave AI System (`SysBraveAI`)

The most complex individual system. Replicates the original game's "smart villager" autonomous behavior.

### State Machine

```
                    ┌──────────────┐
                    │     IDLE     │
                    └──────┬───────┘
                           │
            ┌──────────────┼──────────────┬───────────────┬──────────────┐
            ▼              ▼              ▼               ▼              ▼
     ┌────────────┐ ┌────────────┐ ┌───────────┐ ┌────────────┐ ┌──────────┐
     │ HARVESTING │ │PLANNING_   │ │ENTERING_  │ │ FOLLOWING_ │ │WANDERING │
     │            │ │BUILD       │ │HUT        │ │ ORDER      │ │          │
     └─────┬──────┘ └─────┬──────┘ └───────────┘ └─────┬──────┘ └──────────┘
           │               │                            │
           ▼               ▼                            ▼
     ┌────────────┐ ┌────────────┐                ┌───────────┐
     │  BUILDING  │ │  BUILDING  │                │   IDLE    │
     └─────┬──────┘ └─────┬──────┘                └───────────┘
           │               │
           ▼               ▼
     ┌───────────┐   ┌───────────┐
     │   IDLE    │   │   IDLE    │
     └───────────┘   └───────────┘
```

### State Transitions (Pseudocode)

```gdscript
func evaluate_brave(entity: Dictionary, delta: float) -> void:
    var ai = entity["AIState"]
    var pos = entity["Position"]
    var inv = entity["Inventory"]
    var tribe = entity["Tribe"]

    match ai.current_state:
        AIState.IDLE:
            # Priority 1: Player order pending?
            if entity.has("Task") and entity["Task"].task_type != TaskType.NONE:
                ai.current_state = AIState.FOLLOWING_ORDER
                return

            # Priority 2: Nearby incomplete construction needing my help?
            var construction = find_nearest_construction(pos, tribe.tribe_id)
            if construction and inv.wood > 0:
                set_task_move_to(entity, construction.position)
                ai.current_state = AIState.BUILDING
                return

            # Priority 3: Need wood? Go harvest
            if inv.wood == 0:
                var tree = find_nearest_tree(pos)
                if tree:
                    set_task_move_to(entity, tree.position)
                    ai.current_state = AIState.HARVESTING
                    return

            # Priority 4: Should we build a new hut?
            var tribe_data = get_tribe_data(tribe.tribe_id)
            if tribe_data.housed_braves < tribe_data.total_braves * 0.8:
                var flat_spot = find_flat_terrain_for_building(pos, BuildingType.HUT_SMALL)
                if flat_spot:
                    place_construction_ghost(flat_spot, BuildingType.HUT_SMALL, tribe.tribe_id)
                    ai.current_state = AIState.PLANNING_BUILD
                    return

            # Priority 5: Is there a hut with space?
            var hut = find_hut_with_space(pos, tribe.tribe_id)
            if hut:
                set_task_move_to(entity, hut.position)
                ai.current_state = AIState.ENTERING_HUT
                return

            # Default: Wander
            ai.current_state = AIState.WANDERING
            set_task_wander(entity, pos, 5.0)

        AIState.HARVESTING:
            if not entity["Pathfinding"].is_pathing:
                # Arrived at tree
                var tree = find_tree_at(pos)
                if tree:
                    # Chop (takes time)
                    ai.state_timer -= delta
                    if ai.state_timer <= 0:
                        harvest_tree(tree, entity)  # Remove tree, add wood to inventory
                        ai.current_state = AIState.IDLE  # Will re-evaluate
                else:
                    ai.current_state = AIState.IDLE

        AIState.BUILDING:
            if not entity["Pathfinding"].is_pathing:
                var construction = find_construction_at(pos)
                if construction:
                    contribute_to_construction(entity, construction, delta)
                    if construction["Construction"].progress >= 1.0:
                        complete_construction(construction)
                        ai.current_state = AIState.IDLE
                else:
                    ai.current_state = AIState.IDLE

        AIState.ENTERING_HUT:
            if not entity["Pathfinding"].is_pathing:
                var hut = find_hut_at(pos, entity["Tribe"].tribe_id)
                if hut and hut["Garrison"].occupants.size() < hut["Garrison"].max_occupants:
                    enter_garrison(entity, hut)
                    # Entity becomes "housed" — no longer processed by movement/AI
                else:
                    ai.current_state = AIState.IDLE

        AIState.FOLLOWING_ORDER:
            if entity["Task"].task_type == TaskType.NONE:
                ai.current_state = AIState.IDLE
            # Otherwise, task system handles execution

        AIState.WANDERING:
            ai.state_timer -= delta
            if ai.state_timer <= 0:
                ai.current_state = AIState.IDLE
```

---

## 2. Tribal Strategic AI (`SysTribalAI`)

### Decision Loop (Every 5 Game Seconds)

```gdscript
func evaluate_tribe(tribe_entity: Dictionary, delta: float) -> void:
    var tribe = tribe_entity["Tribe"]
    var strategy = tribe_entity["TribalStrategy"]
    var mana = tribe_entity["Mana"]

    # 1. Gather intelligence
    var pop = get_population(tribe.tribe_id)
    var military_count = get_military_count(tribe.tribe_id)
    var enemy_threats = evaluate_all_threats(tribe.tribe_id)
    var highest_threat = get_highest_threat(enemy_threats)

    # 2. Determine strategic state
    if highest_threat > THREAT_CRITICAL:
        strategy.state = StrategyState.UNDER_ATTACK
    elif pop.total < 20:
        strategy.state = StrategyState.EARLY_GAME
    elif pop.total < 80:
        strategy.state = StrategyState.MID_GAME
    elif count_remaining_tribes() <= 1:
        strategy.state = StrategyState.WINNING
    else:
        strategy.state = StrategyState.LATE_GAME

    # 3. Execute strategy
    match strategy.state:
        StrategyState.EARLY_GAME:
            execute_expansion(tribe, pop)
        StrategyState.MID_GAME:
            execute_buildup(tribe, pop, military_count)
        StrategyState.LATE_GAME:
            execute_aggression(tribe, pop, military_count, enemy_threats)
        StrategyState.UNDER_ATTACK:
            execute_defense(tribe, highest_threat)
        StrategyState.WINNING:
            execute_finishing(tribe, military_count)

func execute_expansion(tribe, pop) -> void:
    # Ensure Braves are building huts
    var idle_braves = get_idle_braves(tribe.tribe_id)
    for brave in idle_braves:
        if not has_nearby_construction(brave):
            order_build_hut(brave)

    # Use Shaman to Flatten terrain if needed
    var shaman = get_shaman(tribe.tribe_id)
    if shaman and has_spell(shaman, SpellType.FLATTEN):
        var unflat_buildable = find_unflatten_buildable_area(tribe)
        if unflat_buildable:
            order_cast_spell(shaman, SpellType.FLATTEN, unflat_buildable)

    # Convert nearby Wildmen
    if shaman and has_spell(shaman, SpellType.CONVERT):
        var wildmen = find_nearby_wildmen(shaman, 20.0)
        if wildmen.size() > 0:
            order_cast_spell(shaman, SpellType.CONVERT, wildmen[0].position)

func execute_buildup(tribe, pop, military_count) -> void:
    # Build training buildings if missing
    if not has_building(tribe.tribe_id, BuildingType.WARRIOR_TRAINING):
        order_build(tribe.tribe_id, BuildingType.WARRIOR_TRAINING)
    if not has_building(tribe.tribe_id, BuildingType.TEMPLE_FIRE):
        order_build(tribe.tribe_id, BuildingType.TEMPLE_FIRE)

    # Train military (aim for ~40% of population)
    var target_military = pop.total * 0.4
    if military_count < target_military:
        train_units(tribe.tribe_id, RoleType.WARRIOR, 3)
        train_units(tribe.tribe_id, RoleType.FIREWARRIOR, 2)

    # Build Guard Towers at borders
    var border_tiles = find_border_tiles(tribe.tribe_id)
    for tile in border_tiles.slice(0, 3):
        if not has_guard_tower_near(tile, 5):
            order_build_at(tribe.tribe_id, BuildingType.GUARD_TOWER, tile)

func execute_aggression(tribe, pop, military_count, threats) -> void:
    var weakest_enemy = find_weakest_enemy(tribe.tribe_id)
    if military_count > 30 and weakest_enemy:
        # Assemble attack force
        var army = gather_military(tribe.tribe_id, 0.7)  # 70% of military
        var target = get_enemy_base_center(weakest_enemy)
        order_army_attack(army, target)

        # Shaman leads with spells
        var shaman = get_shaman(tribe.tribe_id)
        if shaman:
            order_follow_army(shaman, army)
            queue_spell_sequence(shaman, [
                SpellType.LIGHTNING,   # Open with damage
                SpellType.BLOODLUST,   # Buff army
                SpellType.TORNADO,     # Destroy buildings
            ])

func execute_defense(tribe, threat) -> void:
    var threat_pos = threat.position
    var military = gather_military(tribe.tribe_id, 1.0)  # ALL military
    order_army_defend(military, threat_pos)

    var shaman = get_shaman(tribe.tribe_id)
    if shaman:
        order_cast_spell(shaman, SpellType.MAGICAL_SHIELD, threat_pos)
        order_cast_spell(shaman, SpellType.BLAST, threat_pos)
```

### Threat Evaluation

```gdscript
func evaluate_threat_from(tribe_id: int, enemy_id: int) -> ThreatData:
    var threat = ThreatData.new()
    var visible_enemies = get_visible_units(tribe_id, enemy_id)

    for unit in visible_enemies:
        var role = unit["Role"].role_type
        match role:
            RoleType.WARRIOR:     threat.score += 3.0
            RoleType.FIREWARRIOR: threat.score += 2.5
            RoleType.PREACHER:    threat.score += 2.0
            RoleType.SHAMAN:      threat.score += 10.0
            RoleType.SPY:         threat.score += 1.0
            _:                    threat.score += 0.5

    # Distance factor
    var base_center = get_base_center(tribe_id)
    var closest_dist = INF
    for unit in visible_enemies:
        var d = torus_distance(unit["Position"], base_center)
        closest_dist = min(closest_dist, d)

    if closest_dist < 15.0:
        threat.score *= 3.0
        threat.is_critical = true
    elif closest_dist < 30.0:
        threat.score *= 2.0
    elif closest_dist < 50.0:
        threat.score *= 1.5

    threat.position = get_center_of_mass(visible_enemies)
    return threat
```

---

## 3. Fauna AI System (`SysFaunaAI`)

### Herbivore State Machine (Deer, Rabbit, Bison)

```gdscript
func update_herbivore(entity: Dictionary, delta: float) -> void:
    var ai = entity["AIState"]
    var hunger = entity["Hunger"]
    var prey = entity["Prey"]
    var pos = entity["Position"]

    match ai.current_state:
        AIState.IDLE:
            # Check threats
            var predator = find_nearest_predator(pos, prey.awareness_range)
            if predator:
                ai.current_state = AIState.FLEEING
                set_flee_target(entity, predator)
                return

            # Check hunger
            if hunger.current > hunger.max * 0.5:
                ai.current_state = AIState.FORAGING
                return

            # Check breeding
            if can_breed(entity):
                var mate = find_mate(entity)
                if mate:
                    ai.current_state = AIState.MATING
                    return

            # Check schedule (sleep at night)
            if entity.has("Schedule"):
                var schedule = entity["Schedule"]
                if not is_active_hour(schedule):
                    ai.current_state = AIState.SLEEPING
                    return

            # Check migration
            if entity.has("Migration"):
                if should_migrate(entity):
                    ai.current_state = AIState.MIGRATING
                    return

            # Default: wander within herd
            ai.current_state = AIState.WANDERING

        AIState.FORAGING:
            var food = find_food_source(pos, entity["Species"])
            if food:
                if torus_distance(pos, food.position) < 1.5:
                    # Eating
                    hunger.current -= hunger.eat_rate * delta
                    hunger.current = max(hunger.current, 0.0)
                    if hunger.current < hunger.max * 0.2:
                        ai.current_state = AIState.IDLE
                else:
                    # Walk to food
                    request_path(entity, food.position)
            else:
                # No food: wander to find some
                set_task_wander(entity, pos, 10.0)
                ai.state_timer = 5.0

            # Always check for predators while foraging
            var predator = find_nearest_predator(pos, prey.awareness_range)
            if predator:
                ai.current_state = AIState.FLEEING
                set_flee_target(entity, predator)

        AIState.FLEEING:
            var predator = find_nearest_predator(pos, prey.awareness_range * 1.5)
            if predator:
                # Run away from predator
                var flee_dir = (pos.world_pos - predator["Position"].world_pos).normalized()
                entity["Velocity"].direction = Vector2(flee_dir.x, flee_dir.z)
                entity["Velocity"].speed = entity["Species"].move_speed * prey.flee_speed_bonus
            else:
                # Predator gone, calm down
                entity["Velocity"].speed = 0
                ai.current_state = AIState.IDLE

        AIState.MATING:
            var mate = entity["_mate_target"]
            if mate and torus_distance(pos, mate["Position"]) < 2.0:
                start_gestation(entity)
                ai.current_state = AIState.IDLE
            elif mate:
                request_path(entity, mate["Position"].grid_pos)
            else:
                ai.current_state = AIState.IDLE

        AIState.SLEEPING:
            entity["Velocity"].speed = 0
            if entity.has("Schedule") and is_active_hour(entity["Schedule"]):
                ai.current_state = AIState.IDLE

        AIState.MIGRATING:
            var migration = entity["Migration"]
            if not migration.is_migrating:
                var target = find_better_biome(entity)
                if target:
                    migration.target = target
                    migration.is_migrating = true
                    request_path(entity, target)
                else:
                    ai.current_state = AIState.IDLE
                    return
            if reached_target(entity, migration.target):
                migration.is_migrating = false
                ai.current_state = AIState.IDLE
```

### Predator State Machine (Wolf, Bear, Eagle)

```gdscript
func update_predator(entity: Dictionary, delta: float) -> void:
    var ai = entity["AIState"]
    var hunger = entity["Hunger"]
    var predator = entity["Predator"]
    var pos = entity["Position"]

    match ai.current_state:
        AIState.IDLE:
            if hunger.current > hunger.max * 0.4:
                ai.current_state = AIState.HUNTING
                return
            if can_breed(entity):
                var mate = find_mate(entity)
                if mate:
                    ai.current_state = AIState.MATING
                    return
            if entity.has("Schedule") and not is_active_hour(entity["Schedule"]):
                ai.current_state = AIState.SLEEPING
                return
            ai.current_state = AIState.WANDERING

        AIState.HUNTING:
            var prey_target = find_nearest_prey(pos, predator.prey_types, predator.hunt_range)
            if prey_target:
                var dist = torus_distance(pos, prey_target["Position"])
                if dist < 1.5:
                    # Attack
                    deal_damage(prey_target, predator.attack_damage * delta * 10)
                    if prey_target["Health"].current_hp <= 0:
                        # Kill confirmed
                        hunger.current -= hunger.max * 0.6  # Big meal
                        hunger.current = max(hunger.current, 0.0)
                        kill_entity(prey_target)
                        ai.current_state = AIState.IDLE
                else:
                    # Chase
                    entity["Velocity"].direction = direction_to(pos, prey_target["Position"])
                    entity["Velocity"].speed = entity["Species"].move_speed * 1.2
            else:
                # No prey found, wander and search
                set_task_wander(entity, pos, 15.0)
                ai.state_timer -= delta
                if ai.state_timer <= 0:
                    ai.current_state = AIState.IDLE

        AIState.SLEEPING:
            entity["Velocity"].speed = 0
            if entity.has("Schedule") and is_active_hour(entity["Schedule"]):
                ai.current_state = AIState.IDLE
```

---

## 4. Herd / Flocking System (`SysHerd`)

Implements **Boids** algorithm for herding animals.

```gdscript
func update_herd(entity: Dictionary, delta: float) -> void:
    if entity["AIState"].current_state in [AIState.FLEEING, AIState.HUNTING]:
        return  # Don't flock while fleeing or hunting

    var herd = entity["Herd"]
    var pos = entity["Position"].world_pos
    var herd_members = get_herd_members(herd.herd_id)

    if herd_members.size() <= 1:
        return

    var separation = Vector3.ZERO
    var cohesion = Vector3.ZERO
    var alignment = Vector3.ZERO
    var count = 0

    for member in herd_members:
        if member == entity:
            continue
        var other_pos = member["Position"].world_pos
        var dist = pos.distance_to(other_pos)

        # Separation: steer away from close neighbors
        if dist < herd.separation_dist and dist > 0.01:
            separation += (pos - other_pos).normalized() / dist

        # Cohesion: steer toward center of herd
        if dist < herd.cohesion_dist:
            cohesion += other_pos
            count += 1

        # Alignment: match velocity of neighbors
        if dist < herd.cohesion_dist:
            alignment += member["Velocity"].direction_3d()

    if count > 0:
        cohesion = (cohesion / count - pos).normalized()
        alignment = (alignment / count).normalized()

    # Combine forces
    var steer = separation * 1.5 + cohesion * 1.0 + alignment * 1.0
    if steer.length() > 0.01:
        var dir_2d = Vector2(steer.x, steer.z).normalized()
        entity["Velocity"].direction = entity["Velocity"].direction.lerp(dir_2d, 0.1)
```

---

## 5. Weather System (`SysWeather`)

### State Machine

```
           60%                20%
  ┌──── CLEAR ────────── CLOUDY ──────┐
  │       ▲                  │         │
  │       │ 40%         50%  │    30%  │
  │       │                  ▼         ▼
  │   CLEARING ◄──────── RAIN ────── STORM
  │       ▲           30%    │    20%  │
  │       │                  │         │
  │       └──────────────────┴─────────┘
  │                     via CLEARING
  └─────────── (stays clear) ─────────┘

Transition check every: 30-60 game seconds (randomized)
```

### Weather Processing

```gdscript
func _on_update(delta: float) -> void:
    var weather = get_global_weather()

    weather.transition_timer -= delta
    if weather.transition_timer <= 0:
        weather.transition_timer = randf_range(30.0, 60.0)
        attempt_transition(weather)

    # Apply continuous effects
    match weather.current_state:
        WeatherState.CLEAR:
            # Slowly decrease moisture on tiles
            modify_global_moisture(-0.001 * delta)

        WeatherState.RAIN:
            # Increase moisture, extinguish fires
            modify_global_moisture(0.01 * delta)
            extinguish_fires_in_rain(delta)
            # Chance of flooding in low areas
            if randf() < 0.001 * delta:
                flood_low_area()

        WeatherState.STORM:
            # Heavy rain + lightning
            modify_global_moisture(0.02 * delta)
            extinguish_fires_in_rain(delta)
            # Random lightning strikes
            if randf() < 0.01 * delta:
                var strike_pos = random_land_tile()
                lightning_strike(strike_pos)  # Damage + fire
            # Wind speed spike
            modify_global_wind_speed(2.0)

        WeatherState.CLOUDY:
            # Mild moisture increase
            modify_global_moisture(0.002 * delta)

        WeatherState.CLEARING:
            # Transition back to clear
            modify_global_moisture(-0.005 * delta)

func attempt_transition(weather) -> void:
    var roll = randf()
    match weather.current_state:
        WeatherState.CLEAR:
            if roll < 0.2:
                weather.current_state = WeatherState.CLOUDY
        WeatherState.CLOUDY:
            if roll < 0.5:
                weather.current_state = WeatherState.RAIN
            elif roll < 0.7:
                weather.current_state = WeatherState.CLEAR
        WeatherState.RAIN:
            if roll < 0.3:
                weather.current_state = WeatherState.STORM
            elif roll < 0.6:
                weather.current_state = WeatherState.CLEARING
        WeatherState.STORM:
            if roll < 0.4:
                weather.current_state = WeatherState.CLEARING
            elif roll < 0.6:
                weather.current_state = WeatherState.RAIN
        WeatherState.CLEARING:
            weather.current_state = WeatherState.CLEAR
```

---

## 6. Spell Effect Processing (`SysSpellEffect`)

### Per-Spell Processing

```gdscript
func process_spell_effect(effect: Dictionary, delta: float) -> void:
    var spell = effect["SpellEffect"]
    spell.timer -= delta

    match spell.spell_type:
        SpellType.FLATTEN:
            flatten_terrain(spell.position, spell.radius)

        SpellType.RAISE:
            modify_terrain_height(spell.position, spell.radius, 1.0)

        SpellType.LOWER:
            modify_terrain_height(spell.position, spell.radius, -1.0)

        SpellType.LANDBRIDGE:
            var caster_pos = spell.caster_position
            var target_pos = spell.position
            var path = bresenham_line(caster_pos, target_pos)
            for tile in path:
                for dx in range(-1, 2):
                    for dy in range(-1, 2):
                        var h = grid.get_height(tile.x + dx, tile.y + dy)
                        if h < grid.sea_level + 0.5:
                            grid.set_height(tile.x + dx, tile.y + dy, grid.sea_level + 0.5)

        SpellType.VOLCANO:
            if spell.timer > spell.duration * 0.8:
                # Initial eruption: create height cone
                create_height_cone(spell.position, spell.radius, spell.terrain_height_add)
            # Continuous: lava damage
            damage_entities_in_radius(spell.position, spell.radius, 20.0 * delta)
            ignite_flora_in_radius(spell.position, spell.radius)

        SpellType.EARTHQUAKE:
            # Randomize terrain heights
            randomize_terrain(spell.position, spell.radius, spell.terrain_disruption)
            # Damage buildings
            var buildings = find_buildings_in_radius(spell.position, spell.radius)
            for bld in buildings:
                bld["Health"].current_hp -= spell.building_damage * delta / spell.duration

        SpellType.TORNADO:
            # Move tornado in random direction
            spell.position += random_direction() * 2.0 * delta
            # Destroy buildings
            var buildings = find_buildings_in_radius(spell.position, 3.0)
            for bld in buildings:
                bld["Health"].current_hp -= spell.building_damage * delta
            # Fling units
            var units = find_units_in_radius(spell.position, 3.0)
            for unit in units:
                apply_knockback(unit, spell.position, 10.0)
                deal_damage(unit, spell.damage * delta)

        SpellType.LIGHTNING:
            # Instant: chain lightning
            var targets = find_enemies_in_radius(spell.position, spell.radius)
            targets.sort_custom(func(a, b): return distance(spell.position, a) < distance(spell.position, b))
            for i in range(min(spell.chain_targets, targets.size())):
                deal_damage(targets[i], spell.damage * (1.0 - i * 0.3))

        SpellType.SWAMP:
            # Create swamp tiles that slow and damage
            apply_swamp_tiles(spell.position, spell.radius)
            var units = find_units_in_radius(spell.position, spell.radius)
            for unit in units:
                unit["Velocity"].speed *= spell.slow_factor
                deal_damage(unit, spell.damage_per_second * delta)

        SpellType.FIRESTORM:
            # Rain fire on area
            var positions = random_positions_in_radius(spell.position, spell.radius, 5)
            for p in positions:
                ignite_at(p)
                var units = find_units_in_radius(p, 2.0)
                for unit in units:
                    deal_damage(unit, spell.damage * delta)

        SpellType.ANGEL_OF_DEATH:
            # Seek and destroy enemies
            var target = find_nearest_enemy(spell.position, spell.caster_tribe)
            if target:
                var dir = direction_to(spell.position, target["Position"])
                spell.position += dir * spell.hunt_speed * delta
                if distance(spell.position, target["Position"]) < 2.0:
                    deal_damage(target, spell.damage_per_hit)
                    spell.kill_cooldown = 1.0

        SpellType.CONVERT:
            var targets = find_enemies_in_radius(spell.position, spell.radius)
            for target in targets:
                if target["Role"].role_type == RoleType.WILDMAN or true:
                    apply_conversion(target, spell.caster_tribe, spell.conversion_strength)

        SpellType.INVISIBILITY:
            var allies = find_allies_in_radius(spell.position, spell.radius, spell.caster_tribe)
            for ally in allies:
                set_invisible(ally, true)

        SpellType.MAGICAL_SHIELD:
            var allies = find_allies_in_radius(spell.position, spell.radius, spell.caster_tribe)
            for ally in allies:
                set_shielded(ally, spell.damage_reduction)

        SpellType.BLOODLUST:
            var allies = find_allies_in_radius(spell.position, spell.radius, spell.caster_tribe)
            for ally in allies:
                ally["Combat"].attack_damage *= spell.damage_bonus
                ally["Velocity"].speed *= spell.speed_bonus

        SpellType.TELEPORT:
            teleport_entity(spell.caster_entity, spell.position)

        SpellType.SWARM:
            var enemies = find_enemies_in_radius(spell.position, spell.radius)
            for enemy in enemies:
                apply_confusion(enemy, spell.confusion_duration)

        SpellType.GHOST_ARMY:
            spawn_ghost_units(spell.position, spell.caster_tribe, spell.ghost_count, spell.duration)

        SpellType.HYPNOTISE:
            var target = find_nearest_enemy(spell.position, spell.caster_tribe)
            if target:
                temporarily_convert(target, spell.caster_tribe, spell.duration)

        SpellType.ARMAGEDDON:
            teleport_all_to_arena()

    # Remove expired effects
    if spell.timer <= 0:
        remove_entity(effect)
```

---

## 7. Population System (`SysPopulation`)

```gdscript
func _on_update(delta: float) -> void:
    # For each tribe
    for tribe_entity in world().multi_view(["Tribe", "Mana"]):
        var tribe = tribe_entity["Tribe"]
        var pop = count_population(tribe.tribe_id)
        var max_pop = GameConfig.MAX_POPULATION

        if pop.total >= max_pop:
            continue

        # Check each hut for Brave production
        var huts = get_huts(tribe.tribe_id)
        for hut in huts:
            var garrison = hut["Garrison"]
            var production = hut["Production"]

            if garrison.occupants.size() == 0:
                continue  # Empty huts don't produce

            production.production_timer -= delta
            if production.production_timer <= 0:
                production.production_timer = production.production_interval
                if pop.total < max_pop:
                    spawn_brave_at_hut(hut, tribe.tribe_id)
                    pop.total += 1
```

---

## 8. Mana System (`SysMana`)

```gdscript
func _on_update(delta: float) -> void:
    for tribe_entity in world().multi_view(["Tribe", "Mana"]):
        var tribe = tribe_entity["Tribe"]
        var mana = tribe_entity["Mana"]

        # Count housed braves
        var housed = count_housed_braves(tribe.tribe_id)

        # Generate mana
        mana.regen_rate = housed * GameConfig.MANA_PER_BRAVE_PER_SECOND
        mana.current_mana += mana.regen_rate * delta
        mana.current_mana = min(mana.current_mana, mana.max_mana)

        # Auto-recharge spell charges
        var shaman = get_shaman(tribe.tribe_id)
        if shaman and shaman.has("SpellCaster"):
            for spell_charge in get_spell_charges(tribe.tribe_id):
                if spell_charge.charges < spell_charge.max_charges:
                    var cost = get_spell_cost(spell_charge.spell_type)
                    if mana.current_mana >= cost:
                        mana.current_mana -= cost
                        spell_charge.charges += 1
```

---

## 9. Construction System (`SysConstruction`)

```gdscript
func _on_update(delta: float) -> void:
    for building in world().multi_view(["Construction", "Position"]):
        var construction = building["Construction"]
        var pos = building["Position"]

        # Check if enough wood has been delivered
        if construction.consumed_wood < construction.required_wood:
            continue  # Waiting for Braves to deliver wood

        # Count active builders nearby
        var builders = count_builders_at(pos, building["Tribe"].tribe_id)
        if builders == 0:
            continue

        # Progress construction
        var speed = builders * GameConfig.BUILD_SPEED_PER_BRAVE
        construction.progress += speed * delta

        if construction.progress >= 1.0:
            complete_building(building)
            emit_event(EventType.BUILDING_COMPLETED, {
                "building_id": building.entity_id,
                "tribe_id": building["Tribe"].tribe_id,
                "type": building["Building"].building_type if building.has("Building") else construction.building_type,
            })
```

---

## 10. Pathfinding System (`SysPathfinding`)

### A* on Torus Grid

```gdscript
func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
    var open_set = PriorityQueue.new()
    var came_from = {}
    var g_score = {}
    var f_score = {}

    g_score[start] = 0.0
    f_score[start] = torus_heuristic(start, goal)
    open_set.push(start, f_score[start])

    while not open_set.is_empty():
        var current = open_set.pop()

        if current == goal:
            return reconstruct_path(came_from, current)

        for neighbor in get_walkable_neighbors(current):
            var move_cost = get_movement_cost(current, neighbor)
            var tentative_g = g_score[current] + move_cost

            if tentative_g < g_score.get(neighbor, INF):
                came_from[neighbor] = current
                g_score[neighbor] = tentative_g
                f_score[neighbor] = tentative_g + torus_heuristic(neighbor, goal)
                if not open_set.contains(neighbor):
                    open_set.push(neighbor, f_score[neighbor])

    return []  # No path found

func torus_heuristic(a: Vector2i, b: Vector2i) -> float:
    var dx = mini(absi(a.x - b.x), grid_width - absi(a.x - b.x))
    var dy = mini(absi(a.y - b.y), grid_height - absi(a.y - b.y))
    return sqrt(float(dx * dx + dy * dy))

func get_movement_cost(from: Vector2i, to: Vector2i) -> float:
    var base_cost = 1.0
    var biome_cost = BIOME_MOVEMENT_COST[get_biome(to)]
    var slope_cost = abs(get_height(to) - get_height(from)) * 0.5
    return base_cost * biome_cost + slope_cost

func get_walkable_neighbors(pos: Vector2i) -> Array[Vector2i]:
    var neighbors = []
    for offset in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0),
                   Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]:
        var n = Vector2i(wrap_x(pos.x + offset.x), wrap_y(pos.y + offset.y))
        if not is_water(n) and not has_blocking_building(n):
            neighbors.append(n)
    return neighbors
```

### Flow Field (For Large Groups)

```gdscript
func compute_flow_field(goal: Vector2i) -> Dictionary:
    # BFS from goal outward
    var distance = {}
    var flow = {}
    var queue = [goal]
    distance[goal] = 0

    while queue.size() > 0:
        var current = queue.pop_front()
        for neighbor in get_walkable_neighbors(current):
            if not distance.has(neighbor):
                distance[neighbor] = distance[current] + get_movement_cost(current, neighbor)
                # Flow direction = toward lower distance
                flow[neighbor] = direction_to_grid(neighbor, current)
                queue.append(neighbor)

    return flow  # Dict[Vector2i] → Vector2 direction

# Usage: each unit in the group just looks up flow[my_position] to get move direction
```

---

*This document supplements [DOCS.md](DOCS.md) with implementation-level detail.*
*See [PLAN.md](PLAN.md) for the build schedule.*

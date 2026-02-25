extends Node
class_name EcsWorld

var _next_id: int = 1
var entities: Dictionary = {}
var components: Dictionary = {}
var systems: Array = []
var _query_cache: Dictionary = {}
var _cache_generation: int = 0


func create_entity() -> Entity:
	var e := Entity.new(_next_id)
	entities[_next_id] = e
	_next_id += 1
	return e


func add_component(entity: Entity, component: Component) -> void:
	var t := component.get_type()
	if not components.has(t):
		components[t] = {}
	components[t][entity.id] = component
	_cache_generation += 1


func get_component(entity_id: int, comp_type: String) -> Component:
	if components.has(comp_type) and components[comp_type].has(entity_id):
		return components[comp_type][entity_id]
	return null


func get_components(comp_type: String) -> Dictionary:
	return components.get(comp_type, {})


func query(required: Array[String]) -> Array[int]:
	if required.is_empty():
		return []
	var cache_key := ",".join(required)
	if _query_cache.has(cache_key):
		var cached: Array = _query_cache[cache_key]
		if cached[0] == _cache_generation:
			return cached[1]
	var base := get_components(required[0])
	var result: Array[int] = []
	for id in base.keys():
		var ok := true
		for i in range(1, required.size()):
			if not get_components(required[i]).has(id):
				ok = false
				break
		if ok:
			result.append(id)
	_query_cache[cache_key] = [_cache_generation, result]
	return result


func remove_entity(entity_id: int) -> void:
	entities.erase(entity_id)
	for comp_type in components.keys():
		components[comp_type].erase(entity_id)
	_cache_generation += 1


func add_system(system: System) -> void:
	systems.append(system)


func get_entity_count() -> int:
	return entities.size()


func _process(delta: float) -> void:
	for system in systems:
		system.update(self, delta)

extends RefCounted
class_name ExpeditionEventSystem

# Event content lives in ContentRegistry; this system only selects a weighted,
# valid event. Choosing an option and applying its effects belongs to the manager.
func draw_event(rng: RandomNumberGenerator, loop_count: int, previous_event_id: String = "", flags: Dictionary = {}) -> Dictionary:
	var candidates: Array = []
	var total_weight: float = 0.0
	for event_id_value in ContentRegistry.EXPEDITION_EVENTS.keys():
		var event_id: String = str(event_id_value)
		var definition: Dictionary = ContentRegistry.EXPEDITION_EVENTS[event_id]
		if int(definition.get("min_loop", 0)) > loop_count:
			continue
		if event_id == previous_event_id and ContentRegistry.EXPEDITION_EVENTS.size() > 1:
			continue
		var required_flag := str(definition.get("requires_flag", ""))
		if not required_flag.is_empty() and not bool(flags.get(required_flag, false)):
			continue
		var excluded_flag := str(definition.get("excludes_flag", ""))
		if not excluded_flag.is_empty() and bool(flags.get(excluded_flag, false)):
			continue
		var weight: float = maxf(0.01, float(definition.get("weight", 1.0)))
		if not required_flag.is_empty():
			weight *= maxf(1.0, float(definition.get("chain_weight_multiplier", 2.0)))
		candidates.append({"id": event_id, "weight": weight, "definition": definition})
		total_weight += weight
	if candidates.is_empty():
		return {}
	var roll: float = rng.randf() * total_weight
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		roll -= float(candidate.get("weight", 1.0))
		if roll <= 0.0:
			var definition_value: Variant = candidate.get("definition", {})
			if typeof(definition_value) != TYPE_DICTIONARY:
				return {}
			var result: Dictionary = definition_value.duplicate(true)
			result["id"] = str(candidate.get("id", ""))
			return result
	var fallback: Dictionary = candidates[candidates.size() - 1]
	var fallback_value: Variant = fallback.get("definition", {})
	if typeof(fallback_value) != TYPE_DICTIONARY:
		return {}
	var fallback_result: Dictionary = fallback_value.duplicate(true)
	fallback_result["id"] = str(fallback.get("id", ""))
	return fallback_result

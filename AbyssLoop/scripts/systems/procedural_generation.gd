extends RefCounted
class_name ProceduralGeneration

static func generate_route(seed_value: int, cell_count: int, safe_intro_nodes: int = 3) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var route: Array = []
	var route_length := maxi(6, cell_count)
	var safe_prefix := clampi(safe_intro_nodes, 1, mini(5, route_length - 3))
	for i in range(route_length):
		var kind := "plain"
		if i == 0:
			kind = "shrine"
		elif i < safe_prefix:
			# The opening steps teach movement before introducing a risk/event decision.
			kind = "plain"
		else:
			var roll := rng.randf()
			if roll < 0.12:
				kind = "cache"
			elif roll < 0.23:
				kind = "event"
			elif roll < 0.34:
				kind = "danger"
			elif roll < 0.42:
				kind = "shrine"
		route.append({"index": i, "kind": kind, "seed_tag": rng.randi()})
	# Every route should showcase the choice-driven event system, while also
	# guaranteeing at least one material opportunity and one risky location.
	if route.size() > 7:
		if not _contains_kind(route, "event"):
			route[route.size() - 5]["kind"] = "event"
		if not _contains_kind(route, "cache"):
			route[4]["kind"] = "cache"
		if not _contains_kind(route, "danger"):
			route[route.size() - 3]["kind"] = "danger"
	return route

static func _contains_kind(route: Array, kind: String) -> bool:
	for cell in route:
		if str(cell.get("kind", "")) == kind:
			return true
	return false

static func create_seed() -> int:
	return int(Time.get_unix_time_from_system()) ^ int(randi())

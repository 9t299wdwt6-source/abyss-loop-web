extends RefCounted
class_name RouteSystem

const ProceduralGenerationScript = preload("res://scripts/systems/procedural_generation.gd")

## Every expedition route is a single closed loop. The last node always links
## back to node zero; there is no open-route or tower-defence mode.
func create_route(seed_value: int, cell_count: int) -> Array:
	return bind_closed_loop(ProceduralGenerationScript.generate_route(seed_value, cell_count, int(ContentRegistry.BALANCE.get("safe_intro_route_nodes", 3))))

## Add explicit topology metadata while preserving all content-specific fields.
## Also used to normalize saved routes written by earlier prototypes.
func bind_closed_loop(route: Array) -> Array:
	var result: Array = []
	var count := route.size()
	if count == 0:
		return result
	for i in range(count):
		var source: Variant = route[i]
		var cell: Dictionary = source.duplicate(true) if typeof(source) == TYPE_DICTIONARY else {}
		cell["index"] = i
		cell["loop_id"] = "main_loop"
		cell["loop_closed"] = true
		cell["previous_index"] = posmod(i - 1, count)
		cell["next_index"] = posmod(i + 1, count)
		result.append(cell)
	return result

func is_closed_loop(route: Array) -> bool:
	if route.size() < 6:
		return false
	var count := route.size()
	for i in range(count):
		if typeof(route[i]) != TYPE_DICTIONARY:
			return false
		var cell: Dictionary = route[i]
		if not bool(cell.get("loop_closed", false)):
			return false
		if str(cell.get("loop_id", "")) != "main_loop":
			return false
		if int(cell.get("index", -1)) != i:
			return false
		if int(cell.get("previous_index", -1)) != posmod(i - 1, count):
			return false
		if int(cell.get("next_index", -1)) != posmod(i + 1, count):
			return false
	return true

func get_cell_kind(route: Array, index: int) -> String:
	if route.is_empty():
		return "plain"
	var safe_index: int = posmod(index, route.size())
	return str(route[safe_index].get("kind", "plain"))

func next_index(index: int, cell_count: int) -> int:
	if cell_count <= 0:
		return 0
	return posmod(index + 1, cell_count)

func previous_index(index: int, cell_count: int) -> int:
	if cell_count <= 0:
		return 0
	return posmod(index - 1, cell_count)

func route_progress(distance: float, cell_count: int) -> Dictionary:
	if cell_count <= 0:
		return {"index": 0, "fraction": 0.0, "loops": 0}
	var steps := maxi(0, int(floor(distance)))
	return {
		"index": posmod(steps, cell_count),
		"fraction": clampf(distance - floor(distance), 0.0, 0.9999),
		"loops": int(steps / cell_count)
	}

extends Node

const ExpeditionManagerScript = preload("res://scripts/systems/expedition_manager.gd")
const TEST_HERO_STAT: int = 1000000
const MAX_STEPS_PER_FLOOR: int = 5000
const ROUTE_SCALED_DELTA: float = 1.24
const COMBAT_SCALED_DELTA: float = 0.05

var _checks: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run_acceptance")

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", description)
	else:
		_failures.append(description)
		printerr("FAIL: ", description)

func _run_acceptance() -> void:
	print("Abyss Loop eight-floor campaign runtime acceptance — real manager and durable floor unlocks")
	GameState.reset_progress()
	await get_tree().process_frame
	_check(int(GameState.highest_unlocked_floor) == 1, "a fresh campaign starts with only floor one unlocked")
	_check(not GameState.has_saved_expedition(), "the isolated test profile begins without a stale expedition checkpoint")

	var locked_manager = ExpeditionManagerScript.new()
	get_tree().root.add_child(locked_manager)
	await get_tree().process_frame
	var locked_start: bool = bool(locked_manager.start_run("standard", 881001, "standard", "none", "standard", 2))
	_check(not locked_start, "a locked floor cannot be started")
	locked_manager.queue_free()
	await get_tree().process_frame

	var floor_one: Dictionary = await _complete_floor(1, 881101)
	_check(bool(floor_one.get("floor_cleared", false)), "the first guardian victory durably completes floor one")
	_check(int(floor_one.get("floor_number", 0)) == 1, "the first durable result identifies floor one")
	_check(int(GameState.highest_unlocked_floor) == 2, "settling floor one unlocks floor two")
	_check(not GameState.has_saved_expedition(), "successful floor settlement removes the active checkpoint")

	var floor_two: Dictionary = await _complete_floor(2, 881201)
	_check(bool(floor_two.get("floor_cleared", false)), "the second guardian victory durably completes floor two")
	_check(int(floor_two.get("floor_number", 0)) == 2, "the second durable result identifies floor two")
	_check(int(GameState.highest_unlocked_floor) == 3, "settling floor two unlocks floor three")
	_check(int(GameState.runs_completed) == 2, "two completed floors create two separate durable settlements")

	GameState.reset_progress()
	await get_tree().process_frame
	if _failures.is_empty():
		print("FLOOR PROGRESSION RUNTIME ACCEPTANCE PASSED: %d checks" % _checks)
		get_tree().quit(0)
	else:
		printerr("FLOOR PROGRESSION RUNTIME ACCEPTANCE FAILED: %d/%d checks failed" % [_failures.size(), _checks])
		for failure in _failures:
			printerr(" - ", failure)
		get_tree().quit(1)

func _complete_floor(floor_number: int, seed_value: int) -> Dictionary:
	var manager = ExpeditionManagerScript.new()
	manager.name = "FloorProgressionAcceptance_%d" % floor_number
	get_tree().root.add_child(manager)
	await get_tree().process_frame
	var started: bool = bool(manager.start_run("standard", seed_value, "standard", "none", "standard", floor_number))
	_check(started, "unlocked floor %d starts from its own deterministic seed" % floor_number)
	if not started:
		manager.queue_free()
		await get_tree().process_frame
		return {}
	manager.set_pause(true)
	manager.set_speed(3.0)
	_set_test_hero_strength(manager)
	var steps: int = 0
	while bool(manager.active) and steps < MAX_STEPS_PER_FLOOR:
		steps += 1
		if not str(manager.pending_end_outcome).is_empty():
			_check(false, "floor %d does not remain stuck after a failed settlement" % floor_number)
			break
		if not manager.pending_event.is_empty():
			manager.run_ledger["scrap"] = maxi(100000, int(manager.run_ledger.get("scrap", 0)))
			manager.run_ledger["crystals"] = maxi(100000, int(manager.run_ledger.get("crystals", 0)))
			var choice_id := _first_available_event_choice(manager)
			if choice_id.is_empty():
				_check(false, "floor %d event has at least one actionable choice" % floor_number)
				break
			var event_result: Dictionary = manager.resolve_event_choice(choice_id)
			if not bool(event_result.get("ok", false)):
				_check(false, "floor %d event choice resolves through the production handler" % floor_number)
				break
			continue
		if int(manager.pending_perk_count) > 0:
			var perk_id := _first_offered_perk(manager)
			if perk_id.is_empty() or not bool(manager.choose_perk(perk_id)):
				_check(false, "floor %d level-up has a valid perk choice" % floor_number)
				break
			_set_test_hero_strength(manager)
			continue
		if not manager.enemy.is_empty():
			_set_test_hero_strength(manager)
			manager.combat_timers["hero"] = 1000.0
			manager._tick_combat(COMBAT_SCALED_DELTA)
			continue
		var previous_steps: int = int(manager.processed_steps)
		manager.distance = float(previous_steps)
		manager._tick_route(ROUTE_SCALED_DELTA)
		if bool(manager.active) and int(manager.processed_steps) == previous_steps and manager.enemy.is_empty() and manager.pending_event.is_empty() and int(manager.pending_perk_count) == 0:
			_check(false, "floor %d route progresses when no encounter or decision is pending" % floor_number)
			break
	if bool(manager.active):
		_check(false, "floor %d guardian is reached and settled within the bounded simulation" % floor_number)
		manager.active = false
	var summary: Dictionary = GameState.last_summary.duplicate(true)
	manager.queue_free()
	await get_tree().process_frame
	_check(not summary.is_empty() and int(summary.get("floor_number", 0)) == floor_number, "floor %d produces a durable summary tagged with its floor number" % floor_number)
	return summary

func _set_test_hero_strength(manager: Variant) -> void:
	# Test-only hero values shorten fights; this validates floor progression and settlement,
	# not combat balance. Balance capture uses production values without forced stats.
	manager.hero["base_hp"] = TEST_HERO_STAT
	manager.hero["max_hp"] = TEST_HERO_STAT
	manager.hero["hp"] = TEST_HERO_STAT
	manager.hero["base_attack"] = TEST_HERO_STAT
	manager.hero["attack"] = TEST_HERO_STAT
	manager.hero["base_defense"] = TEST_HERO_STAT
	manager.hero["defense"] = TEST_HERO_STAT

func _first_available_event_choice(manager: Variant) -> String:
	var choices_value: Variant = manager.pending_event.get("choices", [])
	if typeof(choices_value) != TYPE_ARRAY:
		return ""
	for choice_value in choices_value:
		if typeof(choice_value) == TYPE_DICTIONARY:
			var choice: Dictionary = choice_value
			var choice_id := str(choice.get("id", ""))
			if not choice_id.is_empty() and bool(manager.event_choice_is_available(choice_id)):
				return choice_id
	return ""

func _first_offered_perk(manager: Variant) -> String:
	var choices_value: Variant = manager.pending_perk_choices
	if typeof(choices_value) != TYPE_ARRAY or choices_value.is_empty():
		return ""
	var first: Variant = choices_value[0]
	if typeof(first) == TYPE_DICTIONARY:
		return str(first.get("id", ""))
	return str(first)

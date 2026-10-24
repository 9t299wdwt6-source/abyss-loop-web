extends Node

const ExpeditionManagerScript = preload("res://scripts/systems/expedition_manager.gd")
const LONG_SEED: int = 8675309
const TEST_HERO_HP: int = 1000000
const MAX_INTERACTIONS: int = 2400

var _check_count: int = 0
var _failures: Array[String] = []
var _boss_loops_seen: Array[int] = []

func _ready() -> void:
	call_deferred("_run_acceptance")

func _check(condition: bool, description: String) -> void:
	_check_count += 1
	if condition:
		print("PASS: ", description)
	else:
		_failures.append(description)
		printerr("FAIL: ", description)

func _finish() -> void:
	if _failures.is_empty():
		print("LONG EXPEDITION RUNTIME ACCEPTANCE PASSED: %d checks" % _check_count)
		get_tree().quit(0)
	else:
		printerr("LONG EXPEDITION RUNTIME ACCEPTANCE FAILED: %d/%d checks failed" % [_failures.size(), _check_count])
		for failure in _failures:
			printerr(" - ", failure)
		get_tree().quit(1)

func _run_acceptance() -> void:
	Engine.max_fps = 60
	print("Abyss Loop long-expedition runtime acceptance — real manager, 12 route loops, isolated CI profile")
	GameState.reset_progress()
	await get_tree().process_frame
	_check(not GameState.has_saved_expedition(), "long-expedition test begins with a clean profile and no checkpoint")

	var manager = ExpeditionManagerScript.new()
	manager.name = "LongExpeditionRuntimeAcceptance"
	get_tree().root.add_child(manager)
	await get_tree().process_frame
	var started: bool = bool(manager.start_run("standard", LONG_SEED, "standard", "none", "long_expedition"))
	_check(started, "the real ExpeditionManager accepts a deterministic long-expedition start")
	if not started:
		manager.queue_free()
		await get_tree().process_frame
		_finish()
		return

	manager.set_pause(true)
	_keep_test_hero_alive(manager)
	_check(str(manager.expedition_mode_id) == "long_expedition", "the active run uses the dedicated long-expedition mode")
	_check(int(manager.get_expedition_goal_progress().get("target_loops", 0)) == 12, "the mode declares a 12-loop target")
	_check(int(manager.get_expedition_goal_progress().get("target_bosses", 0)) == 4, "the mode requires four boss victories")

	var interactions := 0
	while bool(manager.active) and interactions < MAX_INTERACTIONS:
		interactions += 1
		_keep_test_hero_alive(manager)

		if not str(manager.pending_end_outcome).is_empty():
			_check(false, "the run never becomes stuck in a failed settlement transaction")
			break

		if not manager.pending_event.is_empty():
			manager.run_ledger["scrap"] = maxi(100000, int(manager.run_ledger.get("scrap", 0)))
			manager.run_ledger["crystals"] = maxi(100000, int(manager.run_ledger.get("crystals", 0)))
			var choice_id := _first_available_event_choice(manager)
			if choice_id.is_empty():
				_check(false, "every generated event has an available choice during the long run")
				break
			var event_result: Dictionary = manager.resolve_event_choice(choice_id)
			_check(bool(event_result.get("ok", false)), "a real event choice resolves during the long expedition")
			await get_tree().process_frame
			continue

		if int(manager.pending_perk_count) > 0:
			var perk_id := _first_offered_perk(manager)
			if perk_id.is_empty() or not bool(manager.choose_perk(perk_id)):
				_check(false, "every level-up has a valid offered perk to resolve")
				break
			await get_tree().process_frame
			continue

		if not manager.enemy.is_empty():
			var target: Dictionary = manager.enemy
			if bool(target.get("is_boss", false)) and not _boss_loops_seen.has(int(manager.loop_count)):
				_boss_loops_seen.append(int(manager.loop_count))
			_prepare_short_deterministic_combat(manager)
			manager.combat_timers["hero"] = 1000.0
			manager._tick_combat(0.01)
			await get_tree().process_frame
			continue

		var previous_steps: int = int(manager.processed_steps)
		# Drive one real route-cell visit at a time. Pausing prevents the normal
		# frame loop from racing the test harness; _tick_route still uses the
		# production route, visit, checkpoint, encounter, and reward logic.
		manager.distance = float(previous_steps + 1)
		manager._tick_route(0.0)
		if bool(manager.active) and int(manager.processed_steps) == previous_steps and manager.enemy.is_empty() and manager.pending_event.is_empty() and int(manager.pending_perk_count) == 0:
			_check(false, "the route advances whenever no combat, event, or perk is pending")
			break
		await get_tree().process_frame

	if bool(manager.active):
		_check(false, "the 12-loop expedition reaches a durable result before the bounded interaction limit")
		manager.active = false

	var final_summary: Dictionary = GameState.last_summary.duplicate(true)
	var boss_interval := maxi(1, int(ContentRegistry.BALANCE.get("boss_loop_interval", 3)))
	var expected_boss_loops: Array[int] = [boss_interval, boss_interval * 2, boss_interval * 3, boss_interval * 4]
	_check(boss_interval == 3, "the configured campaign cadence schedules a boss every three loops")
	_check(int(manager.loop_count) == 12, "the completed long run reached exactly 12 loops")
	_check(_boss_loops_seen == expected_boss_loops and _boss_loops_seen == [3, 6, 9, 12], "real boss encounters appeared on loops 3, 6, 9, and 12")
	_check(int(manager.run_ledger.get("bosses_defeated", 0)) == 4, "four generated bosses were defeated and rewarded through the real victory path")
	_check(bool(manager.run_ledger.get("endgame_completed", false)), "the long-expedition endgame flag is committed only after the final boss")
	_check(str(final_summary.get("outcome", "")) == "return" and int(final_summary.get("loops", 0)) == 12, "the run settles once as a return at loop 12")
	_check(str(final_summary.get("expedition_mode_id", "")) == "long_expedition" and bool(final_summary.get("endgame_completed", false)), "the durable result identifies the long mode and successful endgame")
	_check(int(final_summary.get("bosses_defeated", 0)) == 4, "the durable campaign summary records all four boss victories")
	_check(int(GameState.runs_completed) == 1, "one completed long run creates exactly one campaign settlement")
	_check(not GameState.has_saved_expedition(), "successful endgame settlement removes the saved expedition checkpoint")

	var checkpoint_value: Variant = manager.run_ledger.get("long_run_checkpoints", [])
	var checkpoints: Array = checkpoint_value if typeof(checkpoint_value) == TYPE_ARRAY else []
	var checkpoint_loops: Array[int] = []
	for checkpoint_value_item in checkpoints:
		if typeof(checkpoint_value_item) == TYPE_DICTIONARY:
			checkpoint_loops.append(int(checkpoint_value_item.get("loop", -1)))
	_check(checkpoint_loops == [3, 6, 9, 12], "four idempotent long-run checkpoints are recorded at loops 3, 6, 9, and 12")

	var summary_checkpoint_value: Variant = final_summary.get("endgame_checkpoints", [])
	var summary_checkpoints: Array = summary_checkpoint_value if typeof(summary_checkpoint_value) == TYPE_ARRAY else []
	var summary_checkpoint_loops: Array[int] = []
	for checkpoint_summary_value in summary_checkpoints:
		if typeof(checkpoint_summary_value) == TYPE_DICTIONARY:
			summary_checkpoint_loops.append(int(checkpoint_summary_value.get("loop", -1)))
	_check(summary_checkpoint_loops == [3, 6, 9, 12], "the final durable summary preserves all four long-run checkpoints")

	manager.queue_free()
	await get_tree().process_frame
	GameState.reset_progress()
	await get_tree().process_frame
	_finish()

func _keep_test_hero_alive(manager: Variant) -> void:
	manager.hero["max_hp"] = TEST_HERO_HP
	manager.hero["hp"] = TEST_HERO_HP
	manager.hero["attack"] = 1000000
	manager.hero["base_attack"] = 1000000
	manager.hero["defense"] = 1000000
	manager.hero["base_defense"] = 1000000

func _prepare_short_deterministic_combat(manager: Variant) -> void:
	# Encounters are still generated by the real enemy/route systems, and every
	# focused victory goes through _tick_combat() and _on_victory(). Only the
	# combat length is shortened here so CI can reliably exercise all 12 loops.
	var encounter_value: Variant = manager.encounter_enemies
	var encounter: Array = encounter_value.duplicate(true) if typeof(encounter_value) == TYPE_ARRAY else []
	for index in range(encounter.size()):
		var fighter_value: Variant = encounter[index]
		if typeof(fighter_value) != TYPE_DICTIONARY:
			continue
		var fighter: Dictionary = fighter_value
		fighter["hp"] = 1
		fighter["max_hp"] = 1
		fighter["defense"] = 0
		fighter["barrier"] = 0
		fighter["status_effects"] = []
		encounter[index] = fighter
	manager.encounter_enemies = encounter
	manager.enemy = encounter[0] if not encounter.is_empty() else {}
	_keep_test_hero_alive(manager)

func _first_available_event_choice(manager: Variant) -> String:
	var choices_value: Variant = manager.pending_event.get("choices", [])
	if typeof(choices_value) != TYPE_ARRAY:
		return ""
	for choice_value in choices_value:
		if typeof(choice_value) != TYPE_DICTIONARY:
			continue
		var choice: Dictionary = choice_value
		var choice_id := str(choice.get("id", ""))
		if not choice_id.is_empty() and bool(manager.event_choice_is_available(choice_id)):
			return choice_id
	return ""

func _first_offered_perk(manager: Variant) -> String:
	if manager.pending_perk_choices.is_empty():
		return ""
	var perk_value: Variant = manager.pending_perk_choices[0]
	return str(perk_value.get("id", "")) if typeof(perk_value) == TYPE_DICTIONARY else str(perk_value)

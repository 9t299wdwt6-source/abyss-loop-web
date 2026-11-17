extends Node

const ExpeditionManagerScript = preload("res://scripts/systems/expedition_manager.gd")
const FLOOR_IDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
const FIXED_SEEDS: Array[int] = [91001, 91003, 91007]
const MAX_SIMULATION_STEPS: int = 60000
const ROUTE_DELTA: float = 1.24
const COMBAT_DELTA: float = 0.05
const CARD_SAMPLE_COUNT: int = 96
const OUTPUT_PATH: String = "user://STAGE92_FLOOR_PROGRESSION.json"

var _runs: Array[Dictionary] = []
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run_capture")

func _run_capture() -> void:
	Engine.max_fps = 60
	print("Stage92 eight-floor engine matrix: eight floors x three deterministic seeds")
	print("Scripted production-engine QA only; not human-playtest evidence or a balance verdict.")
	for floor_id in FLOOR_IDS:
		for seed_value in FIXED_SEEDS:
			var row: Dictionary = await _capture_case(floor_id, seed_value)
			if row.is_empty():
				_failures.append("No durable summary for floor %d seed %d." % [floor_id, seed_value])
			else:
				_runs.append(row)
				print("CAPTURED floor=%d seed=%d outcome=%s loops=%d floor-card-hits=%d" % [
					floor_id, seed_value, str(row.get("outcome", "unknown")),
					int(row.get("loops", 0)), int(row.get("floor_card_pool_hits", 0))
				])
	var report := {
		"metadata": {
			"project": "Abyss Loop",
			"game_version": str(ProjectSettings.get_setting("application/config/version", "unknown")),
			"godot_version": str(Engine.get_version_info().get("string", "")),
			"capture_kind": "automated_engine_run",
			"not_human_playtest": true,
			"not_a_balance_verdict": true,
			"floors": FLOOR_IDS,
			"fixed_seeds": FIXED_SEEDS,
			"expected_runs": FLOOR_IDS.size() * FIXED_SEEDS.size(),
			"completed_runs": _runs.size(),
			"policy": "Each case resets a clean profile, unlocks the chosen floor through GameState, and drives production ExpeditionManager route/combat/event/perk/settlement methods. A separate deterministic sample invokes the production TileSystem draw function for that floor. Hero/enemy stats and gameplay reward formulas are never forced."
		},
		"runs": _runs,
		"failures": _failures
	}
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		printerr("Could not write floor capture: ", OUTPUT_PATH)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	if _runs.size() != FLOOR_IDS.size() * FIXED_SEEDS.size() or not _failures.is_empty():
		printerr("STAGE92 FLOOR CAPTURE FAILED: %d/%d; %s" % [_runs.size(), FLOOR_IDS.size() * FIXED_SEEDS.size(), str(_failures)])
		get_tree().quit(1)
		return
	print("STAGE92 FLOOR CAPTURE PASSED: %d runs across all eight floors." % _runs.size())
	get_tree().quit(0)

func _capture_case(floor_id: int, seed_value: int) -> Dictionary:
	GameState.reset_progress()
	await get_tree().process_frame
	for unlock_id in range(2, floor_id + 1):
		if not GameState.unlock_abyss_floor(unlock_id):
			_failures.append("Could not persist floor %d unlock." % unlock_id)
			return {}
	await get_tree().process_frame
	var manager = ExpeditionManagerScript.new()
	manager.name = "Stage92Floor%dSeed%d" % [floor_id, seed_value]
	get_tree().root.add_child(manager)
	await get_tree().process_frame
	if not bool(manager.start_run("standard", seed_value, "standard", "none", "standard", floor_id)):
		_failures.append("start_run rejected floor %d seed %d." % [floor_id, seed_value])
		manager.queue_free()
		await get_tree().process_frame
		return {}
	manager.set_pause(true)
	manager.set_speed(3.0)
	var floor_definition: Dictionary = manager.get_floor_config()
	var pool_value: Variant = floor_definition.get("tile_pool", [])
	var floor_pool: Array = pool_value if typeof(pool_value) == TYPE_ARRAY else []
	var initial_hand_ids: Array[String] = []
	for card_value in manager.tile_hand:
		if typeof(card_value) == TYPE_DICTIONARY:
			initial_hand_ids.append(str(card_value.get("id", "")))
	var sample_rng := RandomNumberGenerator.new()
	sample_rng.seed = seed_value + 2000000
	var floor_card_pool_hits := 0
	var sampled_floor_card_ids: Array[String] = []
	for _index in range(CARD_SAMPLE_COUNT):
		var card: Dictionary = manager.tile_system.draw_tile(sample_rng, false, [], floor_id)
		var card_id := str(card.get("id", ""))
		if floor_pool.has(card_id):
			floor_card_pool_hits += 1
			if not sampled_floor_card_ids.has(card_id):
				sampled_floor_card_ids.append(card_id)
	if floor_card_pool_hits == 0:
		_failures.append("TileSystem never drew a card from floor %d's configured pool." % floor_id)
		manager.active = false
		manager.queue_free()
		await get_tree().process_frame
		return {}

	var steps := 0
	var case_failed := false
	while bool(manager.active) and steps < MAX_SIMULATION_STEPS:
		steps += 1
		if not str(manager.pending_end_outcome).is_empty():
			_failures.append("Floor %d seed %d hit a failed settlement transaction." % [floor_id, seed_value])
			case_failed = true
			break
		if not manager.pending_event.is_empty():
			var choice_id := _best_available_event_choice(manager)
			if choice_id.is_empty():
				_failures.append("Floor %d seed %d had no available event choice." % [floor_id, seed_value])
				case_failed = true
				break
			var result: Dictionary = manager.resolve_event_choice(choice_id)
			if not bool(result.get("ok", false)):
				_failures.append("Floor %d event choice failed: %s" % [floor_id, str(result.get("reason", ""))])
				case_failed = true
				break
			manager._update_objective_progress()
			continue
		if int(manager.pending_perk_count) > 0:
			var perk_id := _first_offered_perk(manager)
			if perk_id.is_empty() or not bool(manager.choose_perk(perk_id)):
				_failures.append("Floor %d seed %d had no valid perk." % [floor_id, seed_value])
				case_failed = true
				break
			manager._update_objective_progress()
			continue
		if bool(manager.pending_floor_choice):
			var floor_result: Dictionary = manager.resolve_floor_choice("continue")
			if not bool(floor_result.get("ok", false)):
				_failures.append("Floor %d boss decision failed: %s" % [floor_id, str(floor_result.get("reason", ""))])
				case_failed = true
				break
			continue
		if not manager.enemy.is_empty():
			manager._tick_combat(COMBAT_DELTA)
			manager.run_elapsed_seconds += COMBAT_DELTA / maxf(1.0, float(manager.speed))
			continue
		if int(manager.loop_count) >= 1:
			manager.end_run("return")
			break
		var previous_steps := int(manager.processed_steps)
		manager.distance = float(manager.processed_steps)
		manager._tick_route(ROUTE_DELTA)
		manager.run_elapsed_seconds += ROUTE_DELTA / maxf(1.0, float(manager.speed))
		if manager.active:
			manager._update_objective_progress()
		if manager.active and int(manager.processed_steps) == previous_steps and manager.enemy.is_empty() and manager.pending_event.is_empty() and int(manager.pending_perk_count) == 0:
			_failures.append("Floor %d seed %d route stopped advancing." % [floor_id, seed_value])
			case_failed = true
			break
	if manager.active:
		_failures.append("Floor %d seed %d exceeded the simulation step limit." % [floor_id, seed_value])
		case_failed = true
		manager.active = false
	var summary: Dictionary = GameState.last_summary.duplicate(true)
	manager.queue_free()
	await get_tree().process_frame
	if case_failed or summary.is_empty():
		return {}
	if str(summary.get("outcome", "")) not in ["return", "defeat"] or int(summary.get("floor_id", 0)) != floor_id:
		_failures.append("Floor %d seed %d returned an invalid result or floor ID." % [floor_id, seed_value])
		return {}
	if int(summary.get("telemetry_schema", 0)) != 1 or str(summary.get("run_id", "")).is_empty():
		_failures.append("Floor %d seed %d summary is missing run ID or telemetry." % [floor_id, seed_value])
		return {}
	summary["run_id"] = "stage92-floor-%02d-seed-%d" % [floor_id, seed_value]
	summary["floor_id"] = floor_id
	summary["floor_name"] = str(floor_definition.get("name", "Этаж %d" % floor_id))
	summary["difficulty_id"] = "floor_%02d" % floor_id
	summary["expedition_mode_id"] = "standard"
	summary["modifier_id"] = "standard"
	summary["contract_id"] = "none"
	summary["capture_kind"] = "automated_engine_run"
	summary["capture_seed"] = seed_value
	summary["capture_initial_hand_tile_ids"] = initial_hand_ids
	summary["floor_card_pool_hits"] = floor_card_pool_hits
	summary["sampled_floor_card_ids"] = sampled_floor_card_ids
	summary["capture_simulation_steps"] = steps
	return summary

func _best_available_event_choice(manager: Variant) -> String:
	var values: Variant = manager.pending_event.get("choices", [])
	if typeof(values) != TYPE_ARRAY:
		return ""
	var best_id := ""
	var best_score := -INF
	for value in values:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var choice: Dictionary = value
		var choice_id := str(choice.get("id", ""))
		if choice_id.is_empty() or not bool(manager.event_choice_is_available(choice_id)):
			continue
		var effects_value: Variant = choice.get("effects", {})
		var effects: Dictionary = effects_value if typeof(effects_value) == TYPE_DICTIONARY else {}
		var score := float(effects.get("heal", 0)) * 2.0
		score += float(effects.get("crystals", 0)) * 1.5
		score += float(effects.get("scrap", 0)) * 0.3
		score -= float(effects.get("damage", 0)) * 3.0
		score -= float(effects.get("cost_scrap", 0)) * 0.25
		if score > best_score:
			best_score = score
			best_id = choice_id
	return best_id

func _first_offered_perk(manager: Variant) -> String:
	var values: Variant = manager.pending_perk_choices
	if typeof(values) != TYPE_ARRAY or values.is_empty():
		return ""
	var first_value: Variant = values[0]
	if typeof(first_value) == TYPE_DICTIONARY:
		return str(first_value.get("id", ""))
	return str(first_value)

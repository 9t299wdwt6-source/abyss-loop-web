extends Node

const ExpeditionManagerScript = preload("res://scripts/systems/expedition_manager.gd")
const OUTPUT_PATH: String = "user://STAGE71_BALANCE_MATRIX.json"
const MAX_PROCESS_FRAMES_PER_RUN: int = 6000
const DIFFICULTY_IDS: Array[String] = ["standard", "volatile", "attrition", "abyssal"]
const BASE_SEEDS: Array[int] = [8675309, 8675311, 8675313]
const LONG_MODE_SEEDS: Array[int] = [8675401, 8675407, 8675413]
const RESONANCE_SEEDS: Array[int] = [8675501, 8675507, 8675513]
const SCARCE_SEEDS: Array[int] = [8675521, 8675527, 8675531]
const UNSTABLE_SEEDS: Array[int] = [8675541, 8675547, 8675551]
const BOUNTY_SEEDS: Array[int] = [8675601, 8675607, 8675613]
const EVENT_SEEDS: Array[int] = [8675621, 8675627, 8675633]
const LANDSCAPE_SEEDS: Array[int] = [8675641, 8675647, 8675651]

var _runs: Array[Dictionary] = []
var _failures: Array[String] = []
var _case_count: int = 0

func _ready() -> void:
	call_deferred("_run_capture")

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
		printerr("FAIL: ", description)

func _run_capture() -> void:
	Engine.max_fps = 60
	var cases := _build_case_matrix()
	print("Stage71 real-engine balance matrix: %d reproducible cases" % cases.size())
	print("Four difficulties, standard/long modes, three modifiers and three contracts.")
	print("All outcomes are labelled automated_engine_run; no hero/enemy stats or loot formulas are forced.")

	for case_value in cases:
		var case_data: Dictionary = case_value
		_case_count += 1
		var row: Dictionary = await _capture_case(case_data)
		if row.is_empty():
			_failures.append("Case %s / seed %d did not produce a valid completed run." % [str(case_data.get("capture_group", "unknown")), int(case_data.get("seed", 0))])
			printerr("FAIL: %s seed=%d did not produce a valid summary." % [str(case_data.get("capture_group", "unknown")), int(case_data.get("seed", 0))])
			break
		_runs.append(row)
		print("CAPTURED: group=%s diff=%s mode=%s modifier=%s contract=%s seed=%d outcome=%s loops=%d bosses=%d victories=%d events=%d contract_status=%s seconds=%d" % [
			str(row.get("capture_group", "unknown")),
			str(row.get("difficulty_id", "unknown")),
			str(row.get("expedition_mode_id", "unknown")),
			str(row.get("modifier_id", "unknown")),
			str(row.get("capture_contract_id", "unknown")),
			int(row.get("seed", 0)),
			str(row.get("outcome", "unknown")),
			int(row.get("loops", 0)),
			int(row.get("bosses_defeated", 0)),
			int(row.get("victories", 0)),
			int(row.get("events_resolved", 0)),
			str(row.get("contract_status", "unknown")),
			int(row.get("run_elapsed_seconds", 0))
		])

	var report := {
		"metadata": {
			"project": "Abyss Loop",
			"game_version": str(ProjectSettings.get_setting("application/config/version", "unknown")),
			"godot_version": str(Engine.get_version_info().get("string", "")),
			"capture_kind": "automated_engine_run",
			"not_human_playtest": true,
			"not_a_balance_verdict": true,
			"runs_expected": cases.size(),
			"runs_completed": _runs.size(),
			"run_groups": [
				"difficulty_standard_one_loop",
				"difficulty_long_mode_three_loops",
				"modifier_resonance",
				"modifier_scarce",
				"modifier_unstable",
				"contract_bounty_hunter",
				"contract_event_archive",
				"contract_landscape_survey"
			],
			"seeds": {
				"difficulty_standard": BASE_SEEDS,
				"long_mode": LONG_MODE_SEEDS,
				"resonance": RESONANCE_SEEDS,
				"scarce": SCARCE_SEEDS,
				"unstable": UNSTABLE_SEEDS,
				"bounty_hunter": BOUNTY_SEEDS,
				"event_archive": EVENT_SEEDS,
				"landscape_survey": LANDSCAPE_SEEDS
			},
			"policy": "The real ExpeditionManager and production route, event, combat, loot, contract, challenge, and settlement methods run at 3x game speed. Each scenario uses an isolated fresh profile and deterministic seed. The harness selects an affordable event option, accepts the first offered perk, and returns at its declared target loop unless a natural defeat occurs. It places legal tiles to exercise road/landscape contracts. Hero/enemy HP, attack, defense, loot, rewards, encounter rates, and gameplay formulas are never forced or edited."
		},
		"runs": _runs,
		"failures": _failures
	}
	var absolute_report_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_report_path.get_base_dir())
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		printerr("Could not write Stage71 balance matrix: ", OUTPUT_PATH)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()

	if _runs.size() != cases.size() or not _failures.is_empty():
		printerr("STAGE71 BALANCE MATRIX FAILED: %d/%d cases; %s" % [_runs.size(), cases.size(), str(_failures)])
		get_tree().quit(1)
		return
	print("STAGE71 BALANCE MATRIX CAPTURE PASSED: %d cases across %d repeatable seed sets." % [_runs.size(), _case_count])
	print("IMPORTANT: these are scripted engine QA samples, not human playtesting or an automatic balance verdict.")
	get_tree().quit(0)

func _build_case_matrix() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	for difficulty_id in DIFFICULTY_IDS:
		_append_cases(cases, "difficulty_standard_one_loop", difficulty_id, "standard", "none", "standard", 1, 1, BASE_SEEDS)
	for difficulty_id in DIFFICULTY_IDS:
		_append_cases(cases, "difficulty_long_mode_three_loops", difficulty_id, "standard", "none", "long_expedition", 3, 1, LONG_MODE_SEEDS)
	_append_cases(cases, "modifier_resonance", "standard", "resonance", "none", "standard", 1, 1, RESONANCE_SEEDS)
	_append_cases(cases, "modifier_scarce", "standard", "scarce", "none", "standard", 1, 1, SCARCE_SEEDS)
	_append_cases(cases, "modifier_unstable", "standard", "unstable", "none", "standard", 1, 1, UNSTABLE_SEEDS)
	_append_cases(cases, "contract_bounty_hunter", "standard", "standard", "bounty_hunter", "standard", 2, 1, BOUNTY_SEEDS)
	_append_cases(cases, "contract_event_archive", "standard", "standard", "event_archive", "standard", 3, 1, EVENT_SEEDS)
	_append_cases(cases, "contract_landscape_survey", "standard", "standard", "landscape_survey", "standard", 3, 3, LANDSCAPE_SEEDS)
	return cases

func _append_cases(cases: Array[Dictionary], group_id: String, difficulty_id: String, modifier_id: String, contract_id: String, mode_id: String, target_loops: int, landscape_tiles: int, seeds: Array[int]) -> void:
	for seed_value in seeds:
		cases.append({
			"capture_group": group_id,
			"difficulty_id": difficulty_id,
			"modifier_id": modifier_id,
			"contract_id": contract_id,
			"expedition_mode_id": mode_id,
			"target_loops": target_loops,
			"landscape_tiles": landscape_tiles,
			"seed": seed_value
		})

func _capture_case(case_data: Dictionary) -> Dictionary:
	GameState.reset_progress()
	await get_tree().process_frame

	var difficulty_id := str(case_data.get("difficulty_id", "standard"))
	var modifier_id := str(case_data.get("modifier_id", "standard"))
	var contract_id := str(case_data.get("contract_id", "none"))
	var mode_id := str(case_data.get("expedition_mode_id", "standard"))
	var seed_value := int(case_data.get("seed", 0))
	var target_loops := maxi(1, int(case_data.get("target_loops", 1)))
	var target_landscape_tiles := maxi(1, int(case_data.get("landscape_tiles", 1)))

	var manager = ExpeditionManagerScript.new()
	manager.name = "Stage71_%s_%d" % [str(case_data.get("capture_group", "case")), seed_value]
	get_tree().root.add_child(manager)
	await get_tree().process_frame
	if not bool(manager.start_run(difficulty_id, seed_value, modifier_id, contract_id, mode_id)):
		printerr("FAIL: start_run rejected %s / seed %d." % [str(case_data.get("capture_group", "unknown")), seed_value])
		manager.queue_free()
		await get_tree().process_frame
		return {}

	manager.set_pause(true)
	manager.set_speed(3.0)
	if not _place_one_legal_road_tile(manager):
		printerr("FAIL: road placement could not be exercised for seed %d." % seed_value)
		manager.queue_free()
		await get_tree().process_frame
		return {}
	var world_tiles_placed := _place_landscape_tiles(manager, target_landscape_tiles)
	if world_tiles_placed < target_landscape_tiles:
		printerr("FAIL: expected %d legal landscape tiles but placed %d for seed %d." % [target_landscape_tiles, world_tiles_placed, seed_value])
		manager.queue_free()
		await get_tree().process_frame
		return {}
	manager.set_pause(false)

	var process_frames := 0
	while bool(manager.active) and process_frames < MAX_PROCESS_FRAMES_PER_RUN:
		process_frames += 1
		if not str(manager.pending_end_outcome).is_empty():
			printerr("FAIL: settlement is pending after a persistence failure for seed %d." % seed_value)
			break
		if not manager.pending_event.is_empty():
			var choice_id := _best_available_event_choice(manager)
			if choice_id.is_empty():
				printerr("FAIL: no affordable event choice for seed %d." % seed_value)
				manager.active = false
				break
			var event_result: Dictionary = manager.resolve_event_choice(choice_id)
			if not bool(event_result.get("ok", false)):
				printerr("FAIL: event choice rejected for seed %d: %s" % [seed_value, str(event_result.get("reason", ""))])
				manager.active = false
				break
			continue
		if int(manager.pending_perk_count) > 0:
			var perk_id := _first_offered_perk(manager)
			if perk_id.is_empty() or not bool(manager.choose_perk(perk_id)):
				printerr("FAIL: no valid offered perk for seed %d." % seed_value)
				manager.active = false
				break
			continue
		if int(manager.loop_count) >= target_loops and manager.enemy.is_empty():
			manager.end_run("return")
			break
		await get_tree().process_frame

	var still_active := bool(manager.active)
	var completed_summary: Dictionary = GameState.last_summary.duplicate(true)
	if still_active:
		printerr("FAIL: seed %d exceeded %d frames without a durable result." % [seed_value, MAX_PROCESS_FRAMES_PER_RUN])
		manager.active = false
	manager.queue_free()
	await get_tree().process_frame

	if still_active or completed_summary.is_empty():
		return {}
	if str(completed_summary.get("outcome", "")) not in ["return", "defeat"]:
		printerr("FAIL: unsupported outcome for seed %d: %s." % [seed_value, str(completed_summary.get("outcome", ""))])
		return {}
	if str(completed_summary.get("run_id", "")).is_empty():
		printerr("FAIL: durable summary has no run_id for seed %d." % seed_value)
		return {}
	if int(completed_summary.get("telemetry_schema", 0)) != 1:
		printerr("FAIL: missing Stage68B telemetry for seed %d." % seed_value)
		return {}
	if int(completed_summary.get("road_placements", 0)) < 1 or int(completed_summary.get("world_placements", 0)) < target_landscape_tiles:
		printerr("FAIL: durable summary lost tile placement metrics for seed %d." % seed_value)
		return {}

	var modifier_definition: Dictionary = ContentRegistry.RUN_MODIFIERS.get(modifier_id, ContentRegistry.RUN_MODIFIERS["standard"])
	var challenge_value: Variant = modifier_definition.get("challenge", {})
	var challenge_id := str(challenge_value.get("id", "none")) if typeof(challenge_value) == TYPE_DICTIONARY else "none"
	completed_summary["capture_kind"] = "automated_engine_run"
	completed_summary["capture_group"] = str(case_data.get("capture_group", "unknown"))
	completed_summary["capture_contract_id"] = contract_id
	completed_summary["capture_challenge_id"] = challenge_id
	completed_summary["capture_seed"] = seed_value
	completed_summary["capture_target_loops"] = target_loops
	return completed_summary

func _place_one_legal_road_tile(manager: Variant) -> bool:
	if manager.tile_hand.is_empty():
		return false
	for route_index in range(1, manager.route.size()):
		var preview: Dictionary = manager.tile_system.can_place(manager.route, manager.placed_tiles, route_index)
		if not bool(preview.get("ok", false)):
			continue
		var result: Dictionary = manager.place_tile(0, route_index)
		if bool(result.get("ok", false)):
			return true
	return false

func _place_landscape_tiles(manager: Variant, target_count: int) -> int:
	var placed := 0
	for y in range(8):
		for x in range(10):
			if placed >= target_count or manager.tile_hand.is_empty():
				break
			var cell_id := "%d:%d" % [x, y]
			var preview: Dictionary = manager.tile_system.can_place_world(manager.route, manager.world_tiles, cell_id)
			if not bool(preview.get("ok", false)):
				continue
			var result: Dictionary = manager.place_world_tile(0, cell_id)
			if bool(result.get("ok", false)):
				placed += 1
		if placed >= target_count or manager.tile_hand.is_empty():
			break
	return placed

func _best_available_event_choice(manager: Variant) -> String:
	var choices_value: Variant = manager.pending_event.get("choices", [])
	if typeof(choices_value) != TYPE_ARRAY:
		return ""
	var best_id := ""
	var best_score: float = -INF
	for choice_value in choices_value:
		if typeof(choice_value) != TYPE_DICTIONARY:
			continue
		var choice: Dictionary = choice_value
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
	var choices_value: Variant = manager.pending_perk_choices
	if typeof(choices_value) != TYPE_ARRAY or choices_value.is_empty():
		return ""
	var first_value: Variant = choices_value[0]
	if typeof(first_value) == TYPE_DICTIONARY:
		return str(first_value.get("id", ""))
	return str(first_value)

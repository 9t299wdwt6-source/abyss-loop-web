extends Node

const ExpeditionManagerScript = preload("res://scripts/systems/expedition_manager.gd")
const RUN_SEEDS: Array[int] = [8675309, 8675311, 8675313, 8675317, 8675323]
const DIFFICULTY_IDS: Array[String] = ["standard", "volatile", "attrition", "abyssal"]
const MODE_IDS: Array[String] = ["standard", "long_expedition"]
const STANDARD_TARGET_LOOPS: int = 1
const LONG_TARGET_LOOPS: int = 12
const MAX_SIMULATION_STEPS_PER_RUN: int = 100000
# At 3x speed, a 1.24 scaled-delta route update advances one 0.82-speed cell.
const ROUTE_SCALED_DELTA: float = 1.24
# 0.05 scaled seconds equals one 60 FPS frame at the game's 3x speed.
const COMBAT_SCALED_DELTA: float = 0.05
const OUTPUT_PATH: String = "user://STAGE64B_AUTOMATED_ENGINE_RUNS.json"

# Small, explicitly labelled integration samples exercise modifiers and contracts.
# These are not large enough to support balance claims; the analyzer flags them as small groups.
const COVERAGE_CASES: Array[Dictionary] = [
	{"difficulty_id": "standard", "seed": 8680001, "modifier_id": "resonance", "contract_id": "boss_bounty", "mode_id": "standard", "target_loops": 4, "starting_landscape_placements": 0, "coverage_only": true},
	{"difficulty_id": "standard", "seed": 8680002, "modifier_id": "standard", "contract_id": "landscape_survey", "mode_id": "standard", "target_loops": 3, "starting_landscape_placements": 3, "coverage_only": true},
	{"difficulty_id": "volatile", "seed": 8680003, "modifier_id": "unstable", "contract_id": "event_archive", "mode_id": "standard", "target_loops": 3, "starting_landscape_placements": 0, "coverage_only": true},
	{"difficulty_id": "attrition", "seed": 8680004, "modifier_id": "standard", "contract_id": "bounty_hunter", "mode_id": "standard", "target_loops": 2, "starting_landscape_placements": 0, "coverage_only": true},
	{"difficulty_id": "abyssal", "seed": 8680005, "modifier_id": "scarce", "contract_id": "none", "mode_id": "standard", "target_loops": 1, "starting_landscape_placements": 0, "coverage_only": true}
]

var _runs: Array[Dictionary] = []
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run_capture")

func _build_case_matrix() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	for difficulty_id in DIFFICULTY_IDS:
		for mode_id in MODE_IDS:
			for seed_value in RUN_SEEDS:
				cases.append({
					"difficulty_id": difficulty_id,
					"seed": seed_value,
					"modifier_id": "standard",
					"contract_id": "none",
					"mode_id": mode_id,
					"target_loops": STANDARD_TARGET_LOOPS if mode_id == "standard" else LONG_TARGET_LOOPS,
					"starting_landscape_placements": 0,
					"coverage_only": false
				})
	cases.append_array(COVERAGE_CASES)
	return cases

func _run_capture() -> void:
	print("Stage71 automated engine balance matrix (scripted QA, not human-playtest data)")
	print("Core matrix: four difficulties x two expedition modes x five fixed seeds; plus five labelled modifier/contract coverage samples.")
	var cases := _build_case_matrix()
	for case_data in cases:
		var row: Dictionary = await _capture_case(case_data)
		if row.is_empty():
			_failures.append("No durable result for case %s." % _case_label(case_data))
		else:
			_runs.append(row)
			print("CAPTURED: difficulty=%s mode=%s modifier=%s contract=%s seed=%d outcome=%s loops=%d bosses=%d events=%d seconds=%d coverage_only=%s" % [
				str(row.get("difficulty_id", "standard")),
				str(row.get("expedition_mode_id", "standard")),
				str(row.get("modifier_id", "standard")),
				str(row.get("contract_id", "none")),
				int(row.get("seed", 0)),
				str(row.get("outcome", "unknown")),
				int(row.get("loops", 0)),
				int(row.get("bosses_defeated", 0)),
				int(row.get("events_resolved", 0)),
				int(row.get("run_elapsed_seconds", 0)),
				bool(row.get("capture_coverage_only", false))
			])

	var report := {
		"metadata": {
			"project": "Abyss Loop",
			"game_version": str(ProjectSettings.get_setting("application/config/version", "unknown")),
			"godot_version": str(Engine.get_version_info().get("string", "")),
			"capture_kind": "automated_engine_run",
			"not_human_playtest": true,
			"not_a_balance_verdict": true,
			"difficulty_ids": DIFFICULTY_IDS,
			"expedition_mode_ids": MODE_IDS,
			"fixed_seeds": RUN_SEEDS,
			"core_matrix_runs_expected": DIFFICULTY_IDS.size() * MODE_IDS.size() * RUN_SEEDS.size(),
			"coverage_runs_expected": COVERAGE_CASES.size(),
			"runs_expected": cases.size(),
			"route_scaled_delta": ROUTE_SCALED_DELTA,
			"combat_scaled_delta": COMBAT_SCALED_DELTA,
			"simulation_speed": "3x-equivalent scaled-time steps",
			"policy": "The production ExpeditionManager route, encounter, combat, loot, event, objective, contract, and settlement methods are used. The harness advances route by one production cell at a time and combat in 0.05 scaled-second steps (equivalent to one 60 FPS frame at 3x). It never overwrites hero/enemy stats, loot, damage, or reward formulas. Core matrix compares four difficulties across standard and 12-loop modes on five fixed seeds with standard modifier/no contract. Five extra coverage-only cases probe contracts/modifiers and must not be treated as balanced samples."
		},
		"runs": _runs,
		"failures": _failures
	}
	var absolute_report_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_report_path.get_base_dir())
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		printerr("Could not write automated engine capture output: ", OUTPUT_PATH)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()

	if _runs.size() != cases.size() or not _failures.is_empty():
		printerr("STAGE71 ENGINE BALANCE MATRIX FAILED: %d/%d runs; %s" % [_runs.size(), cases.size(), str(_failures)])
		get_tree().quit(1)
		return
	print("STAGE71 ENGINE BALANCE MATRIX PASSED: %d finished runs (%d core matrix + %d coverage-only)." % [_runs.size(), DIFFICULTY_IDS.size() * MODE_IDS.size() * RUN_SEEDS.size(), COVERAGE_CASES.size()])
	print("IMPORTANT: all samples are scripted engine QA, not human playtests; small contract/modifier coverage groups are not balance verdicts.")
	get_tree().quit(0)

func _capture_case(case_data: Dictionary) -> Dictionary:
	GameState.reset_progress()
	await get_tree().process_frame

	var difficulty_id := str(case_data.get("difficulty_id", "standard"))
	var seed_value := int(case_data.get("seed", 0))
	var modifier_id := str(case_data.get("modifier_id", "standard"))
	var contract_id := str(case_data.get("contract_id", "none"))
	var mode_id := str(case_data.get("mode_id", "standard"))
	var target_loops := maxi(1, int(case_data.get("target_loops", STANDARD_TARGET_LOOPS)))

	var manager = ExpeditionManagerScript.new()
	manager.name = "Stage71Run_%s_%s_%d" % [difficulty_id, mode_id, seed_value]
	get_tree().root.add_child(manager)
	await get_tree().process_frame

	if not bool(manager.start_run(difficulty_id, seed_value, modifier_id, contract_id, mode_id)):
		printerr("FAIL: start_run rejected case %s." % _case_label(case_data))
		manager.queue_free()
		await get_tree().process_frame
		return {}

	manager.set_pause(true)
	manager.set_speed(3.0)

	var starting_landscapes := maxi(0, int(case_data.get("starting_landscape_placements", 0)))
	for _placement in range(starting_landscapes):
		if not _place_one_legal_landscape_tile(manager):
			printerr("FAIL: requested initial landscape placement was not possible for case %s." % _case_label(case_data))
			manager.active = false
			manager.queue_free()
			await get_tree().process_frame
			return {}
	if not _place_one_legal_road_tile(manager):
		printerr("FAIL: no legal road placement for case %s." % _case_label(case_data))
		manager.active = false
		manager.queue_free()
		await get_tree().process_frame
		return {}
	if manager.world_tiles.is_empty() and not _place_one_legal_landscape_tile(manager):
		printerr("FAIL: no legal landscape placement for case %s." % _case_label(case_data))
		manager.active = false
		manager.queue_free()
		await get_tree().process_frame
		return {}
	if manager.placed_tiles.is_empty() or manager.world_tiles.is_empty():
		printerr("FAIL: both real road and landscape placement must be exercised for case %s." % _case_label(case_data))
		manager.active = false
		manager.queue_free()
		await get_tree().process_frame
		return {}
	manager._update_objective_progress()

	var simulation_steps := 0
	var case_failed := false
	while bool(manager.active) and simulation_steps < MAX_SIMULATION_STEPS_PER_RUN:
		simulation_steps += 1
		if not str(manager.pending_end_outcome).is_empty():
			_failures.append("Case %s stalled after a failed settlement transaction." % _case_label(case_data))
			case_failed = true
			manager.active = false
			break

		if not manager.pending_event.is_empty():
			var choice_id := _best_available_event_choice(manager)
			if choice_id.is_empty():
				_failures.append("Case %s has an event without an available choice." % _case_label(case_data))
				case_failed = true
				manager.active = false
				break
			var event_result: Dictionary = manager.resolve_event_choice(choice_id)
			if not bool(event_result.get("ok", false)):
				_failures.append("Case %s event choice was rejected: %s." % [_case_label(case_data), str(event_result.get("reason", ""))])
				case_failed = true
				manager.active = false
				break
			manager._update_objective_progress()
			continue

		if int(manager.pending_perk_count) > 0:
			var perk_id := _first_offered_perk(manager)
			if perk_id.is_empty() or not bool(manager.choose_perk(perk_id)):
				_failures.append("Case %s has no valid offered perk." % _case_label(case_data))
				case_failed = true
				manager.active = false
				break
			manager._update_objective_progress()
			continue

		if not manager.enemy.is_empty():
			manager._tick_combat(COMBAT_SCALED_DELTA)
			manager.run_elapsed_seconds += COMBAT_SCALED_DELTA / maxf(1.0, float(manager.speed))
			if manager.active:
				manager._update_objective_progress()
			continue

		if mode_id == "long_expedition" and int(manager.loop_count) >= target_loops:
			var boss_goal := int(manager.get_expedition_goal_progress().get("target_bosses", 4))
			var bosses_defeated := int(manager.run_ledger.get("bosses_defeated", 0))
			if bosses_defeated < boss_goal:
				_failures.append("Case %s reached its loop goal without the required final boss count (%d/%d)." % [_case_label(case_data), bosses_defeated, boss_goal])
				case_failed = true
				manager.active = false
				break
			_failures.append("Case %s met the long-expedition goal but did not settle automatically." % _case_label(case_data))
			case_failed = true
			manager.active = false
			break

		if mode_id != "long_expedition" and int(manager.loop_count) >= target_loops:
			manager.end_run("return")
			break

		var previous_steps := int(manager.processed_steps)
		manager.distance = float(manager.processed_steps)
		manager._tick_route(ROUTE_SCALED_DELTA)
		manager.run_elapsed_seconds += ROUTE_SCALED_DELTA / maxf(1.0, float(manager.speed))
		if manager.active:
			manager._update_objective_progress()
		if bool(manager.active) and int(manager.processed_steps) == previous_steps and manager.enemy.is_empty() and manager.pending_event.is_empty() and int(manager.pending_perk_count) == 0:
			_failures.append("Case %s route did not advance or raise an actionable state." % _case_label(case_data))
			case_failed = true
			manager.active = false
			break

	if bool(manager.active):
		_failures.append("Case %s exceeded %d simulation steps without a durable outcome." % [_case_label(case_data), MAX_SIMULATION_STEPS_PER_RUN])
		case_failed = true
		manager.active = false

	var completed_summary: Dictionary = GameState.last_summary.duplicate(true)
	manager.queue_free()
	await get_tree().process_frame
	if case_failed or completed_summary.is_empty():
		return {}
	if str(completed_summary.get("outcome", "")) not in ["return", "defeat"]:
		_failures.append("Case %s has unsupported outcome %s." % [_case_label(case_data), str(completed_summary.get("outcome", ""))])
		return {}
	if int(completed_summary.get("telemetry_schema", 0)) != 1 or int(completed_summary.get("seed", 0)) <= 0:
		_failures.append("Case %s summary lacks real-run baseline telemetry or seed." % _case_label(case_data))
		return {}
	if str(completed_summary.get("run_id", "")).is_empty():
		_failures.append("Case %s summary has no original run_id." % _case_label(case_data))
		return {}
	if int(completed_summary.get("road_placements", 0)) < 1 or int(completed_summary.get("world_placements", 0)) < 1:
		_failures.append("Case %s summary did not preserve both placement types." % _case_label(case_data))
		return {}

	var original_run_id := str(completed_summary.get("run_id", ""))
	completed_summary["source_run_id"] = original_run_id
	# The game creates run IDs within one clean profile. Include the full configuration
	# in each QA ID so the analyzer never de-duplicates runs with different settings.
	completed_summary["run_id"] = "qa-%s-%s-%s-%s-%d" % [difficulty_id, mode_id, modifier_id, contract_id, seed_value]
	completed_summary["capture_kind"] = "automated_engine_run"
	completed_summary["capture_seed"] = seed_value
	completed_summary["capture_difficulty_id"] = difficulty_id
	completed_summary["capture_mode_id"] = mode_id
	completed_summary["capture_modifier_id"] = modifier_id
	completed_summary["capture_contract_id"] = contract_id
	completed_summary["capture_challenge_id"] = str(manager.run_challenge.get("id", "none"))
	completed_summary["capture_coverage_only"] = bool(case_data.get("coverage_only", false))
	completed_summary["capture_target_loops"] = target_loops
	completed_summary["capture_policy_version"] = 2
	completed_summary["capture_simulation_steps"] = simulation_steps
	return completed_summary

func _case_label(case_data: Dictionary) -> String:
	return "%s/%s/%s/%s/seed-%d" % [
		str(case_data.get("difficulty_id", "standard")),
		str(case_data.get("mode_id", "standard")),
		str(case_data.get("modifier_id", "standard")),
		str(case_data.get("contract_id", "none")),
		int(case_data.get("seed", 0))
	]

func _place_one_legal_road_tile(manager) -> bool:
	if manager.tile_hand.is_empty():
		return false
	for route_index in range(1, manager.route.size()):
		var placement_preview: Dictionary = manager.tile_system.can_place(manager.route, manager.placed_tiles, route_index)
		if not bool(placement_preview.get("ok", false)):
			continue
		var placement_result: Dictionary = manager.place_tile(0, route_index)
		if bool(placement_result.get("ok", false)):
			manager._update_objective_progress()
			return true
	return false

func _place_one_legal_landscape_tile(manager) -> bool:
	if manager.tile_hand.is_empty():
		return false
	for y in range(8):
		for x in range(10):
			var cell_id := "%d:%d" % [x, y]
			var placement_preview: Dictionary = manager.tile_system.can_place_world(manager.route, manager.world_tiles, cell_id)
			if not bool(placement_preview.get("ok", false)):
				continue
			var placement_result: Dictionary = manager.place_world_tile(0, cell_id)
			if bool(placement_result.get("ok", false)):
				manager._update_objective_progress()
				return true
	return false

func _best_available_event_choice(manager) -> String:
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

func _first_offered_perk(manager) -> String:
	var choices_value: Variant = manager.pending_perk_choices
	if typeof(choices_value) != TYPE_ARRAY or choices_value.is_empty():
		return ""
	var first_value: Variant = choices_value[0]
	if typeof(first_value) == TYPE_DICTIONARY:
		return str(first_value.get("id", ""))
	return str(first_value)

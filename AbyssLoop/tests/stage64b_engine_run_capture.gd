extends Node

const ExpeditionManagerScript = preload("res://scripts/systems/expedition_manager.gd")
const RUN_SEEDS: Array[int] = [8675309, 8675311, 8675313, 8675317, 8675323]
const TARGET_LOOPS: int = 1
const MAX_PROCESS_FRAMES_PER_RUN: int = 3000
const OUTPUT_PATH: String = "user://STAGE64B_AUTOMATED_ENGINE_RUNS.json"

var _runs: Array[Dictionary] = []
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run_capture")

func _run_capture() -> void:
	# Bound frame rate so process-time/route ticks are consistent in headless CI.
	Engine.max_fps = 60
	print("Stage64B automated engine-run capture (not human playtest data)")
	print("Godot engine systems run unmodified at 3x speed; fresh isolated campaign per seed.")
	for seed_value in RUN_SEEDS:
		var row: Dictionary = await _capture_seed(seed_value)
		if row.is_empty():
			_failures.append("Seed %d did not produce a valid completed run." % seed_value)
		else:
			_runs.append(row)
			print("CAPTURED: seed=%d outcome=%s loops=%d victories=%d events=%d seconds=%d road=%d landscape=%d" % [
				seed_value,
				str(row.get("outcome", "unknown")),
				int(row.get("loops", 0)),
				int(row.get("victories", 0)),
				int(row.get("events_resolved", 0)),
				int(row.get("run_elapsed_seconds", 0)),
				int(row.get("road_placements", 0)),
				int(row.get("world_placements", 0))
			])

	var report := {
		"metadata": {
			"project": "Abyss Loop",
			"game_version": str(ProjectSettings.get_setting("application/config/version", "unknown")),
			"godot_version": str(Engine.get_version_info().get("string", "")),
			"capture_kind": "automated_engine_run",
			"not_human_playtest": true,
			"not_a_balance_verdict": true,
			"difficulty_id": "standard",
			"modifier_id": "standard",
			"expedition_mode_id": "standard",
			"target_loops": TARGET_LOOPS,
			"seeds": RUN_SEEDS,
			"runs_expected": RUN_SEEDS.size(),
			"policy": "Real ExpeditionManager and its normal route/combat process run at 3x speed. The deterministic policy places one legal road tile and one legal landscape tile, chooses an affordable event option with a conservative score, accepts the first offered perk, and returns after the target loop or a natural defeat. Enemy HP/attack/defense, hero HP, loot, and reward formulas are never forced or edited."
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

	if _runs.size() != RUN_SEEDS.size() or not _failures.is_empty():
		printerr("STAGE64B AUTOMATED ENGINE CAPTURE FAILED: %d/%d runs; %s" % [_runs.size(), RUN_SEEDS.size(), str(_failures)])
		get_tree().quit(1)
		return
	print("STAGE64B AUTOMATED ENGINE CAPTURE PASSED: %d finished runs across %d distinct seeds." % [_runs.size(), RUN_SEEDS.size()])
	print("IMPORTANT: these are scripted QA engine runs, not human playtesting and not an automatic balance verdict.")
	get_tree().quit(0)

func _capture_seed(seed_value: int) -> Dictionary:
	# This scene runs against a separate CI app identity; each sample starts from a
	# clean profile so prior rewards/upgrades cannot leak into another seed.
	GameState.reset_progress()
	await get_tree().process_frame

	var manager = ExpeditionManagerScript.new()
	manager.name = "Stage64BRun_%d" % seed_value
	get_tree().root.add_child(manager)
	await get_tree().process_frame

	if not bool(manager.start_run("standard", seed_value, "standard", "none", "standard")):
		printerr("FAIL: start_run rejected seed %d" % seed_value)
		manager.queue_free()
		await get_tree().process_frame
		return {}

	manager.set_pause(true)
	manager.set_speed(3.0)
	_place_one_legal_road_tile(manager)
	_place_one_legal_landscape_tile(manager)
	if manager.placed_tiles.is_empty() or manager.world_tiles.is_empty():
		printerr("FAIL: both legal road and landscape placement must be exercised for seed %d" % seed_value)
		manager.active = false
		manager.queue_free()
		await get_tree().process_frame
		return {}
	manager.set_pause(false)

	var process_frames := 0
	while bool(manager.active) and process_frames < MAX_PROCESS_FRAMES_PER_RUN:
		process_frames += 1

		if not manager.pending_event.is_empty():
			var choice_id := _best_available_event_choice(manager)
			if choice_id.is_empty():
				printerr("FAIL: no affordable event choice for seed %d" % seed_value)
				manager.active = false
				manager.queue_free()
				await get_tree().process_frame
				return {}
			var event_result: Dictionary = manager.resolve_event_choice(choice_id)
			if not bool(event_result.get("ok", false)):
				printerr("FAIL: event choice rejected for seed %d: %s" % [seed_value, str(event_result.get("reason", ""))])
				manager.active = false
				manager.queue_free()
				await get_tree().process_frame
				return {}
			continue

		if int(manager.pending_perk_count) > 0:
			var perk_id := _first_offered_perk(manager)
			if perk_id.is_empty() or not bool(manager.choose_perk(perk_id)):
				printerr("FAIL: no valid offered perk for seed %d" % seed_value)
				manager.active = false
				manager.queue_free()
				await get_tree().process_frame
				return {}
			continue

		if int(manager.loop_count) >= TARGET_LOOPS and manager.enemy.is_empty():
			manager.end_run("return")
			break

		await get_tree().process_frame

	var still_active := bool(manager.active)
	var completed_summary: Dictionary = GameState.last_summary.duplicate(true)
	if still_active:
		printerr("FAIL: seed %d exceeded %d process frames without a natural result." % [seed_value, MAX_PROCESS_FRAMES_PER_RUN])
		manager.active = false
		manager.queue_free()
		await get_tree().process_frame
		return {}
	manager.queue_free()
	await get_tree().process_frame

	if completed_summary.is_empty():
		printerr("FAIL: seed %d ended without a durable summary." % seed_value)
		return {}
	if str(completed_summary.get("outcome", "")) not in ["return", "defeat"]:
		printerr("FAIL: seed %d has unsupported outcome %s" % [seed_value, str(completed_summary.get("outcome", ""))])
		return {}
	if str(completed_summary.get("run_id", "")).is_empty():
		printerr("FAIL: seed %d summary has no run_id." % seed_value)
		return {}
	if int(completed_summary.get("telemetry_schema", 0)) != 1:
		printerr("FAIL: seed %d summary does not contain Stage68B telemetry schema 1." % seed_value)
		return {}
	if int(completed_summary.get("road_placements", 0)) < 1 or int(completed_summary.get("world_placements", 0)) < 1:
		printerr("FAIL: seed %d summary did not persist both placement types." % seed_value)
		return {}

	completed_summary["capture_kind"] = "automated_engine_run"
	completed_summary["capture_seed"] = seed_value
	completed_summary["capture_policy_version"] = 1
	completed_summary["capture_process_frames"] = process_frames
	return completed_summary

func _place_one_legal_road_tile(manager) -> void:
	if manager.tile_hand.is_empty():
		return
	for route_index in range(1, manager.route.size()):
		var placement_preview: Dictionary = manager.tile_system.can_place(manager.route, manager.placed_tiles, route_index)
		if not bool(placement_preview.get("ok", false)):
			continue
		var placement_result: Dictionary = manager.place_tile(0, route_index)
		if bool(placement_result.get("ok", false)):
			return

func _place_one_legal_landscape_tile(manager) -> void:
	if manager.tile_hand.is_empty():
		return
	for y in range(8):
		for x in range(10):
			var cell_id := "%d:%d" % [x, y]
			var placement_preview: Dictionary = manager.tile_system.can_place_world(manager.route, manager.world_tiles, cell_id)
			if not bool(placement_preview.get("ok", false)):
				continue
			var placement_result: Dictionary = manager.place_world_tile(0, cell_id)
			if bool(placement_result.get("ok", false)):
				return

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

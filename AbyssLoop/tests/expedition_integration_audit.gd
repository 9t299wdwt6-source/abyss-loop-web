extends SceneTree

const ExpeditionManagerType = preload("res://scripts/systems/expedition_manager.gd")

const TARGET_PATHS := [
	"user://loop_roguelite_save.json",
	"user://loop_roguelite_save.tmp.json",
	"user://loop_roguelite_save.backup.json",
	"user://loop_roguelite_save.backup.tmp.json",
	"user://loop_roguelite_save.corrupt.json",
	"user://loop_roguelite_save.corrupt.tmp.json",
	"user://loop_roguelite_save.json.previous.tmp",
	"user://loop_roguelite_save.backup.json.previous.tmp"
]

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var originals: Dictionary = {}
	for path in TARGET_PATHS:
		originals[path] = {"exists": FileAccess.file_exists(path), "text": FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""}

	# This script runs only in the release gate's isolated QA profile. Still restore
	# all target files to make direct manual runs non-destructive as well.
	GameState.reset_progress()
	GameState.tutorial_completed = true
	var manager = ExpeditionManagerType.new()
	root.add_child(manager)
	assert(manager.start_run("standard", 540054, "standard", "none", "standard"), "a fresh expedition should commit its first checkpoint")
	assert(GameState.has_saved_expedition(), "new expedition checkpoint must be persisted")
	var saved_seed := int(GameState.saved_expedition.get("run_seed", 0))
	var saved_route: Array = GameState.saved_expedition.get("route", []).duplicate(true)
	var initial_baseline_value: Variant = GameState.saved_expedition.get("run_baseline", {})
	assert(saved_seed == 540054 and not saved_route.is_empty(), "first checkpoint must preserve deterministic run identity and route")
	assert(int(GameState.saved_expedition.get("telemetry_schema", 0)) == 1 and typeof(initial_baseline_value) == TYPE_DICTIONARY, "new checkpoint must carry Stage68B telemetry and start baseline")
	assert(int(initial_baseline_value.get("start_hp", 0)) > 0 and int(initial_baseline_value.get("start_max_hp", 0)) >= int(initial_baseline_value.get("start_hp", 0)), "start baseline must contain a valid initial health record")

	# Resume through a new manager instance: the checkpoint, RNG and pause state must
	# survive a new object lifecycle, not merely an in-memory screen transition.
	manager.free()
	manager = ExpeditionManagerType.new()
	root.add_child(manager)
	assert(manager.restore_saved_run(), "saved expedition must restore through a fresh manager")
	assert(manager.active and manager.paused, "restored expedition must start active but safely paused")
	assert(manager.run_seed == saved_seed and manager.route.size() == saved_route.size(), "resumed expedition must preserve seed and route length")
	assert(int(manager.run_rng.state) == int(GameState.saved_expedition.get("rng_state", -1)), "RNG state must be restored without consuming a draw")
	var saved_elapsed := maxf(0.0, float(GameState.saved_expedition.get("run_elapsed_seconds", -1.0)))
	manager.run_elapsed_seconds = saved_elapsed + 12.0
	assert(manager.save_run_snapshot(), "a telemetry checkpoint should save successfully")
	assert(is_equal_approx(float(GameState.saved_expedition.get("run_elapsed_seconds", -1.0)), saved_elapsed + 12.0), "elapsed process time must persist across checkpoints")

	# Event decisions are synchronous transactions. A duplicate button activation must
	# fail without granting the reward a second time.
	manager.pending_event = {
		"id": "qa_integration_event",
		"name": "Проверка интеграции",
		"choices": [{"id": "take_supply", "title": "Забрать припасы", "effects": {"cost_scrap": 0, "scrap": 7, "crystals": 1, "damage": 0, "heal": 0, "danger_delta": 0.0, "set_flags": [], "clear_flags": []}}],
		"context": {"cell_index": 0, "spawn_bonus": -1.0, "strength_bonus": 0.0, "reward_bonus": 0.0}
	}
	manager.run_ledger["scrap"] = 0
	manager.run_ledger["crystals"] = 0
	var first_choice: Dictionary = manager.resolve_event_choice("take_supply")
	assert(bool(first_choice.get("ok", false)), "valid event choice must resolve")
	var scrap_after_choice := int(manager.run_ledger.get("scrap", 0))
	var crystals_after_choice := int(manager.run_ledger.get("crystals", 0))
	var duplicate_choice: Dictionary = manager.resolve_event_choice("take_supply")
	assert(not bool(duplicate_choice.get("ok", false)), "duplicate event choice must be rejected")
	assert(int(manager.run_ledger.get("scrap", 0)) == scrap_after_choice and int(manager.run_ledger.get("crystals", 0)) == crystals_after_choice, "duplicate event choice must not pay out twice")

	# Invalid checkpoint content passes the outer shape check but must be rejected by
	# SaveSystem; the in-memory checkpoint must stay at the last confirmed version.
	var confirmed_checkpoint: Dictionary = GameState.saved_expedition.duplicate(true)
	var invalid_snapshot: Dictionary = confirmed_checkpoint.duplicate(true)
	invalid_snapshot["route"] = ["not_a_route_cell"]
	assert(not GameState.set_saved_expedition(invalid_snapshot), "invalid route cells must fail save validation")
	assert(GameState.saved_expedition == confirmed_checkpoint, "failed checkpoint write must roll back in-memory state")

	# Simulate a persistence error deterministically with an invalid building level.
	# Deleting a checkpoint must fail without losing the only recoverable snapshot.
	var old_forge_level := int(GameState.buildings.get("forge", 0))
	GameState.buildings["forge"] = -1
	assert(not GameState.clear_saved_expedition(), "failed save must reject checkpoint deletion")
	assert(GameState.saved_expedition == confirmed_checkpoint, "failed deletion must retain the checkpoint")
	var invalid_telemetry_checkpoint: Dictionary = confirmed_checkpoint.duplicate(true)
	invalid_telemetry_checkpoint["run_elapsed_seconds"] = -1.0
	assert(not GameState.set_saved_expedition(invalid_telemetry_checkpoint), "negative telemetry duration must be rejected")
	invalid_telemetry_checkpoint = confirmed_checkpoint.duplicate(true)
	var invalid_baseline: Dictionary = invalid_telemetry_checkpoint.get("run_baseline", {}).duplicate(true)
	invalid_baseline["start_hp"] = -1
	invalid_telemetry_checkpoint["run_baseline"] = invalid_baseline
	assert(not GameState.set_saved_expedition(invalid_telemetry_checkpoint), "negative baseline measurements must be rejected")

	# Settlement must be atomic with checkpoint clearing and retryable. An attempted
	# second call with a different outcome must not turn the original return into defeat.
	GameState.buildings["forge"] = old_forge_level
	manager.run_elapsed_seconds = 123.4
	manager.run_challenge.clear()
	manager.run_contract.clear()
	manager.run_ledger["scrap"] = 13
	manager.run_ledger["crystals"] = 2
	manager.run_ledger["victories"] = 1
	manager.run_ledger["bosses_defeated"] = 0
	manager.run_ledger["elites_defeated"] = 0
	manager.run_ledger["events_resolved"] = 1
	manager.run_ledger["event_history"] = [{"event": "QA", "choice": "Принять припасы"}]
	var runs_before_settlement := int(GameState.runs_completed)
	var permanent_scrap_before := int(GameState.scrap)
	var permanent_crystals_before := int(GameState.crystals)
	var history_before_settlement := GameState.expedition_history.size()
	var difficulty_record_before_value: Variant = GameState.difficulty_records.get("standard", {})
	var difficulty_runs_before := int(difficulty_record_before_value.get("runs", 0)) if typeof(difficulty_record_before_value) == TYPE_DICTIONARY else 0
	GameState.buildings["forge"] = -1
	manager.end_run("return")
	assert(manager.active and manager.paused and manager.pending_end_outcome == "return", "failed settlement must keep the run paused for retry")
	assert(GameState.has_saved_expedition(), "failed settlement must keep a resumable checkpoint")
	assert(int(GameState.runs_completed) == runs_before_settlement, "failed settlement must not increment run count")
	assert(int(GameState.scrap) == permanent_scrap_before and int(GameState.crystals) == permanent_crystals_before, "failed settlement must roll back rewards")
	assert(GameState.expedition_history.size() == history_before_settlement, "failed settlement must not publish a partial history row")
	var failed_record_value: Variant = GameState.difficulty_records.get("standard", {})
	assert((int(failed_record_value.get("runs", 0)) if typeof(failed_record_value) == TYPE_DICTIONARY else 0) == difficulty_runs_before, "failed settlement must roll back difficulty stats")
	manager.end_run("defeat")
	assert(manager.pending_end_outcome == "return" and int(GameState.runs_completed) == runs_before_settlement, "retry must preserve the initial outcome and not double-settle")

	GameState.buildings["forge"] = old_forge_level
	manager.end_run("defeat")
	assert(not manager.active, "settlement should complete after persistence is restored")
	assert(not GameState.has_saved_expedition(), "successful settlement must clear the checkpoint")
	assert(int(GameState.runs_completed) == runs_before_settlement + 1, "successful settlement must count exactly one run")
	assert(str(GameState.last_summary.get("outcome", "")) == "return", "retry must keep the original return outcome")
	assert(int(GameState.scrap) == permanent_scrap_before + 13 and int(GameState.crystals) == permanent_crystals_before + 2, "successful settlement must award the saved loot exactly once")
	assert(GameState.expedition_history.size() == history_before_settlement + 1, "successful settlement must commit exactly one history row")
	var committed_record_value: Variant = GameState.difficulty_records.get("standard", {})
	assert(typeof(committed_record_value) == TYPE_DICTIONARY and int(committed_record_value.get("runs", 0)) == difficulty_runs_before + 1, "successful settlement must commit difficulty stats exactly once")
	var completed_run_id := str(GameState.last_summary.get("run_id", ""))
	assert(not completed_run_id.is_empty() and bool(GameState.last_summary.get("history_saved", false)) and bool(GameState.last_summary.get("difficulty_record_saved", false)), "rich completion metadata must be part of the committed summary")
	assert(int(GameState.last_summary.get("telemetry_schema", 0)) == 1 and int(GameState.last_summary.get("run_elapsed_seconds", 0)) == 123, "completed summary must preserve schema and measured elapsed time")
	assert(int(GameState.last_summary.get("start_hp", 0)) > 0 and int(GameState.last_summary.get("end_max_hp", 0)) > 0, "completed summary must preserve start/end health data")
	var persisted_profile: Dictionary = SaveSystem.load_game()
	var persisted_summary: Variant = persisted_profile.get("last_summary", {})
	assert(typeof(persisted_summary) == TYPE_DICTIONARY and str(persisted_summary.get("run_id", "")) == completed_run_id, "reloading the save must retain the full completed-run summary")
	var persisted_history: Variant = persisted_profile.get("expedition_history", [])
	var matching_history_rows := 0
	if typeof(persisted_history) == TYPE_ARRAY:
		for persisted_row_value in persisted_history:
			if typeof(persisted_row_value) == TYPE_DICTIONARY and str(persisted_row_value.get("run_id", "")) == completed_run_id:
				matching_history_rows += 1
	assert(matching_history_rows == 1, "saved profile must contain exactly one row for the completed run")
	for persisted_row_value in persisted_history:
		if typeof(persisted_row_value) == TYPE_DICTIONARY and str(persisted_row_value.get("run_id", "")) == completed_run_id:
			assert(int(persisted_row_value.get("telemetry_schema", 0)) == 1 and int(persisted_row_value.get("run_elapsed_seconds", 0)) == 123, "campaign history must persist telemetry values")
	manager.end_run("defeat")
	assert(int(GameState.runs_completed) == runs_before_settlement + 1, "a repeated completion call must not settle twice")

	manager.free()
	_restore_original_files(originals)
	print("EXPEDITION INTEGRATION AUDIT PASSED: resume, RNG checkpoint, event anti-double action, failed save rollback, outcome lock, atomic full summary/history/record commit and exactly-once settlement")
	quit(0)

func _restore_original_files(originals: Dictionary) -> void:
	for path in TARGET_PATHS:
		var absolute_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(absolute_path)
		var previous: Dictionary = originals.get(path, {})
		if bool(previous.get("exists", false)):
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null:
				file.store_string(str(previous.get("text", "")))
				file.flush()
				file.close()

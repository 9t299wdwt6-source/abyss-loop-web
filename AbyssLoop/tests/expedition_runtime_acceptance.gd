extends SceneTree

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const ExpeditionManagerScript = preload("res://scripts/systems/expedition_manager.gd")

var _check_count: int = 0
var _failures: Array[String] = []

func _initialize() -> void:
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
		print("EXPEDITION RUNTIME ACCEPTANCE PASSED: %d checks" % _check_count)
		quit(0)
	else:
		printerr("EXPEDITION RUNTIME ACCEPTANCE FAILED: %d/%d checks failed" % [_failures.size(), _check_count])
		for failure in _failures:
			printerr(" - ", failure)
		quit(1)

func _run_acceptance() -> void:
	print("Abyss Loop runtime acceptance — real Godot scene, isolated CI profile")
	_check(not GameState.has_saved_expedition(), "isolated profile starts without a saved expedition")
	if GameState.has_saved_expedition():
		_finish()
		return

	var ui: Node = MainScene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	_check(str(ui.get("screen_mode")) == "base", "main scene opens on the shelter screen")
	if str(ui.get("modal_kind")) == "tutorial":
		ui.call("_finish_tutorial")
	await process_frame
	_check(bool(GameState.tutorial_completed), "tutorial can be dismissed and its completion persists")

	var seed_input := ui.get("seed_input") as LineEdit
	_check(seed_input != null, "expedition preparation exposes the seed input")
	if seed_input == null:
		ui.queue_free()
		await process_frame
		_finish()
		return
	seed_input.text = "8675309"
	ui.call("_start_expedition")
	await process_frame
	var manager = ui.get("manager")
	_check(manager != null and bool(manager.active), "the real UI start action creates an active expedition")
	if manager == null or not bool(manager.active):
		ui.queue_free()
		await process_frame
		_finish()
		return

	_check(str(ui.get("screen_mode")) == "expedition", "starting a run switches the main UI into expedition mode")
	_check(int(manager.run_seed) == 8675309, "the chosen seed is applied to the actual run")
	_check(manager.route.size() == int(ContentRegistry.BALANCE.get("route_cells", 18)), "the run creates the configured closed route")
	_check(manager.tile_hand.size() >= 3, "the first-run tile hand meets its onboarding minimum")
	manager.set_pause(true)

	var hand_before: int = manager.tile_hand.size()
	var invalid_road: Dictionary = manager.place_tile(0, 0)
	_check(not bool(invalid_road.get("ok", false)), "placing a tile on the protected start node is rejected")
	_check(manager.tile_hand.size() == hand_before and manager.placed_tiles.is_empty(), "rejected road placement spends no tile and changes no route cell")

	var road_result: Dictionary = manager.place_tile(0, 1)
	_check(bool(road_result.get("ok", false)), "a valid road node accepts a tile")
	_check(manager.placed_tiles.has("1") and manager.tile_hand.size() == hand_before - 1, "valid road placement records the tile and removes it from hand")

	var world_result: Dictionary = manager.place_world_tile(0, "0:0")
	_check(bool(world_result.get("ok", false)), "a valid landscape cell accepts a tile independently of the road")
	_check(manager.world_tiles.has("0:0"), "landscape placement persists its cell and route-sector metadata")
	_check(int(manager.world_tiles.get("0:0", {}).get("route_index", -1)) >= 0, "landscape placement stores a valid route sector")

	_check(manager.save_run_snapshot(), "an active expedition snapshot saves through the real persistence path")
	var saved_snapshot: Dictionary = GameState.saved_expedition.duplicate(true)
	_check(int(saved_snapshot.get("snapshot_version", 0)) == 4 and int(saved_snapshot.get("telemetry_schema", 0)) == 1, "the saved checkpoint includes the current schema and real-run baseline")
	var restored = ExpeditionManagerScript.new()
	ui.add_child(restored)
	_check(bool(restored.restore_saved_run()), "a second manager restores the persisted expedition checkpoint")
	if bool(restored.active):
		_check(bool(restored.paused), "a restored expedition safely resumes paused")
		_check(int(restored.run_seed) == int(manager.run_seed), "restoration preserves the expedition seed")
		_check(restored.placed_tiles.has("1") and restored.world_tiles.has("0:0"), "restoration preserves both road and landscape placements")
		_check(not restored.run_baseline.is_empty() and float(restored.run_elapsed_seconds) >= 0.0, "restoration preserves available real-run telemetry without inventing missing values")
	restored.active = false
	restored.queue_free()
	await process_frame

	manager.run_ledger["scrap"] = maxi(100, int(manager.run_ledger.get("scrap", 0)))
	manager._begin_expedition_event(1, 0.0, 0.0, 0.0)
	var event: Dictionary = manager.pending_event.duplicate(true)
	_check(not event.is_empty() and typeof(event.get("choices", null)) == TYPE_ARRAY and not event.get("choices", []).is_empty(), "a real event is drawn from the event registry with actionable choices")
	if not event.is_empty():
		manager.changed.emit()
		await process_frame
		_check(str(ui.get("modal_kind")) == "event", "the real UI opens the event-decision modal")
		var tile_count_during_event: int = manager.tile_hand.size()
		var blocked_placement: Dictionary = manager.place_tile(0, 2)
		_check(not bool(blocked_placement.get("ok", false)) and manager.tile_hand.size() == tile_count_during_event, "tile placement is blocked until the pending event is resolved")
		var chosen_id := ""
		var best_score := INF
		for choice_value in event.get("choices", []):
			if typeof(choice_value) != TYPE_DICTIONARY:
				continue
			var choice: Dictionary = choice_value
			var effects_value: Variant = choice.get("effects", {})
			var effects: Dictionary = effects_value if typeof(effects_value) == TYPE_DICTIONARY else {}
			var candidate_id := str(choice.get("id", ""))
			if candidate_id.is_empty() or not bool(manager.event_choice_is_available(candidate_id)):
				continue
			var score: float = float(effects.get("damage", 0)) * 2.0 + float(effects.get("cost_scrap", 0)) - float(effects.get("heal", 0)) * 2.0 - float(effects.get("scrap", 0)) * 0.1
			if score < best_score:
				best_score = score
				chosen_id = candidate_id
		_check(not chosen_id.is_empty(), "the event exposes at least one affordable choice")
		if not chosen_id.is_empty():
			var events_before: int = int(manager.run_ledger.get("events_resolved", 0))
			ui.call("_resolve_event_choice", chosen_id)
			await process_frame
			_check(manager.pending_event.is_empty(), "resolving a choice closes the pending event")
			_check(int(manager.run_ledger.get("events_resolved", 0)) == events_before + 1, "an accepted choice increments event telemetry exactly once")
			_check(not manager.run_ledger.get("event_history", []).is_empty(), "the selected event decision is kept in the expedition history")

	if manager.enemy.is_empty():
		manager._start_encounter(1, 0.0, 0.0, false)
		manager.changed.emit()
	_check(not manager.enemy.is_empty() and not manager.encounter_enemies.is_empty(), "an encounter creates an active enemy group")
	if not manager.enemy.is_empty():
		manager.set_pause(true)
		var hand_during_combat: int = manager.tile_hand.size()
		var combat_placement: Dictionary = manager.place_tile(0, 2)
		_check(not bool(combat_placement.get("ok", false)) and manager.tile_hand.size() == hand_during_combat, "road placement is blocked during combat")
		var encounter_for_test: Array = manager.encounter_enemies.duplicate(true)
		for index in range(encounter_for_test.size()):
			var fighter_value: Variant = encounter_for_test[index]
			if typeof(fighter_value) != TYPE_DICTIONARY:
				continue
			var fighter: Dictionary = fighter_value
			fighter["hp"] = 1
			fighter["max_hp"] = 1
			fighter["defense"] = 0
			encounter_for_test[index] = fighter
		manager.encounter_enemies = encounter_for_test
		manager.enemy = manager.encounter_enemies[0]
		var victories_before: int = int(manager.run_ledger.get("victories", 0))
		for _step in range(24):
			if manager.enemy.is_empty():
				break
			if int(manager.pending_perk_count) > 0:
				if manager.pending_perk_choices.is_empty():
					break
				var perk_value: Variant = manager.pending_perk_choices[0]
				var perk_id: String = str(perk_value.get("id", "")) if typeof(perk_value) == TYPE_DICTIONARY else str(perk_value)
				if perk_id.is_empty() or not bool(manager.choose_perk(perk_id)):
					break
			else:
				manager.combat_timers["hero"] = 100.0
				manager._tick_combat(0.01)
		_check(int(manager.run_ledger.get("victories", 0)) > victories_before, "real combat processing can defeat an enemy and record its reward once")
		_check(manager.enemy.is_empty() or int(manager.run_ledger.get("victories", 0)) > victories_before, "combat keeps a valid focused target or advances after victory")

	manager.enemy.clear()
	manager.encounter_enemies.clear()
	manager.pending_event.clear()
	manager.pending_perk_count = 0
	manager.pending_perk_choices.clear()
	manager.set_pause(true)
	_check(manager.save_run_snapshot(), "the final expedition checkpoint remains saveable after gameplay changes")

	manager.end_run("return")
	await process_frame
	_check(not bool(manager.active), "return ends the active expedition")
	_check(not GameState.has_saved_expedition(), "successful return atomically removes the saved checkpoint")
	_check(str(GameState.last_summary.get("outcome", "")) == "return", "the run result is written as a return")
	_check(int(GameState.runs_completed) >= 1, "the campaign records the completed expedition")
	_check(str(ui.get("screen_mode")) == "summary", "the completion signal renders the real debrief screen")

	ui.call("_render_base")
	await process_frame
	_check(str(ui.get("screen_mode")) == "base", "the debrief can return to the shelter screen")
	ui.queue_free()
	await process_frame
	_finish()

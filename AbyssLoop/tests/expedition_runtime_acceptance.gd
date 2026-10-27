extends Node

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const ExpeditionManagerScript = preload("res://scripts/systems/expedition_manager.gd")
const TileSystemType = preload("res://scripts/systems/tile_system.gd")

var _check_count: int = 0
var _failures: Array[String] = []

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
		print("EXPEDITION RUNTIME ACCEPTANCE PASSED: %d checks" % _check_count)
		get_tree().quit(0)
	else:
		printerr("EXPEDITION RUNTIME ACCEPTANCE FAILED: %d/%d checks failed" % [_failures.size(), _check_count])
		for failure in _failures:
			printerr(" - ", failure)
		get_tree().quit(1)

func _run_acceptance() -> void:
	print("Abyss Loop runtime acceptance — real Godot scene, isolated CI profile")
	_check(not GameState.has_saved_expedition(), "isolated profile starts without a saved expedition")
	if GameState.has_saved_expedition():
		_finish()
		return

	var ui: Node = MainScene.instantiate()
	get_tree().root.add_child(ui)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(str(ui.get("screen_mode")) == "base", "main scene opens on the shelter screen")
	if str(ui.get("modal_kind")) == "tutorial":
		ui.call("_finish_tutorial")
	await get_tree().process_frame
	_check(bool(GameState.tutorial_completed), "tutorial can be dismissed and its completion persists")

	var seed_input := ui.get("seed_input") as LineEdit
	_check(seed_input != null, "expedition preparation exposes the seed input")
	if seed_input == null:
		ui.queue_free()
		await get_tree().process_frame
		_finish()
		return
	seed_input.text = "8675309"
	ui.call("_start_expedition")
	await get_tree().process_frame
	var manager = ui.get("manager")
	_check(manager != null and bool(manager.active), "the real UI start action creates an active expedition")
	if manager == null or not bool(manager.active):
		ui.queue_free()
		await get_tree().process_frame
		_finish()
		return

	_check(str(ui.get("screen_mode")) == "expedition", "starting a run switches the main UI into expedition mode")
	_check(int(manager.run_seed) == 8675309, "the chosen seed is applied to the actual run")
	_check(manager.route.size() == int(ContentRegistry.BALANCE.get("route_cells", 18)), "the run creates the configured closed route")
	_check(manager.tile_hand.size() >= 3, "the first-run tile hand meets its onboarding minimum")

	# Stage 89 — exercise the actual discovery mask against the active seeded contour.
	var active_geometry_seed: int = int(manager.get_route_geometry_seed())
	var initial_discovery: Dictionary = manager.discovered_world_cells.duplicate(true)
	_check(active_geometry_seed > 0, "a new expedition persists a positive route-geometry seed")
	_check(not initial_discovery.is_empty(), "a new expedition reveals the starting landscape around its first road node")
	var active_road_ids: Dictionary = {}
	var active_road_cells: Array[Vector2i] = TileSystemType.get_road_grid_coordinates_for_seed(str(manager.get_route_shape_id()), active_geometry_seed)
	_check(active_road_cells.size() == 34, "the active map contour contains the expected 34 unique road cells")
	for road_cell_value in active_road_cells:
		var road_coord: Vector2i = road_cell_value
		active_road_ids[TileSystemType.map_world_cell_id(road_coord.x, road_coord.y)] = true
	var initial_mask_valid := true
	for discovered_id_value in initial_discovery.keys():
		var discovered_id := str(discovered_id_value)
		if not TileSystemType.is_map_world_cell_id(discovered_id) or not bool(initial_discovery.get(discovered_id_value, false)) or active_road_ids.has(discovered_id):
			initial_mask_valid = false
	_check(initial_mask_valid, "the initial discovery mask uses canonical modern IDs and never reveals road cells")
	var initial_discovery_count: int = initial_discovery.size()
	manager._reveal_world_cells_near_route_index(int(manager.route.size() / 2))
	var expanded_discovery: Dictionary = manager.discovered_world_cells.duplicate(true)
	_check(expanded_discovery.size() > initial_discovery_count, "visiting a distant route index reveals additional off-road landscape")
	var expanded_mask_valid := true
	for expanded_id_value in expanded_discovery.keys():
		var expanded_id := str(expanded_id_value)
		if not TileSystemType.is_map_world_cell_id(expanded_id) or not bool(expanded_discovery.get(expanded_id_value, false)) or active_road_ids.has(expanded_id):
			expanded_mask_valid = false
	_check(expanded_mask_valid, "the expanded discovery mask remains canonical and excludes all road cells")
	manager.set_pause(true)

	# The equipment/backpack panel should appear only during actual combat.
	var gear_panel := ui.get("expedition_gear_panel") as PanelContainer
	_check(gear_panel != null, "the expedition UI exposes a dedicated battle equipment panel")
	manager.enemy.clear()
	ui.call("_sync_expedition_view", false)
	_check(gear_panel != null and not gear_panel.visible, "equipment panel stays hidden during route exploration")
	var empty_enemy_state: Dictionary = manager.enemy.duplicate(true)
	manager.enemy = {"id": "ui_visibility_probe", "name": "Проверка интерфейса", "hp": 1, "max_hp": 1, "is_boss": false, "is_elite": false}
	ui.call("_sync_expedition_view", false)
	_check(gear_panel != null and gear_panel.visible, "equipment and backpack appear during combat")
	manager.enemy = empty_enemy_state
	ui.call("_sync_expedition_view", false)
	_check(gear_panel != null and not gear_panel.visible, "equipment panel hides again when combat ends")

	var tile_grid := ui.get("tile_hand_grid") as GridContainer
	_check(tile_grid != null and tile_grid.get_child_count() >= 3, "tile hand renders as selectable category cards")
	if tile_grid != null and tile_grid.get_child_count() > 0:
		var first_card := tile_grid.get_child(0) as Button
		var idle_card_style := first_card.get_theme_stylebox("normal") as StyleBoxFlat
		var idle_card_background := idle_card_style.bg_color if idle_card_style != null else Color.TRANSPARENT
		_check(idle_card_style != null and idle_card_style.border_width_left >= 1 and idle_card_style.border_color != Color("#efc36b"), "unselected tile cards use a restrained category border")
		ui.call("_on_tile_selected", 0)
		await get_tree().process_frame
		tile_grid = ui.get("tile_hand_grid") as GridContainer
		var selected_card := tile_grid.get_child(0) as Button if tile_grid != null and tile_grid.get_child_count() > 0 else null
		var selected_card_style := selected_card.get_theme_stylebox("normal") as StyleBoxFlat if selected_card != null else null
		var selected_style_is_clear := selected_card_style != null and selected_card_style.border_width_left >= 2 and (selected_card_style.border_color == Color("#efc36b") or selected_card_style.bg_color != idle_card_background)
		_check(selected_style_is_clear, "selected tile card gains a clear amber or high-contrast selection border")
		ui.call("_on_tile_selected", 0)
		await get_tree().process_frame

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
	_check(saved_snapshot.get("discovered_world_cells", {}) == manager.discovered_world_cells, "the checkpoint persists the exact discovered-cell mask")
	_check(int(saved_snapshot.get("route_geometry_seed", 0)) == active_geometry_seed, "the checkpoint persists the geometry seed used by the discovery mask")
	var restored = ExpeditionManagerScript.new()
	ui.add_child(restored)
	_check(bool(restored.restore_saved_run()), "a second manager restores the persisted expedition checkpoint")
	if bool(restored.active):
		_check(bool(restored.paused), "a restored expedition safely resumes paused")
		_check(int(restored.run_seed) == int(manager.run_seed), "restoration preserves the expedition seed")
		_check(restored.placed_tiles.has("1") and restored.world_tiles.has("0:0"), "restoration preserves both road and landscape placements")
		_check(not restored.run_baseline.is_empty() and float(restored.run_elapsed_seconds) >= 0.0, "restoration preserves available real-run telemetry without inventing missing values")
		_check(restored.discovered_world_cells == manager.discovered_world_cells, "save/restore reproduces the same discovery mask exactly")
		_check(int(restored.get_route_geometry_seed()) == active_geometry_seed, "save/restore keeps map discovery tied to the same road contour")
	var preserved_checkpoint: Dictionary = GameState.saved_expedition.duplicate(true)
	var legacy_snapshot: Dictionary = saved_snapshot.duplicate(true)
	legacy_snapshot.erase("discovered_world_cells")
	GameState.saved_expedition = legacy_snapshot
	var legacy_restored = ExpeditionManagerScript.new()
	ui.add_child(legacy_restored)
	var legacy_restore_ok: bool = legacy_restored.restore_saved_run()
	_check(legacy_restore_ok, "a pre-Stage88 snapshot without a discovery mask remains restorable")
	if legacy_restore_ok:
		var legacy_mask: Dictionary = legacy_restored.discovered_world_cells.duplicate(true)
		var expected_legacy_mask_size: int = TileSystemType.MAP_COLUMNS * TileSystemType.MAP_ROWS - active_road_ids.size()
		_check(legacy_mask.size() == expected_legacy_mask_size, "legacy restoration falls back to every off-road landscape cell")
		var legacy_mask_valid := true
		for legacy_id_value in legacy_mask.keys():
			var legacy_id := str(legacy_id_value)
			if not TileSystemType.is_map_world_cell_id(legacy_id) or not bool(legacy_mask.get(legacy_id_value, false)) or active_road_ids.has(legacy_id):
				legacy_mask_valid = false
		_check(legacy_mask_valid, "legacy discovery migration excludes road cells and normalizes all IDs")
	legacy_restored.active = false
	legacy_restored.queue_free()
	await get_tree().process_frame
	GameState.saved_expedition = preserved_checkpoint
	restored.active = false
	restored.queue_free()
	await get_tree().process_frame

	manager.run_ledger["scrap"] = maxi(100, int(manager.run_ledger.get("scrap", 0)))
	manager._begin_expedition_event(1, 0.0, 0.0, 0.0)
	var event: Dictionary = manager.pending_event.duplicate(true)
	_check(not event.is_empty() and typeof(event.get("choices", null)) == TYPE_ARRAY and not event.get("choices", []).is_empty(), "a real event is drawn from the event registry with actionable choices")
	if not event.is_empty():
		manager.changed.emit()
		await get_tree().process_frame
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
			await get_tree().process_frame
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
	await get_tree().process_frame
	_check(not bool(manager.active), "return ends the active expedition")
	_check(not GameState.has_saved_expedition(), "successful return atomically removes the saved checkpoint")
	_check(str(GameState.last_summary.get("outcome", "")) == "return", "the run result is written as a return")
	_check(int(GameState.runs_completed) >= 1, "the campaign records the completed expedition")
	_check(str(ui.get("screen_mode")) == "summary", "the completion signal renders the real debrief screen")

	ui.call("_render_base")
	await get_tree().process_frame
	_check(str(ui.get("screen_mode")) == "base", "the debrief can return to the shelter screen")
	ui.queue_free()
	await get_tree().process_frame
	_finish()

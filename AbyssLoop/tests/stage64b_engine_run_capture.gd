extends Node

const ExpeditionManagerScript = preload("res://scripts/systems/expedition_manager.gd")
const TileSystemScript = preload("res://scripts/systems/tile_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const OUTPUT_PATH: String = "user://STAGE64B_AUTOMATED_ENGINE_RUNS.json"
const MAX_SIMULATION_STEPS_PER_RUN: int = 20000
const ROUTE_SCALED_DELTA: float = 1.24
const COMBAT_SCALED_DELTA: float = 0.05
const FLOOR_NUMBERS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
const BASE_SEEDS: Array[int] = [8675309, 8675311, 8675313, 8675317, 8675323]
const MODIFIER_FLOORS: Array[int] = [1, 4, 8]
const MODIFIER_IDS: Array[String] = ["resonance", "scarce", "unstable"]

var _runs: Array[Dictionary] = []
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run_capture")

func _run_capture() -> void:
	var cases := _build_case_matrix()
	print("Stage64B eight-floor baseline matrix: %d real-engine observations." % cases.size())
	print("Coverage: all eight floors x five fixed seeds, using the standard route modifier and no contract.")
	print("Production hero/enemy stats, loot and combat formulas remain unchanged.")
	for case_value in cases:
		var case_data: Dictionary = case_value
		var row: Dictionary = await _capture_case(case_data)
		if row.is_empty():
			_failures.append("Case %s / floor %d / seed %d did not produce a valid completed run." % [
				str(case_data.get("capture_group", "unknown")),
				int(case_data.get("floor_number", 0)),
				int(case_data.get("seed", 0))
			])
			printerr("FAIL: %s floor=%d seed=%d" % [
				str(case_data.get("capture_group", "unknown")),
				int(case_data.get("floor_number", 0)),
				int(case_data.get("seed", 0))
			])
			break
		_runs.append(row)
		print("CAPTURED: group=%s floor=%d name=%s modifier=%s seed=%d outcome=%s cleared=%s loops=%d bosses=%d victories=%d events=%d autoequips=%d placements=%d seconds=%d" % [
			str(row.get("capture_group", "unknown")),
			int(row.get("floor_number", 0)),
			str(row.get("floor_name", "")),
			str(row.get("modifier_id", "standard")),
			int(row.get("seed", 0)),
			str(row.get("outcome", "unknown")),
			str(row.get("floor_cleared", false)),
			int(row.get("loops", 0)),
			int(row.get("bosses_defeated", 0)),
			int(row.get("victories", 0)),
			int(row.get("events_resolved", 0)),
			int(row.get("capture_auto_equips", 0)),
			int(row.get("capture_strategic_placements", 0)),
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
			"floor_numbers": FLOOR_NUMBERS,
			"base_seeds": BASE_SEEDS,
			"runs_expected": cases.size(),
			"runs_completed": _runs.size(),
			"route_scaled_delta": ROUTE_SCALED_DELTA,
			"combat_scaled_delta": COMBAT_SCALED_DELTA,
"policy": "The actual ExpeditionManager route, placement, encounter, combat, event, loot, perk, floor-guardian, equip_bag_item and settlement methods are executed with production hero/enemy/combat/reward formulas. A clean isolated profile exposes each test floor so the floor can be sampled independently. The scripted controller equips a bag item only when production item_power is strictly higher than the currently equipped item in that slot; all equipment changes use the production equip method. During safe route intervals it plays one legal card at a time, preferring healing, control and supply when health is low, and reserving danger tiles for healthier states or a nearly full hand. It never writes hero/enemy stats, loot, damage or rewards. Results are player-policy QA, not human playtests or a balance verdict."
		},
		"runs": _runs,
		"failures": _failures
	}
	var absolute_report_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_report_path.get_base_dir())
	var output_file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if output_file == null:
		printerr("Could not write Stage71 floor balance matrix: ", OUTPUT_PATH)
		get_tree().quit(1)
		return
	output_file.store_string(JSON.stringify(report, "\t") + "\n")
	output_file.close()
	if _runs.size() != cases.size() or not _failures.is_empty():
		printerr("STAGE71 FLOOR BALANCE MATRIX FAILED: %d/%d cases; %s" % [_runs.size(), cases.size(), str(_failures)])
		get_tree().quit(1)
		return
	print("STAGE64B FLOOR BASELINE MATRIX PASSED: %d observations." % _runs.size())
	print("The report groups results by floor and modifier; it does not infer a balance verdict.")
	get_tree().quit(0)

func _build_case_matrix() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	for floor_number in FLOOR_NUMBERS:
		for seed_value in BASE_SEEDS:
			cases.append({
				"capture_group": "floor_baseline",
				"floor_number": floor_number,
				"modifier_id": "standard",
				"contract_id": "none",
				"seed": seed_value
			})
	return cases

func _capture_case(case_data: Dictionary) -> Dictionary:
	GameState.reset_progress()
	await get_tree().process_frame
	var floor_number: int = clampi(int(case_data.get("floor_number", 1)), 1, ContentRegistry.FLOOR_COUNT)
	var seed_value: int = int(case_data.get("seed", 0))
	var modifier_id: String = str(case_data.get("modifier_id", "standard"))
	var contract_id: String = str(case_data.get("contract_id", "none"))
	# This is an isolated scenario runner, not an unlock exploit in the player flow.
	GameState.highest_unlocked_floor = floor_number

	var manager = ExpeditionManagerScript.new()
	manager.name = "Stage71_Floor%d_%s_%d" % [floor_number, modifier_id, seed_value]
	get_tree().root.add_child(manager)
	await get_tree().process_frame
	if not bool(manager.start_run("standard", seed_value, modifier_id, contract_id, "standard", floor_number)):
		printerr("FAIL: start_run rejected floor=%d modifier=%s seed=%d" % [floor_number, modifier_id, seed_value])
		manager.queue_free()
		await get_tree().process_frame
		return {}
	manager.set_pause(true)
	manager.set_speed(3.0)
	if not _place_one_legal_road_tile(manager):
		printerr("FAIL: no legal road tile for floor=%d seed=%d" % [floor_number, seed_value])
		manager.active = false
		manager.queue_free()
		await get_tree().process_frame
		return {}
	if not _place_one_legal_landscape_tile(manager):
		printerr("FAIL: no legal landscape tile for floor=%d seed=%d" % [floor_number, seed_value])
		manager.active = false
		manager.queue_free()
		await get_tree().process_frame
		return {}
	manager.set_pause(false)

	var simulation_steps: int = 0
	var auto_equips: int = 0
	var strategic_placements: int = 0
	var case_failed: bool = false
	while bool(manager.active) and simulation_steps < MAX_SIMULATION_STEPS_PER_RUN:
		simulation_steps += 1
		if not str(manager.pending_end_outcome).is_empty():
			_failures.append("Floor %d modifier %s seed %d stalled after a save failure." % [floor_number, modifier_id, seed_value])
			case_failed = true
			break
		if not manager.pending_event.is_empty():
			var choice_id := _first_available_event_choice(manager)
			if choice_id.is_empty():
				_failures.append("Floor %d seed %d offered no affordable event choice." % [floor_number, seed_value])
				case_failed = true
				break
			var event_result: Dictionary = manager.resolve_event_choice(choice_id)
			if not bool(event_result.get("ok", false)):
				_failures.append("Floor %d seed %d rejected an available event choice." % [floor_number, seed_value])
				case_failed = true
				break
			manager._update_objective_progress()
			continue
		if int(manager.pending_perk_count) > 0:
			var perk_id := _first_offered_perk(manager)
			if perk_id.is_empty() or not bool(manager.choose_perk(perk_id)):
				_failures.append("Floor %d seed %d has an invalid offered perk." % [floor_number, seed_value])
				case_failed = true
				break
			manager._update_objective_progress()
			continue
		if not manager.enemy.is_empty():
			manager._tick_combat(COMBAT_SCALED_DELTA)
			manager.run_elapsed_seconds += COMBAT_SCALED_DELTA / maxf(1.0, float(manager.speed))
			if manager.active:
				manager._update_objective_progress()
			continue
		auto_equips += _equip_better_bag_items(manager)
		if _place_best_legal_tile(manager):
			strategic_placements += 1
		var previous_steps: int = int(manager.processed_steps)
		manager.distance = float(previous_steps)
		manager._tick_route(ROUTE_SCALED_DELTA)
		manager.run_elapsed_seconds += ROUTE_SCALED_DELTA / maxf(1.0, float(manager.speed))
		if manager.active:
			manager._update_objective_progress()
		if bool(manager.active) and int(manager.processed_steps) == previous_steps and manager.enemy.is_empty() and manager.pending_event.is_empty() and int(manager.pending_perk_count) == 0:
			_failures.append("Floor %d seed %d route failed to advance." % [floor_number, seed_value])
			case_failed = true
			break
	if bool(manager.active):
		_failures.append("Floor %d modifier %s seed %d exceeded the bounded simulation." % [floor_number, modifier_id, seed_value])
		case_failed = true
		manager.active = false
	var completed_summary: Dictionary = GameState.last_summary.duplicate(true)
	manager.queue_free()
	await get_tree().process_frame
	if case_failed or completed_summary.is_empty():
		return {}
	if str(completed_summary.get("outcome", "")) not in ["return", "defeat"]:
		_failures.append("Floor %d seed %d has unsupported outcome %s." % [floor_number, seed_value, str(completed_summary.get("outcome", ""))])
		return {}
	if int(completed_summary.get("floor_number", 0)) != floor_number:
		_failures.append("Floor %d seed %d summary carries the wrong floor number." % [floor_number, seed_value])
		return {}
	if int(completed_summary.get("telemetry_schema", 0)) != 1 or str(completed_summary.get("run_id", "")).is_empty():
		_failures.append("Floor %d seed %d summary lacks durable Stage68B telemetry." % [floor_number, seed_value])
		return {}
	if int(completed_summary.get("road_placements", 0)) < 1 or int(completed_summary.get("world_placements", 0)) < 1:
		_failures.append("Floor %d seed %d lost its placement telemetry." % [floor_number, seed_value])
		return {}
	var original_run_id: String = str(completed_summary.get("run_id", ""))
	completed_summary["source_run_id"] = original_run_id
	completed_summary["run_id"] = "qa-stage64b-%s-floor%02d-%s-%d" % [str(case_data.get("capture_group", "floor")), floor_number, modifier_id, seed_value]
	completed_summary["capture_kind"] = "automated_engine_run"
	completed_summary["capture_group"] = str(case_data.get("capture_group", "floor_baseline"))
	completed_summary["capture_floor_number"] = floor_number
	completed_summary["capture_seed"] = seed_value
	completed_summary["capture_modifier_id"] = modifier_id
	completed_summary["capture_contract_id"] = contract_id
	completed_summary["capture_auto_equips"] = auto_equips
	completed_summary["capture_strategic_placements"] = strategic_placements
	return completed_summary

func _place_best_legal_tile(manager: Variant) -> bool:
	# One actual card can be played during a safe route interval. The policy values
	# healing/control/supply above extra danger when health is low; all legality,
	# rewards and synergy outcomes remain the production game rules.
	if not manager.enemy.is_empty() or not manager.pending_event.is_empty() or int(manager.pending_perk_count) > 0:
		return false
	if manager.tile_hand.is_empty():
		return false
	var best_score: float = -INF
	var best_hand_index: int = -1
	var best_route_index: int = -1
	var best_world_cell: String = ""
	var best_is_world: bool = false
	var first_route_index: int = posmod(int(manager.processed_steps) + 1, manager.route.size())
	for hand_index in range(manager.tile_hand.size()):
		var tile_value: Variant = manager.tile_hand[hand_index]
		if typeof(tile_value) != TYPE_DICTIONARY:
			continue
		var tile: Dictionary = tile_value
		var tile_id: String = str(tile.get("id", ""))
		var definition_value: Variant = ContentRegistry.TILE_DEFS.get(tile_id, {})
		var definition: Dictionary = definition_value if typeof(definition_value) == TYPE_DICTIONARY else {}
		var zone: String = str(tile.get("placement_zone", definition.get("placement_zone", "any")))
		var utility: float = _tile_utility_score(tile, manager)
		var road_candidate_found: bool = false
		if zone in ["any", "road"]:
			for offset in range(manager.route.size()):
				var route_index: int = posmod(first_route_index + offset, manager.route.size())
				var route_preview: Dictionary = manager.tile_system.can_place(manager.route, manager.placed_tiles, route_index, tile)
				if not bool(route_preview.get("ok", false)):
					continue
				road_candidate_found = true
				var score: float = utility + 1.5
				if score > best_score:
					best_score = score
					best_hand_index = hand_index
					best_route_index = route_index
					best_world_cell = ""
					best_is_world = false
		if zone in ["landscape", "roadside"] or (zone == "any" and not road_candidate_found):
			var world_target_found: bool = false
			for y in range(TileSystemScript.MAP_ROWS):
				for x in range(TileSystemScript.MAP_COLUMNS):
					var cell_id: String = TileSystemScript.map_world_cell_id(x, y)
					var world_preview: Dictionary = manager.tile_system.can_place_world(
						manager.route, manager.world_tiles, cell_id, tile,
						manager.get_route_shape_id(), manager.get_route_geometry_seed()
					)
					if not bool(world_preview.get("ok", false)):
						continue
					world_target_found = true
					var world_score: float = utility + (0.5 if zone in ["landscape", "roadside"] else -1.5)
					if world_score > best_score:
						best_score = world_score
						best_hand_index = hand_index
						best_route_index = -1
						best_world_cell = cell_id
						best_is_world = true
					break
				if world_target_found:
					break
	if best_hand_index < 0:
		return false
	# Save dangerous cards for a better opportunity unless the hand is nearly full.
	if best_score < 0.0 and manager.tile_hand.size() < maxi(1, int(ContentRegistry.BALANCE.get("max_tile_hand", 4)) - 1):
		return false
	var placement_result: Dictionary
	if best_is_world:
		placement_result = manager.place_world_tile(best_hand_index, best_world_cell)
	else:
		placement_result = manager.place_tile(best_hand_index, best_route_index)
	if not bool(placement_result.get("ok", false)):
		return false
	manager._update_objective_progress()
	return true

func _tile_utility_score(tile: Dictionary, manager: Variant) -> float:
	var tile_id: String = str(tile.get("id", ""))
	var max_hp: float = maxf(1.0, float(manager.hero.get("max_hp", 1)))
	var health_ratio: float = clampf(float(manager.hero.get("hp", 0)) / max_hp, 0.0, 1.0)
	var missing_health: float = 1.0 - health_ratio
	match tile_id:
		"ward":
			return 11.0 + missing_health * 3.0
		"echo_spring":
			return 10.0 + missing_health * 5.0
		"snare":
			return 8.0 + (3.0 if health_ratio < 0.7 else 0.0)
		"cache":
			return 8.0
		"lost_convoy":
			return 9.0
		"archive":
			return 8.0
		"signal":
			return 7.0
		"spore_garden":
			return 7.0 + missing_health * 4.0
		"crystal_hive", "echo_obelisk":
			return 5.5
		"hunt", "rift", "fault_line", "hunter_marker":
			return 5.0 if health_ratio >= 0.90 else -6.0
		"nursery", "bone_orchard":
			return 3.0 if health_ratio >= 0.90 else -5.0
		_:
			var definition_value: Variant = ContentRegistry.TILE_DEFS.get(tile_id, {})
			var definition: Dictionary = definition_value if typeof(definition_value) == TYPE_DICTIONARY else {}
			match str(definition.get("kind", "")):
				"support":
					return 9.0 + missing_health * 3.0
				"control":
					return 7.0
				"economy":
					return 7.0
				"knowledge":
					return 6.0
				"rare":
					return 5.0
				"danger":
					return 4.0 if health_ratio >= 0.90 else -4.0
				_:
					return 1.0


func _equip_better_bag_items(manager: Variant) -> int:
	# Automated QA emulates a basic player pausing between encounters to equip
	# an actual loot drop only when it improves the item-power score in that slot.
	# It never edits hero stats directly; all changes go through production equip logic.
	if not manager.enemy.is_empty() or not manager.pending_event.is_empty() or int(manager.pending_perk_count) > 0:
		return 0
	var equip_count: int = 0
	var bag_snapshot: Array = manager.bag.duplicate(true)
	for bag_value in bag_snapshot:
		if typeof(bag_value) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = bag_value
		var slot: String = str(candidate.get("slot", ""))
		if not InventorySystemScript.EQUIPMENT_SLOTS.has(slot):
			continue
		var item_id: String = str(candidate.get("id", ""))
		if item_id.is_empty():
			continue
		var current_value: Variant = manager.equipment.get(slot, {})
		var current_item: Dictionary = current_value if typeof(current_value) == TYPE_DICTIONARY else {}
		var candidate_power: float = manager.inventory_system.item_power(candidate)
		var current_power: float = manager.inventory_system.item_power(current_item) if not current_item.is_empty() else -1.0
		if not current_item.is_empty() and candidate_power <= current_power + 0.01:
			continue
		var result: Dictionary = manager.equip_bag_item(item_id)
		if bool(result.get("ok", false)):
			equip_count += 1
	return equip_count

func _place_one_legal_road_tile(manager: Variant) -> bool:
	for hand_index in range(manager.tile_hand.size()):
		if _try_place_road_from_hand(manager, hand_index):
			return true
	var supplemental_draws: int = 0
	while supplemental_draws < 12:
		var unlock_rare: bool = manager.loop_count >= 3 or GameState.get_unlock_effect("unlock_rare_tiles") > 0.0
		var supplemental_tile: Dictionary = manager.tile_system.draw_tile(manager._rng_for_draw(), unlock_rare)
		var supplemental_index: int = manager.tile_hand.size()
		manager.tile_hand.append(supplemental_tile)
		supplemental_draws += 1
		if _try_place_road_from_hand(manager, supplemental_index):
			return true
		if supplemental_index < manager.tile_hand.size():
			manager.tile_hand.remove_at(supplemental_index)
	return false

func _try_place_road_from_hand(manager: Variant, hand_index: int) -> bool:
	if hand_index < 0 or hand_index >= manager.tile_hand.size():
		return false
	var tile_value: Variant = manager.tile_hand[hand_index]
	if typeof(tile_value) != TYPE_DICTIONARY:
		return false
	var tile: Dictionary = tile_value
	for route_index in range(1, manager.route.size()):
		var preview: Dictionary = manager.tile_system.can_place(manager.route, manager.placed_tiles, route_index, tile)
		if not bool(preview.get("ok", false)):
			continue
		var result: Dictionary = manager.place_tile(hand_index, route_index)
		if bool(result.get("ok", false)):
			return true
	return false

func _place_one_legal_landscape_tile(manager: Variant) -> bool:
	for hand_index in range(manager.tile_hand.size()):
		if _try_place_landscape_from_hand(manager, hand_index):
			return true
	var supplemental_draws: int = 0
	while supplemental_draws < 12:
		var unlock_rare: bool = manager.loop_count >= 3 or GameState.get_unlock_effect("unlock_rare_tiles") > 0.0
		var supplemental_tile: Dictionary = manager.tile_system.draw_tile(manager._rng_for_draw(), unlock_rare)
		var supplemental_index: int = manager.tile_hand.size()
		manager.tile_hand.append(supplemental_tile)
		supplemental_draws += 1
		if _try_place_landscape_from_hand(manager, supplemental_index):
			return true
		if supplemental_index < manager.tile_hand.size():
			manager.tile_hand.remove_at(supplemental_index)
	return false

func _try_place_landscape_from_hand(manager: Variant, hand_index: int) -> bool:
	if hand_index < 0 or hand_index >= manager.tile_hand.size():
		return false
	var tile_value: Variant = manager.tile_hand[hand_index]
	if typeof(tile_value) != TYPE_DICTIONARY:
		return false
	var tile: Dictionary = tile_value
	for y in range(TileSystemScript.MAP_ROWS):
		for x in range(TileSystemScript.MAP_COLUMNS):
			var cell_id: String = TileSystemScript.map_world_cell_id(x, y)
			var preview: Dictionary = manager.tile_system.can_place_world(manager.route, manager.world_tiles, cell_id, tile, manager.get_route_shape_id(), manager.get_route_geometry_seed())
			if not bool(preview.get("ok", false)):
				continue
			var result: Dictionary = manager.place_world_tile(hand_index, cell_id)
			if bool(result.get("ok", false)):
				return true
	return false

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
	var choices_value: Variant = manager.pending_perk_choices
	if typeof(choices_value) != TYPE_ARRAY or choices_value.is_empty():
		return ""
	var first_value: Variant = choices_value[0]
	if typeof(first_value) == TYPE_DICTIONARY:
		return str(first_value.get("id", ""))
	return str(first_value)

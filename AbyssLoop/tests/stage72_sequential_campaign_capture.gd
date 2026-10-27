extends Node

const ExpeditionManagerScript = preload("res://scripts/systems/expedition_manager.gd")
const BaseSystemScript = preload("res://scripts/systems/base_system.gd")
const TileSystemScript = preload("res://scripts/systems/tile_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const OUTPUT_PATH: String = "user://STAGE72_SEQUENTIAL_CAMPAIGNS.json"
const MAX_SIMULATION_STEPS_PER_FLOOR: int = 20000
const ROUTE_SCALED_DELTA: float = 1.24
const COMBAT_SCALED_DELTA: float = 0.05
const FLOOR_NUMBERS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
const CAMPAIGN_SEEDS: Array[int] = [8676203, 8676211, 8676221, 8676233, 8676241]
const META_CAMPAIGN_SEEDS: Array[int] = [8676203, 8676211, 8676221]

var _runs: Array[Dictionary] = []
var _failures: Array[String] = []
var _campaign_results: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("_run_capture")

func _run_capture() -> void:
	print("Stage72 capture: %d baseline campaigns and %d matched resource-investment campaigns." % [CAMPAIGN_SEEDS.size(), META_CAMPAIGN_SEEDS.size()])
	print("Production combat, enemy stats, equipment, rewards, route and guardian conditions remain unchanged.")
	for seed_value in CAMPAIGN_SEEDS:
		await _capture_campaign(seed_value, "sequential_campaign")
	for seed_value in META_CAMPAIGN_SEEDS:
		await _capture_campaign(seed_value, "sequential_campaign_meta")

	var report := {
		"metadata": {
			"project": "Abyss Loop",
			"game_version": str(ProjectSettings.get_setting("application/config/version", "unknown")),
			"godot_version": str(Engine.get_version_info().get("string", "")),
			"capture_kind": "automated_engine_run",
			"not_human_playtest": true,
			"not_a_balance_verdict": true,
			"capture_group": "paired_campaign_scenarios",
			"scenario": "paired_campaign_scenarios",
			"floor_numbers": FLOOR_NUMBERS,
			"campaign_seeds": CAMPAIGN_SEEDS,
			"meta_campaign_seeds": META_CAMPAIGN_SEEDS,
			"scenario_groups": ["sequential_campaign", "sequential_campaign_meta"],
			"runs_expected_maximum": (CAMPAIGN_SEEDS.size() + META_CAMPAIGN_SEEDS.size()) * ContentRegistry.FLOOR_COUNT,
			"runs_completed": _runs.size(),
			"campaign_results": _campaign_results,
			"route_scaled_delta": ROUTE_SCALED_DELTA,
			"combat_scaled_delta": COMBAT_SCALED_DELTA,
			"policy": "Every campaign starts a fresh profile and then proceeds only through floors actually unlocked by production guardian settlement. Baseline group sequential_campaign carries persistent loadout, armory, shelter, research and resources but makes no between-floor purchases. Paired group sequential_campaign_meta uses production BaseSystem.try_research, BaseSystem.try_upgrade and GameState.upgrade_armory_item to invest affordable resources before floor 1 and after each cleared floor into combat research, shelter attack/defence and equipped gear; it does not assign hero stats directly. Both groups equip only items that improve production item_power, use real route/combat/event/perk/loot/placement/settlement handlers, place only legal tiles and choose available event options. No run forces hero/enemy stats, rewards or unlocks. Defeat is a valid outcome. These are scripted policy observations, not human playtests or an automatic balance verdict."
		},
		"runs": _runs,
		"failures": _failures
	}
	var absolute_report_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_report_path.get_base_dir())
	var output_file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if output_file == null:
		printerr("Could not write Stage72 sequential campaign capture: ", OUTPUT_PATH)
		get_tree().quit(1)
		return
	output_file.store_string(JSON.stringify(report, "\t") + "\n")
	output_file.close()
	if _failures.is_empty() and not _runs.is_empty():
		print("STAGE72 SEQUENTIAL CAMPAIGN CAPTURE COMPLETED: %d floor observations across %d fresh-profile campaigns." % [_runs.size(), _campaign_results.size()])
		print("Campaign reach and defeats are outcomes, not harness failures; locked floors are never forced open.")
		get_tree().quit(0)
	else:
		printerr("STAGE72 SEQUENTIAL CAMPAIGN CAPTURE FAILED: %d observations; %s" % [_runs.size(), str(_failures)])
		get_tree().quit(1)

func _capture_campaign(seed_value: int, capture_group: String) -> void:
	# Reset exactly once per campaign. Between floors all durable settlements remain intact.
	GameState.reset_progress()
	await get_tree().process_frame
	var investment_for_floor: Dictionary = {}
	if capture_group == "sequential_campaign_meta":
		investment_for_floor = _invest_between_floors()
	var rows_before: int = _runs.size()
	var furthest_floor: int = 0
	var final_floor_cleared: bool = false
	for floor_number in FLOOR_NUMBERS:
		if int(GameState.highest_unlocked_floor) < floor_number:
			break
		var armory_equips_before_floor: int = _equip_better_armory_items()
		var starting_loadout_count: int = _count_equipped_items()
		var starting_armory_count: int = GameState.armory.size()
		var row: Dictionary = await _capture_floor(seed_value, floor_number, armory_equips_before_floor, starting_loadout_count, starting_armory_count, capture_group, investment_for_floor)
		if row.is_empty():
			_failures.append("Campaign seed %d group %s floor %d failed to produce a valid settled run." % [seed_value, capture_group, floor_number])
			break
		_runs.append(row)
		furthest_floor = floor_number
		final_floor_cleared = bool(row.get("floor_cleared", false))
		print("CAPTURED: group=%s campaign_seed=%d floor=%d name=%s outcome=%s cleared=%s loops=%d bosses=%d victories=%d autoequips=%d armory_equips=%d placements=%d building_upgrades=%d researches=%d item_upgrades=%d" % [
			capture_group, seed_value, floor_number, str(row.get("floor_name", "")), str(row.get("outcome", "unknown")),
			str(row.get("floor_cleared", false)), int(row.get("loops", 0)),
			int(row.get("bosses_defeated", 0)), int(row.get("victories", 0)),
			int(row.get("capture_auto_equips", 0)), int(row.get("capture_armory_equips_before_floor", 0)),
			int(row.get("capture_strategic_placements", 0)),
			int(row.get("capture_building_upgrades_before_floor", 0)),
			int(row.get("capture_research_unlocks_before_floor", 0)),
			int(row.get("capture_item_upgrades_before_floor", 0))
		])
		if not final_floor_cleared:
			break
		if floor_number < ContentRegistry.FLOOR_COUNT and int(GameState.highest_unlocked_floor) < floor_number + 1:
			_failures.append("Campaign seed %d group %s cleared floor %d but durable progression did not unlock floor %d." % [seed_value, capture_group, floor_number, floor_number + 1])
			break
		if capture_group == "sequential_campaign_meta" and floor_number < ContentRegistry.FLOOR_COUNT:
			investment_for_floor = _invest_between_floors()
	var rows_completed: int = _runs.size() - rows_before
	_campaign_results.append({
		"campaign_seed": seed_value,
		"capture_group": capture_group,
		"floors_reached": rows_completed,
		"furthest_floor": furthest_floor,
		"last_floor_cleared": final_floor_cleared
	})
	if rows_completed == 0:
		_failures.append("Campaign seed %d group %s produced no floor observations." % [seed_value, capture_group])

func _invest_between_floors() -> Dictionary:
	# Invest only through live production transactions. This is a competent resource-spending
	# policy, not free stats or an enemy-side handicap.
	var base = BaseSystemScript.new()
	var inventory = InventorySystemScript.new()
	var result := {
		"building_upgrades": [],
		"research_unlocks": [],
		"item_upgrades": 0,
		"scrap_spent": 0,
		"crystals_spent": 0
	}
	var research_priority: Array[String] = [
		"field_training", "boss_analysis", "event_forecasting", "medical_relay",
		"route_archive", "supply_contracts", "rare_survey", "advanced_salvage", "crystal_study"
	]
	for research_id in research_priority:
		var status: Dictionary = base.get_research_status(research_id)
		if not bool(status.get("available", false)):
			continue
		var research_result: Dictionary = base.try_research(research_id)
		if bool(research_result.get("ok", false)):
			result["research_unlocks"].append(research_id)
			result["scrap_spent"] = int(result["scrap_spent"]) + int(status.get("scrap_cost", 0))
			result["crystals_spent"] = int(result["crystals_spent"]) + int(status.get("crystal_cost", 0))
	# Upgrade currently equipped gear one level at a time across slots when affordable.
	var upgrade_round := 0
	var more_gear_upgrades := true
	while more_gear_upgrades and upgrade_round < 5:
		upgrade_round += 1
		more_gear_upgrades = false
		for slot in ["armor", "shield", "helmet", "weapon", "core", "amulet"]:
			var equipped_value: Variant = GameState.loadout.get(slot, {})
			if typeof(equipped_value) != TYPE_DICTIONARY or equipped_value.is_empty():
				continue
			var item_id := str(equipped_value.get("id", ""))
			if item_id.is_empty():
				continue
			var owned_item: Dictionary = GameState.get_armory_item(item_id)
			if owned_item.is_empty():
				continue
			var upgrade_cost: Dictionary = inventory.get_upgrade_cost(owned_item)
			if not bool(upgrade_cost.get("available", false)):
				continue
			if GameState.scrap < int(upgrade_cost.get("scrap", 0)) or GameState.crystals < int(upgrade_cost.get("crystals", 0)):
				continue
			var upgrade_result: Dictionary = GameState.upgrade_armory_item(item_id)
			if bool(upgrade_result.get("ok", false)):
				more_gear_upgrades = true
				result["item_upgrades"] = int(result["item_upgrades"]) + 1
				result["scrap_spent"] = int(result["scrap_spent"]) + int(upgrade_result.get("scrap_spent", 0))
				result["crystals_spent"] = int(result["crystals_spent"]) + int(upgrade_result.get("crystals_spent", 0))
	# Defence first, then attack. Repeat until neither can be afforded or both are capped.
	var building_progress := true
	var building_guard := 0
	while building_progress and building_guard < 20:
		building_guard += 1
		building_progress = false
		for building_id in ["infirmary", "forge"]:
			var cost: Dictionary = base.get_upgrade_cost(building_id)
			if int(cost.get("level", 0)) >= int(cost.get("max_level", 0)):
				continue
			if GameState.scrap < int(cost.get("scrap", 0)) or GameState.crystals < int(cost.get("crystals", 0)) or GameState.echo_dust < int(cost.get("echo_dust", 0)):
				continue
			var building_result: Dictionary = base.try_upgrade(building_id)
			if bool(building_result.get("ok", false)):
				building_progress = true
				result["building_upgrades"].append({"id": building_id, "level": int(GameState.buildings.get(building_id, 0))})
				result["scrap_spent"] = int(result["scrap_spent"]) + int(cost.get("scrap", 0))
				result["crystals_spent"] = int(result["crystals_spent"]) + int(cost.get("crystals", 0))
	return result

func _capture_floor(campaign_seed: int, floor_number: int, armory_equips_before_floor: int, starting_loadout_count: int, starting_armory_count: int, capture_group: String, investment_summary: Dictionary) -> Dictionary:
	var seed_value: int = campaign_seed + floor_number * 100003
	var manager = ExpeditionManagerScript.new()
	manager.name = "Stage72_%s_Campaign%d_Floor%d" % [capture_group, campaign_seed, floor_number]
	get_tree().root.add_child(manager)
	await get_tree().process_frame
	if not bool(manager.start_run("standard", seed_value, "standard", "none", "standard", floor_number)):
		printerr("FAIL: sequential production start_run rejected group=%s campaign=%d floor=%d unlocked=%d" % [capture_group, campaign_seed, floor_number, int(GameState.highest_unlocked_floor)])
		manager.queue_free()
		await get_tree().process_frame
		return {}
	manager.set_pause(true)
	manager.set_speed(3.0)
	if not _place_one_legal_road_tile(manager):
		_failures.append("Campaign %d floor %d has no legal road placement." % [campaign_seed, floor_number])
		manager.active = false
		manager.queue_free()
		await get_tree().process_frame
		return {}
	if not _place_one_legal_landscape_tile(manager):
		_failures.append("Campaign %d floor %d has no legal landscape placement." % [campaign_seed, floor_number])
		manager.active = false
		manager.queue_free()
		await get_tree().process_frame
		return {}
	manager.set_pause(false)

	var simulation_steps: int = 0
	var auto_equips: int = 0
	var strategic_placements: int = 0
	var case_failed: bool = false
	while bool(manager.active) and simulation_steps < MAX_SIMULATION_STEPS_PER_FLOOR:
		simulation_steps += 1
		if not str(manager.pending_end_outcome).is_empty():
			_failures.append("Campaign %d floor %d stalled after a failed durable settlement." % [campaign_seed, floor_number])
			case_failed = true
			break
		if not manager.pending_event.is_empty():
			var choice_id := _first_available_event_choice(manager)
			if choice_id.is_empty():
				_failures.append("Campaign %d floor %d offered no affordable event choice." % [campaign_seed, floor_number])
				case_failed = true
				break
			var event_result: Dictionary = manager.resolve_event_choice(choice_id)
			if not bool(event_result.get("ok", false)):
				_failures.append("Campaign %d floor %d rejected an available event choice." % [campaign_seed, floor_number])
				case_failed = true
				break
			manager._update_objective_progress()
			continue
		if int(manager.pending_perk_count) > 0:
			var perk_id := _first_offered_perk(manager)
			if perk_id.is_empty() or not bool(manager.choose_perk(perk_id)):
				_failures.append("Campaign %d floor %d had an invalid perk choice." % [campaign_seed, floor_number])
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
			_failures.append("Campaign %d floor %d route failed to advance." % [campaign_seed, floor_number])
			case_failed = true
			break
	if bool(manager.active):
		_failures.append("Campaign %d floor %d exceeded the bounded simulation." % [campaign_seed, floor_number])
		case_failed = true
		manager.active = false
	var summary: Dictionary = GameState.last_summary.duplicate(true)
	manager.queue_free()
	await get_tree().process_frame
	if case_failed or summary.is_empty():
		return {}
	if str(summary.get("outcome", "")) not in ["return", "defeat"]:
		_failures.append("Campaign %d floor %d has unsupported outcome %s." % [campaign_seed, floor_number, str(summary.get("outcome", ""))])
		return {}
	if int(summary.get("floor_number", 0)) != floor_number:
		_failures.append("Campaign %d floor %d summary reports the wrong floor." % [campaign_seed, floor_number])
		return {}
	if int(summary.get("telemetry_schema", 0)) != 1 or str(summary.get("run_id", "")).is_empty():
		_failures.append("Campaign %d floor %d summary lacks durable telemetry." % [campaign_seed, floor_number])
		return {}
	if int(summary.get("road_placements", 0)) < 1 or int(summary.get("world_placements", 0)) < 1:
		_failures.append("Campaign %d floor %d lost placement telemetry." % [campaign_seed, floor_number])
		return {}
	var source_run_id: String = str(summary.get("run_id", ""))
	summary["source_run_id"] = source_run_id
	summary["run_id"] = "qa-stage72-%s-seed%d-floor%02d" % [capture_group, campaign_seed, floor_number]
	summary["capture_kind"] = "automated_engine_run"
	summary["capture_group"] = capture_group
	summary["capture_building_upgrades_before_floor"] = investment_summary.get("building_upgrades", []).size()
	summary["capture_research_unlocks_before_floor"] = investment_summary.get("research_unlocks", []).size()
	summary["capture_item_upgrades_before_floor"] = int(investment_summary.get("item_upgrades", 0))
	summary["capture_investment_scrap_spent_before_floor"] = int(investment_summary.get("scrap_spent", 0))
	summary["capture_investment_crystals_spent_before_floor"] = int(investment_summary.get("crystals_spent", 0))
	summary["capture_buildings_before_floor"] = GameState.buildings.duplicate(true)
	summary["capture_research_before_floor"] = GameState.unlocked_nodes.duplicate(true)
	summary["capture_floor_number"] = floor_number
	summary["capture_seed"] = seed_value
	summary["capture_campaign_seed"] = campaign_seed
	summary["capture_modifier_id"] = "standard"
	summary["capture_contract_id"] = "none"
	summary["capture_armory_equips_before_floor"] = armory_equips_before_floor
	summary["capture_start_loadout_items"] = starting_loadout_count
	summary["capture_start_armory_items"] = starting_armory_count
	summary["capture_auto_equips"] = auto_equips
	summary["capture_strategic_placements"] = strategic_placements
	return summary

func _equip_better_armory_items() -> int:
	var inventory = InventorySystemScript.new()
	var equip_count: int = 0
	var armory_snapshot: Array = GameState.armory.duplicate(true)
	for item_value in armory_snapshot:
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = item_value
		var slot: String = str(candidate.get("slot", ""))
		if not InventorySystemScript.EQUIPMENT_SLOTS.has(slot):
			continue
		var item_id: String = str(candidate.get("id", ""))
		if item_id.is_empty():
			continue
		var current_value: Variant = GameState.loadout.get(slot, {})
		var current_item: Dictionary = current_value if typeof(current_value) == TYPE_DICTIONARY else {}
		var candidate_power: float = inventory.item_power(candidate)
		var current_power: float = inventory.item_power(current_item) if not current_item.is_empty() else -1.0
		if not current_item.is_empty() and candidate_power <= current_power + 0.01:
			continue
		if GameState.equip_item(item_id):
			equip_count += 1
	return equip_count

func _count_equipped_items() -> int:
	var count: int = 0
	for slot_value in GameState.loadout.values():
		if typeof(slot_value) == TYPE_DICTIONARY and not slot_value.is_empty():
			count += 1
	return count

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

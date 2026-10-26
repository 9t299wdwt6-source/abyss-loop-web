extends Node
class_name ExpeditionManager

signal changed
signal run_finished(summary: Dictionary)
signal feedback_requested(kind: String, message: String)

const RouteSystemScript = preload("res://scripts/systems/route_system.gd")
const TileSystemScript = preload("res://scripts/systems/tile_system.gd")
const CombatSystemScript = preload("res://scripts/systems/combat_system.gd")
const EnemySystemScript = preload("res://scripts/systems/enemy_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const ProgressionSystemScript = preload("res://scripts/systems/progression_system.gd")
const ResourceSystemScript = preload("res://scripts/systems/resource_system.gd")
const LootSystemScript = preload("res://scripts/systems/loot_system.gd")
const ProceduralGenerationScript = preload("res://scripts/systems/procedural_generation.gd")
const ExpeditionEventSystemScript = preload("res://scripts/systems/expedition_event_system.gd")
const StatusEffectSystemScript = preload("res://scripts/systems/status_effect_system.gd")
const EQUIPMENT_SLOT_NAMES := InventorySystemScript.SLOT_NAMES
const BACKPACK_CAPACITY := InventorySystemScript.BACKPACK_CAPACITY
const INVENTORY_ORDER_VERSION := 2
const FIELD_CACHE_CAPACITY := 6 # legacy snapshot migration only
var route_system = RouteSystemScript.new()
var tile_system = TileSystemScript.new()
var combat_system = CombatSystemScript.new()
var enemy_system = EnemySystemScript.new()
var inventory_system = InventorySystemScript.new()
var progression_system = ProgressionSystemScript.new()
var resource_system = ResourceSystemScript.new()
var loot_system = LootSystemScript.new()
var expedition_event_system = ExpeditionEventSystemScript.new()
var status_effect_system = StatusEffectSystemScript.new()

var active: bool = false
var paused: bool = false
var speed: float = 1.0
var run_seed: int = 0
var route_geometry_seed: int = 0
# Bounded local measurements for reproducible balance capture; no network telemetry.
var run_elapsed_seconds: float = 0.0
var run_baseline: Dictionary = {}
var floor_number: int = 1
var difficulty_id: String = "standard"
var run_modifier_id: String = "standard"
var expedition_mode_id: String = "standard"
var run_challenge: Dictionary = {}
var run_objective: Dictionary = {}
var run_contract: Dictionary = {}
var route: Array = []
var distance: float = 0.0
var processed_steps: int = 0
var loop_count: int = 0
var danger: float = 1.0
var hero: Dictionary = {}
var run_ledger: Dictionary = {"scrap": 0, "crystals": 0, "victories": 0, "bosses_defeated": 0, "elites_defeated": 0}
var placed_tiles: Dictionary = {}
var world_tiles: Dictionary = {}
# Canonical modern map IDs (`m:col:row`) revealed during this expedition.
# Old snapshots without this mask are migrated to a fully revealed field.
var discovered_world_cells: Dictionary = {}
var tile_hand: Array = []
var bag: Array = []
# The active-run backpack is a newest-first 12-item queue, like Loop Hero.
# Older snapshots may still contain field_cache; restore folds it into the queue.
var field_cache: Array = []
var last_inventory_evicted_item: Dictionary = {}
var equipment: Dictionary = {"weapon": {}, "helmet": {}, "armor": {}, "shield": {}, "amulet": {}, "core": {}}
var enemy: Dictionary = {}
# All active enemies in this encounter. The hero focuses encounter_enemies[0],
# while every living member can attack on its own timer.
var encounter_enemies: Array = []
var combat_cell: int = -1
var combat_timers: Dictionary = {"hero": 0.0, "enemy": 0.0}
var combat_reward_bonus: float = 0.0
var current_tile_spawn_bonus: float = 0.0
var pending_perk_count: int = 0
var pending_perk_choices: Array = []
var pending_event: Dictionary = {}
var last_event_id: String = ""
var event_log: Array = []
var _refresh_accumulator: float = 0.0
var _autosave_elapsed: float = 0.0
var _snapshot_save_failure_notified: bool = false
var pending_end_outcome: String = ""
var run_rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _process(delta: float) -> void:
	if not active:
		return
	# Count game-process seconds (including modal choices/paused decisions, but not
	# time while the game process is closed). Persisted with the active snapshot.
	run_elapsed_seconds += maxf(0.0, delta)
	# Autosave uses real time, so it also runs while the expedition is paused or
	# waiting for an event/perk decision.
	_autosave_elapsed += delta
	if _autosave_elapsed >= float(ContentRegistry.BALANCE.get("autosave_interval_seconds", 2.0)):
		_autosave_elapsed = 0.0
		save_run_snapshot()
	if paused or not pending_event.is_empty():
		return
	var scaled_delta: float = delta * speed
	if not enemy.is_empty():
		_tick_combat(scaled_delta)
	else:
		_tick_route(scaled_delta)
	if active:
		_update_objective_progress()
	_refresh_accumulator += delta
	if _refresh_accumulator >= float(ContentRegistry.BALANCE.get("manager_refresh_interval", 0.16)):
		_refresh_accumulator = 0.0
		changed.emit()

func can_accept_contract(contract_id: String) -> Dictionary:
	if contract_id.is_empty() or contract_id == "none":
		return {"ok": true, "reason": "Экспедиция без дополнительного контракта.", "scrap_cost": 0, "crystal_cost": 0}
	if not ContentRegistry.EXPEDITION_CONTRACTS.has(contract_id):
		return {"ok": false, "reason": "Такой контракт не зарегистрирован."}
	var definition: Dictionary = ContentRegistry.EXPEDITION_CONTRACTS[contract_id]
	var scrap_cost := maxi(0, int(definition.get("scrap_cost", 0)))
	var crystal_cost := maxi(0, int(definition.get("crystal_cost", 0)))
	if GameState.scrap < scrap_cost or GameState.crystals < crystal_cost:
		return {"ok": false, "reason": "Недостаточно ресурсов для контракта: требуется %d материалов и %d редких ресурсов." % [scrap_cost, crystal_cost], "scrap_cost": scrap_cost, "crystal_cost": crystal_cost}
	if str(definition.get("kind", "")) not in ["world_tiles", "victories", "events", "bosses", "scrap"] or int(definition.get("target", 0)) < 1 or int(definition.get("deadline_loops", 0)) < 1:
		return {"ok": false, "reason": "Условия контракта некорректны."}
	return {"ok": true, "reason": "Контракт доступен.", "scrap_cost": scrap_cost, "crystal_cost": crystal_cost}

func start_run(requested_difficulty_id: String = "standard", requested_seed: int = 0, requested_modifier_id: String = "standard", requested_contract_id: String = "none", requested_mode_id: String = "standard", requested_floor_number: int = 1) -> bool:
	if active:
		return false
	floor_number = clampi(requested_floor_number, 1, ContentRegistry.FLOOR_COUNT)
	if floor_number > int(GameState.highest_unlocked_floor):
		return false
	pending_end_outcome = ""
	_snapshot_save_failure_notified = false
	var contract_acceptance := can_accept_contract(requested_contract_id)
	if not bool(contract_acceptance.get("ok", false)):
		return false
	difficulty_id = "standard" # Legacy save field retained; floors govern campaign pressure.
	run_modifier_id = requested_modifier_id if ContentRegistry.RUN_MODIFIERS.has(requested_modifier_id) else "standard"
	expedition_mode_id = "standard" # The eight-floor campaign replaces the old free/12-loop selector.
	var modifier_definition: Dictionary = ContentRegistry.RUN_MODIFIERS.get(run_modifier_id, ContentRegistry.RUN_MODIFIERS["standard"])
	var challenge_value: Variant = modifier_definition.get("challenge", {})
	run_challenge = challenge_value.duplicate(true) if typeof(challenge_value) == TYPE_DICTIONARY else {}
	if not run_challenge.is_empty():
		run_challenge["progress"] = 0
		run_challenge["completed"] = false
		run_challenge["rewarded"] = false
	run_contract.clear()
	if requested_contract_id != "none" and ContentRegistry.EXPEDITION_CONTRACTS.has(requested_contract_id):
		run_contract = ContentRegistry.EXPEDITION_CONTRACTS[requested_contract_id].duplicate(true)
		run_contract["id"] = requested_contract_id
		run_contract["progress"] = 0
		run_contract["completed"] = false
		run_contract["rewarded"] = false
		run_contract["failed"] = false
		run_contract["failure_reason"] = ""
		run_contract["cost_paid"] = true # committed atomically with the first snapshot below
	run_seed = ProceduralGenerationScript.create_seed() if requested_seed <= 0 else requested_seed
	# Each floor derives its own deterministic map and RNG stream from the chosen seed.
	# The saved base seed remains unchanged so a floor can be reproduced exactly.
	var floor_seed: int = _get_floor_seed(run_seed, floor_number)
	route_geometry_seed = floor_seed
	run_elapsed_seconds = 0.0
	run_baseline.clear()
	run_rng = RandomNumberGenerator.new()
	run_rng.seed = floor_seed
	route = route_system.create_route(floor_seed, int(ContentRegistry.BALANCE.route_cells))
	run_objective = _choose_objective_for_seed(floor_seed, run_modifier_id)
	distance = 0.0
	processed_steps = 0
	loop_count = 0
	var floor_config: Dictionary = get_floor_config()
	danger = maxf(1.0, float(floor_config.get("starting_danger", 1.0)))
	paused = false
	speed = 1.0
	run_ledger = {"scrap": 0, "crystals": 0, "victories": 0, "bosses_defeated": 0, "elites_defeated": 0, "events_resolved": 0, "event_history": [], "event_flags": {}, "trophy_drops": _empty_trophy_counts(), "echo_item_charges": 0, "pending_item_rarity_bonus": 0.0, "pending_item_drop_bonus": 0.0, "inventory_ejections": [], "inventory_ejections_count": 0, "inventory_ejections_dust": 0, "last_tile_exchange_loop": -1, "floor_number": floor_number, "floor_boss_defeated": false, "floor_cleared": false}
	placed_tiles.clear()
	world_tiles.clear()
	discovered_world_cells.clear()
	_reveal_world_cells_near_route_index(0)
	tile_hand.clear()
	bag.clear()
	field_cache.clear()
	equipment = GameState.loadout.duplicate(true)
	for slot_value in InventorySystemScript.EQUIPMENT_SLOTS:
		var slot := str(slot_value)
		if typeof(equipment.get(slot, {})) != TYPE_DICTIONARY:
			equipment[slot] = {}
	enemy.clear()
	encounter_enemies.clear()
	combat_cell = -1
	combat_timers = {"hero": 0.0, "enemy": 0.0}
	combat_reward_bonus = 0.0
	current_tile_spawn_bonus = 0.0
	pending_perk_count = 0
	pending_perk_choices.clear()
	pending_event.clear()
	last_event_id = ""
	event_log.clear()
	hero = {
		"hp": int(ContentRegistry.BALANCE.base_hp) + GameState.get_health_bonus(),
		"max_hp": int(ContentRegistry.BALANCE.base_hp) + GameState.get_health_bonus(),
		"base_hp": int(ContentRegistry.BALANCE.base_hp) + GameState.get_health_bonus(),
		"base_attack": int(ContentRegistry.BALANCE.base_attack) + GameState.get_attack_bonus() + int(GameState.get_unlock_effect("field_training_attack")),
		"base_defense": int(ContentRegistry.BALANCE.base_defense) + GameState.get_defense_bonus(),
		"attack": int(ContentRegistry.BALANCE.base_attack) + GameState.get_attack_bonus() + int(GameState.get_unlock_effect("field_training_attack")),
		"defense": int(ContentRegistry.BALANCE.base_defense) + GameState.get_defense_bonus(),
		"attack_speed": 1.0, "crit": 0.05,
		"level": 1, "xp": 0, "xp_next": 16,
		"attack_bonus": 0, "hp_bonus": 0, "defense_bonus": 0, "speed_bonus": 0.0, "crit_bonus": 0.0,
		"perk_counts": {}, "perk_kill_heal_bonus": 0, "perk_tile_scrap_bonus": 0,
		"perk_event_heal_bonus": 0, "perk_reward_bonus": 0.0, "perk_tile_spawn_bonus": 0.0,
		"combat_debuff": {"speed_penalty": 0.0, "time_remaining": 0.0}, "status_effects": []
	}
	_sync_hero_stats()
	var starting_tile_count := get_tile_hand_limit()
	if GameState.runs_completed == 0 and run_modifier_id == "standard":
		starting_tile_count = maxi(starting_tile_count, int(ContentRegistry.BALANCE.get("first_run_min_starting_tiles", 3)))
	starting_tile_count = mini(starting_tile_count, 6)
	for i in range(starting_tile_count):
		tile_hand.append(tile_system.draw_tile(_rng_for_draw(), false))
	run_baseline = _build_run_baseline()
	active = true
	_log("Начат этаж %d/8: %s — %s. Seed %d." % [floor_number, get_floor_name(), str(floor_config.get("biome", "Бездонье")), run_seed])
	_log("Условия маршрута: %s." % str(modifier_definition.get("name", "Обычная экспедиция")))
	if expedition_mode_id == "long_expedition":
		_log("Цель длинной экспедиции: 12 циклов и четыре победы над боссами, включая финального босса цикла 12. Риск и награды ограничены мягким пределом.")
	if not run_challenge.is_empty():
		_log("Испытание: %s. Награда: +%d материалов, +%d редких ресурсов." % [str(run_challenge.get("name", "Испытание")), int(run_challenge.get("scrap_reward", 0)), int(run_challenge.get("crystal_reward", 0))])
	if not run_contract.is_empty():
		_log("Контракт принят: %s. Срок — до конца цикла %d." % [str(run_contract.get("name", "Контракт")), int(run_contract.get("deadline_loops", 1))])
		_log("Оплата контракта: %d материалов и %d редких ресурсов." % [int(run_contract.get("scrap_cost", 0)), int(run_contract.get("crystal_cost", 0))])
	_log("Удерживайте риск под контролем: после каждого цикла растут сложность и награда.")
	if not GameState.commit_expedition_start(export_run_state(), int(run_contract.get("scrap_cost", 0)), int(run_contract.get("crystal_cost", 0))):
		active = false
		run_contract.clear()
		feedback_requested.emit("error", "Не удалось безопасно сохранить начало экспедиции; плата за контракт не списана.")
		changed.emit()
		return false
	changed.emit()
	return true

func get_tile_hand_limit() -> int:
	var modifier: Dictionary = ContentRegistry.RUN_MODIFIERS.get(run_modifier_id, ContentRegistry.RUN_MODIFIERS["standard"])
	return maxi(1, int(ContentRegistry.BALANCE.max_tile_hand) + int(modifier.get("starting_tile_delta", 0)) + int(GameState.get_unlock_effect("starting_tiles")))

func get_floor_config() -> Dictionary:
	var safe_floor: int = clampi(floor_number, 1, ContentRegistry.FLOOR_COUNT)
	return ContentRegistry.FLOOR_DEFS[safe_floor - 1].duplicate(true)

func get_floor_name() -> String:
	return str(get_floor_config().get("name", "Этаж %d" % floor_number))

func _get_floor_seed(base_seed: int, requested_floor: int) -> int:
	var safe_floor: int = clampi(requested_floor, 1, ContentRegistry.FLOOR_COUNT)
	var value: int = posmod(base_seed + safe_floor * 104729, 2147483647)
	return maxi(1, value)

func get_run_modifier() -> Dictionary:
	return ContentRegistry.RUN_MODIFIERS.get(run_modifier_id, ContentRegistry.RUN_MODIFIERS["standard"]).duplicate(true)

func get_expedition_mode() -> Dictionary:
	return ContentRegistry.EXPEDITION_MODES.get(expedition_mode_id, ContentRegistry.EXPEDITION_MODES["standard"]).duplicate(true)

func get_expedition_goal_progress() -> Dictionary:
	var mode: Dictionary = get_expedition_mode()
	var target_loops := maxi(0, int(mode.get("goal_loops", 0)))
	var target_bosses := maxi(0, int(mode.get("goal_bosses", 0)))
	return {
		"mode_id": expedition_mode_id,
		"name": str(mode.get("name", "Обычная экспедиция")),
		"target_loops": target_loops,
		"loops_completed": loop_count,
		"target_bosses": target_bosses,
		"bosses_defeated": int(run_ledger.get("bosses_defeated", 0)),
		"completed": target_loops > 0 and loop_count >= target_loops and int(run_ledger.get("bosses_defeated", 0)) >= target_bosses
	}

func _effective_scaling_loop(value: int) -> int:
	if expedition_mode_id != "long_expedition":
		return maxi(0, value)
	var mode: Dictionary = get_expedition_mode()
	return mini(maxi(0, value), maxi(0, int(mode.get("max_scaling_loop", 12))))

func _record_long_expedition_checkpoint() -> void:
	if expedition_mode_id != "long_expedition":
		return
	var target_loops := maxi(1, int(get_expedition_mode().get("goal_loops", 12)))
	var interval := maxi(1, int(ContentRegistry.BALANCE.get("boss_loop_interval", 3)))
	if loop_count % interval != 0 and loop_count != target_loops:
		return
	var checkpoint_value: Variant = run_ledger.get("long_run_checkpoints", [])
	var checkpoints: Array = checkpoint_value.duplicate(true) if typeof(checkpoint_value) == TYPE_ARRAY else []
	for previous_value in checkpoints:
		if typeof(previous_value) == TYPE_DICTIONARY and int(previous_value.get("loop", -1)) == loop_count:
			return
	checkpoints.append({
			"loop": loop_count,
			"hp": int(hero.get("hp", 0)),
			"max_hp": int(hero.get("max_hp", 1)),
			"danger": snappedf(danger, 0.01),
			"bosses_defeated": int(run_ledger.get("bosses_defeated", 0)),
			"scrap": int(run_ledger.get("scrap", 0)),
			"crystals": int(run_ledger.get("crystals", 0))
		})
	while checkpoints.size() > 8:
		checkpoints.pop_front()
	run_ledger["long_run_checkpoints"] = checkpoints
	_log("Контрольная точка %d/%d сохранена: здоровье %d/%d, боссов побеждено %d." % [loop_count, target_loops, int(hero.get("hp", 0)), int(hero.get("max_hp", 1)), int(run_ledger.get("bosses_defeated", 0))])

func _clamp_long_mode_danger(value: float) -> float:
	var mode: Dictionary = get_expedition_mode()
	if expedition_mode_id != "long_expedition":
		return value
	return clampf(value, 1.0, maxf(1.0, float(mode.get("max_danger", 6.0))))

func _maybe_finish_long_expedition() -> void:
	if not active or expedition_mode_id != "long_expedition":
		return
	if pending_perk_count > 0 or not enemy.is_empty() or not pending_event.is_empty():
		return
	var goal: Dictionary = get_expedition_goal_progress()
	if loop_count < int(goal.get("target_loops", 12)):
		return
	if int(run_ledger.get("bosses_defeated", 0)) < int(goal.get("target_bosses", 4)):
		return
	run_ledger["endgame_completed"] = true
	run_ledger["endgame_completed_loop"] = loop_count
	_log("ФИНАЛ ДЛИННОЙ ЭКСПЕДИЦИИ: 12 циклов пройдены, финальный босс побеждён. Вся добыча сохранена.")
	_finish_run("return")

func get_route_shape_id() -> String:
	return str(get_run_modifier().get("route_shape", "classic_ring"))

func get_route_geometry_seed() -> int:
	return route_geometry_seed

func _get_modifier_chance_delta() -> float:
	return float(get_run_modifier().get("encounter_chance_delta", 0.0))

func _objective_is_feasible_for_run(definition: Dictionary, requested_modifier_id: String) -> bool:
	if not ContentRegistry.RUN_MODIFIERS.has(requested_modifier_id):
		return false
	var kind := str(definition.get("kind", ""))
	var target := int(definition.get("target", 0))
	if target < 1 or target > 1000 or str(definition.get("name", "")).strip_edges().is_empty() or str(definition.get("description", "")).strip_edges().is_empty():
		return false
	match kind:
		"loops":
			return int(ContentRegistry.BALANCE.get("route_cells", 0)) >= 4
		"bosses":
			return not ContentRegistry.BOSSES.is_empty() and int(ContentRegistry.BALANCE.get("boss_loop_interval", 0)) > 0
		"victories":
			return not ContentRegistry.ENEMIES.is_empty()
		"events":
			return not ContentRegistry.EXPEDITION_EVENTS.is_empty()
		"scrap":
			return not ContentRegistry.TILE_DEFS.is_empty() and float(ContentRegistry.BALANCE.get("route_reward_scrap", 0)) > 0.0
	return false

func preview_objective_for_seed(seed_value: int, requested_modifier_id: String = "standard") -> Dictionary:
	return _choose_objective_for_seed(seed_value, requested_modifier_id)

func _choose_objective_for_seed(seed_value: int, requested_modifier_id: String = "standard") -> Dictionary:
	var keys: Array[String] = []
	for key_value in ContentRegistry.EXPEDITION_OBJECTIVES.keys():
		var candidate_id := str(key_value)
		var definition_value: Variant = ContentRegistry.EXPEDITION_OBJECTIVES.get(candidate_id, {})
		if typeof(definition_value) == TYPE_DICTIONARY and _objective_is_feasible_for_run(definition_value, requested_modifier_id):
			keys.append(candidate_id)
	if keys.is_empty():
		return {}
	var objective_rng := RandomNumberGenerator.new()
	objective_rng.seed = int(seed_value) ^ 0x51A7C3
	var objective_id := keys[objective_rng.randi_range(0, keys.size() - 1)]
	var definition: Dictionary = ContentRegistry.EXPEDITION_OBJECTIVES.get(objective_id, {})
	var objective: Dictionary = definition.duplicate(true)
	objective["id"] = objective_id
	objective["completed"] = false
	objective["rewarded"] = false
	objective["progress"] = 0
	return objective

func _get_contract_progress() -> int:
	if run_contract.is_empty():
		return 0
	match str(run_contract.get("kind", "")):
		"world_tiles": return world_tiles.size()
		"victories": return int(run_ledger.get("victories", 0))
		"events": return int(run_ledger.get("events_resolved", 0))
		"bosses": return int(run_ledger.get("bosses_defeated", 0))
		"scrap": return int(run_ledger.get("scrap", 0))
	return 0

func _update_contract_progress() -> void:
	if run_contract.is_empty() or bool(run_contract.get("failed", false)):
		return
	var progress := _get_contract_progress()
	run_contract["progress"] = progress
	var target := maxi(1, int(run_contract.get("target", 1)))
	if not bool(run_contract.get("completed", false)) and progress >= target:
		run_contract["completed"] = true
		if not bool(run_contract.get("rewarded", false)):
			# Set flags before adding the payout; snapshots are saved after the whole synchronous operation.
			run_contract["rewarded"] = true
			var scrap_reward := maxi(0, int(run_contract.get("scrap_reward", 0)))
			var crystal_reward := maxi(0, int(run_contract.get("crystal_reward", 0)))
			resource_system.add(run_ledger, "scrap", scrap_reward)
			resource_system.add(run_ledger, "crystals", crystal_reward)
			_log("КОНТРАКТ ВЫПОЛНЕН: %s. +%d материалов и +%d редких ресурсов." % [str(run_contract.get("name", "Контракт")), scrap_reward, crystal_reward])
			_request_feedback("objective", str(run_contract.get("name", "Контракт выполнен")))
			save_run_snapshot()
		return
	if not bool(run_contract.get("completed", false)) and loop_count > maxi(0, int(run_contract.get("deadline_loops", 1))):
		run_contract["failed"] = true
		run_contract["failure_reason"] = "Срок истёк в цикле %d." % loop_count
		_log("КОНТРАКТ ПРОВАЛЕН: %s. %s" % [str(run_contract.get("name", "Контракт")), str(run_contract.get("failure_reason", "Срок истёк."))])
		save_run_snapshot()

func _get_objective_progress() -> int:
	var objective_kind := str(run_objective.get("kind", ""))
	match objective_kind:
		"loops": return int(loop_count)
		"bosses": return int(run_ledger.get("bosses_defeated", 0))
		"victories": return int(run_ledger.get("victories", 0))
		"events": return int(run_ledger.get("events_resolved", 0))
		"scrap": return int(run_ledger.get("scrap", 0))
	return 0

func _get_challenge_progress() -> int:
	if run_challenge.is_empty():
		return 0
	match str(run_challenge.get("kind", "")):
		"loops": return loop_count
		"bosses": return int(run_ledger.get("bosses_defeated", 0))
		"victories": return int(run_ledger.get("victories", 0))
		"events": return int(run_ledger.get("events_resolved", 0))
		"scrap": return int(run_ledger.get("scrap", 0))
	return 0

func _update_challenge_progress() -> void:
	if run_challenge.is_empty():
		return
	var progress := _get_challenge_progress()
	run_challenge["progress"] = progress
	if bool(run_challenge.get("completed", false)) or progress < maxi(1, int(run_challenge.get("target", 1))):
		return
	run_challenge["completed"] = true
	if not bool(run_challenge.get("rewarded", false)):
		run_challenge["rewarded"] = true
		var scrap_reward := maxi(0, int(run_challenge.get("scrap_reward", 0)))
		var crystal_reward := maxi(0, int(run_challenge.get("crystal_reward", 0)))
		resource_system.add(run_ledger, "scrap", scrap_reward)
		resource_system.add(run_ledger, "crystals", crystal_reward)
		_log("ИСПЫТАНИЕ ВЫПОЛНЕНО: %s. +%d материалов и +%d редких ресурсов." % [str(run_challenge.get("name", "Испытание")), scrap_reward, crystal_reward])
		_request_feedback("objective", str(run_challenge.get("name", "Испытание выполнено")))
		save_run_snapshot()

func _update_objective_progress() -> void:
	_update_challenge_progress()
	_update_contract_progress()
	if run_objective.is_empty():
		return
	var progress := _get_objective_progress()
	run_objective["progress"] = progress
	if bool(run_objective.get("completed", false)) or progress < maxi(1, int(run_objective.get("target", 1))):
		return
	run_objective["completed"] = true
	if not bool(run_objective.get("rewarded", false)):
		var scrap_reward := maxi(0, int(run_objective.get("scrap_reward", 0)))
		var crystal_reward := maxi(0, int(run_objective.get("crystal_reward", 0)))
		resource_system.add(run_ledger, "scrap", scrap_reward)
		resource_system.add(run_ledger, "crystals", crystal_reward)
		run_objective["rewarded"] = true
		_log("ЦЕЛЬ ВЫПОЛНЕНА: %s. Награда +%d материалов и +%d редких ресурсов." % [str(run_objective.get("name", "Цель")), scrap_reward, crystal_reward])
		_request_feedback("objective", str(run_objective.get("name", "Цель выполнена")))
	save_run_snapshot()
	changed.emit()

func get_return_forecast() -> Dictionary:
	var active_difficulty: Dictionary = ContentRegistry.DIFFICULTY_PRESETS.get(difficulty_id, ContentRegistry.DIFFICULTY_PRESETS["standard"])
	var modifier: Dictionary = get_run_modifier()
	var next_loop := loop_count + 1
	var floor_config: Dictionary = get_floor_config()
	var projected_danger := minf(float(ContentRegistry.BALANCE.get("max_danger", 6.0)), danger + float(ContentRegistry.BALANCE.get("loop_danger_growth", 0.18)) * float(floor_config.get("danger_growth_multiplier", 1.0)) * float(active_difficulty.get("danger_growth_multiplier", 1.0)) * float(modifier.get("danger_growth_multiplier", 1.0)))
	var projected_scrap_base := int(ContentRegistry.BALANCE.get("route_reward_scrap", 4)) + GameState.get_effective_loop_scrap_bonus()
	var projected_scrap := int(round(float(projected_scrap_base) * float(floor_config.get("reward_multiplier", 1.0)) * float(active_difficulty.get("reward_multiplier", 1.0)) * float(modifier.get("reward_multiplier", 1.0))))
	var crystal_interval := maxi(1, int(ContentRegistry.BALANCE.get("loop_crystal_interval", 2)))
	var projected_crystals := 1 if next_loop % crystal_interval == 0 else 0
	var chance := clampf(float(ContentRegistry.BALANCE.get("encounter_chance_base", 0.22)) + float(next_loop) * float(ContentRegistry.BALANCE.get("encounter_chance_per_loop", 0.04)) + float(floor_config.get("encounter_chance_delta", 0.0)) + float(active_difficulty.get("encounter_chance_delta", 0.0)) + _get_modifier_chance_delta(), float(ContentRegistry.BALANCE.get("encounter_chance_min", 0.08)), float(ContentRegistry.BALANCE.get("encounter_chance_max", 0.96)))
	var boss_interval := maxi(1, int(get_floor_config().get("boss_loop", ContentRegistry.BALANCE.get("boss_loop_interval", 3))))
	return {
		"scrap": int(run_ledger.get("scrap", 0)),
		"crystals": int(run_ledger.get("crystals", 0)),
		"defeat_scrap": int(floor(float(run_ledger.get("scrap", 0)) * float(active_difficulty.get("defeat_keep_ratio", ContentRegistry.BALANCE.get("defeat_keep_ratio", 0.4))))),
		"defeat_crystals": int(floor(float(run_ledger.get("crystals", 0)) * float(active_difficulty.get("defeat_keep_ratio", ContentRegistry.BALANCE.get("defeat_keep_ratio", 0.4))))),
		"next_loop": next_loop,
		"next_scrap": projected_scrap,
		"next_crystals": projected_crystals,
		"danger_now": danger,
		"danger_next": projected_danger,
		"encounter_chance": chance,
		"boss_next": next_loop % boss_interval == 0,
		"floor_number": floor_number,
		"floor_name": get_floor_name(),
		"difficulty_name": get_floor_name()
	}

func _empty_trophy_counts() -> Dictionary:
	return {"spore_pollen": 0, "prism_fragment": 0, "bone_fragment": 0, "echo_residue": 0}

func _normalize_trophy_counts(value: Variant) -> Dictionary:
	var result := _empty_trophy_counts()
	if typeof(value) != TYPE_DICTIONARY:
		return result
	var source: Dictionary = value
	for trophy_id in result.keys():
		result[trophy_id] = clampi(int(source.get(trophy_id, 0)), 0, 1000000)
	return result

func export_run_state() -> Dictionary:
	if not active or route.is_empty() or hero.is_empty():
		return {}
	return {
		"snapshot_version": 4,
		"telemetry_schema": 1 if not run_baseline.is_empty() else 0,
		"run_elapsed_seconds": maxf(0.0, run_elapsed_seconds),
		"run_baseline": run_baseline.duplicate(true),
		"status_schema": 1,
		"field_schema": 3,
		"world_tiles": world_tiles.duplicate(true),
		"discovered_world_cells": discovered_world_cells.duplicate(true),
		"active": true,
		"run_seed": run_seed,
		"route_geometry_seed": route_geometry_seed,
		"floor_number": floor_number,
		"difficulty_id": difficulty_id,
		"run_modifier_id": run_modifier_id,
		"expedition_mode_id": expedition_mode_id,
		"run_challenge": run_challenge.duplicate(true),
		"run_objective": run_objective.duplicate(true),
		"run_contract": run_contract.duplicate(true),
		"rng_state": run_rng.state,
		"speed": speed,
		"distance": distance,
		"processed_steps": processed_steps,
		"loop_count": loop_count,
		"danger": danger,
		"route": route.duplicate(true),
		"hero": hero.duplicate(true),
		"run_ledger": run_ledger.duplicate(true),
		"placed_tiles": placed_tiles.duplicate(true),
		"tile_hand": tile_hand.duplicate(true),
		"bag": bag.duplicate(true),
		"inventory_order_version": INVENTORY_ORDER_VERSION,
		"field_cache": [],
		"equipment": equipment.duplicate(true),
		"enemy": enemy.duplicate(true),
		"encounter_enemies": encounter_enemies.duplicate(true),
		"combat_cell": combat_cell,
		"combat_timers": combat_timers.duplicate(true),
		"combat_reward_bonus": combat_reward_bonus,
		"current_tile_spawn_bonus": current_tile_spawn_bonus,
		"pending_perk_count": pending_perk_count,
		"pending_perk_choices": pending_perk_choices.duplicate(true),
		"pending_event": pending_event.duplicate(true),
		"last_event_id": last_event_id,
		"event_log": event_log.duplicate(true)
	}

func save_run_snapshot() -> bool:
	if not active:
		return false
	var snapshot := export_run_state()
	if snapshot.is_empty():
		return false
	var persisted: bool = GameState.set_saved_expedition(snapshot)
	if not persisted:
		if not _snapshot_save_failure_notified:
			_snapshot_save_failure_notified = true
			_log("ОШИБКА СОХРАНЕНИЯ: последняя контрольная точка не обновлена; проверьте свободное место и доступ к папке данных.")
			_request_feedback("error", "Не удалось сохранить экспедицию. Последняя подтверждённая контрольная точка сохранена.")
		return false
	_snapshot_save_failure_notified = false
	return true

func restore_saved_run() -> bool:
	if active or not GameState.has_saved_expedition():
		return false
	var snapshot: Dictionary = GameState.saved_expedition.duplicate(true)
	if not [1, 2, 3, 4].has(int(snapshot.get("snapshot_version", 1))):
		return false
	snapshot = SaveSystem.migrate_expedition_snapshot(snapshot)
	if snapshot.is_empty():
		return false
	var route_value: Variant = snapshot.get("route", [])
	var hero_value: Variant = snapshot.get("hero", {})
	if typeof(route_value) != TYPE_ARRAY or typeof(hero_value) != TYPE_DICTIONARY:
		return false
	var saved_route: Array = route_value
	var saved_hero: Dictionary = hero_value
	if saved_route.is_empty() or saved_hero.is_empty():
		return false
	for route_cell_value in saved_route:
		if typeof(route_cell_value) != TYPE_DICTIONARY:
			return false
	run_seed = int(snapshot.get("run_seed", ProceduralGenerationScript.create_seed()))
	floor_number = clampi(int(snapshot.get("floor_number", 1)), 1, ContentRegistry.FLOOR_COUNT)
	route_geometry_seed = maxi(0, int(snapshot.get("route_geometry_seed", 0)))
	run_elapsed_seconds = maxf(0.0, float(snapshot.get("run_elapsed_seconds", 0.0)))
	var baseline_value: Variant = snapshot.get("run_baseline", {})
	run_baseline = baseline_value.duplicate(true) if typeof(baseline_value) == TYPE_DICTIONARY else {}
	difficulty_id = "standard" # Legacy snapshots migrate to the single floor-progression rules.
	run_modifier_id = str(snapshot.get("run_modifier_id", "standard"))
	if not ContentRegistry.RUN_MODIFIERS.has(run_modifier_id):
		run_modifier_id = "standard"
	expedition_mode_id = str(snapshot.get("expedition_mode_id", "standard"))
	if not ContentRegistry.EXPEDITION_MODES.has(expedition_mode_id):
		expedition_mode_id = "standard"
	var modifier_definition: Dictionary = get_run_modifier()
	var saved_challenge_value: Variant = snapshot.get("run_challenge", modifier_definition.get("challenge", {}))
	run_challenge = saved_challenge_value.duplicate(true) if typeof(saved_challenge_value) == TYPE_DICTIONARY else {}
	if not run_challenge.is_empty():
		run_challenge["progress"] = maxi(0, int(run_challenge.get("progress", 0)))
		run_challenge["completed"] = bool(run_challenge.get("completed", false))
		run_challenge["rewarded"] = bool(run_challenge.get("rewarded", false))
	var objective_value: Variant = snapshot.get("run_objective", {})
	run_objective = objective_value.duplicate(true) if typeof(objective_value) == TYPE_DICTIONARY else {}
	if run_objective.is_empty():
		run_objective = _choose_objective_for_seed(run_seed, run_modifier_id)
	var contract_value: Variant = snapshot.get("run_contract", {})
	run_contract = contract_value.duplicate(true) if typeof(contract_value) == TYPE_DICTIONARY else {}
	if not run_contract.is_empty():
		run_contract["progress"] = maxi(0, int(run_contract.get("progress", 0)))
		run_contract["completed"] = bool(run_contract.get("completed", false))
		run_contract["rewarded"] = bool(run_contract.get("rewarded", false))
		run_contract["failed"] = bool(run_contract.get("failed", false))
		run_contract["cost_paid"] = bool(run_contract.get("cost_paid", true))
	run_rng = RandomNumberGenerator.new()
	run_rng.seed = run_seed
	run_rng.state = int(snapshot.get("rng_state", run_rng.state))
	route = route_system.bind_closed_loop(saved_route)
	hero = saved_hero.duplicate(true)
	status_effect_system.normalize_legacy_entity(hero)
	var ledger_value: Variant = snapshot.get("run_ledger", {})
	run_ledger = ledger_value.duplicate(true) if typeof(ledger_value) == TYPE_DICTIONARY else {}
	for ledger_key in ["scrap", "crystals", "victories", "bosses_defeated", "elites_defeated", "events_resolved"]:
		run_ledger[ledger_key] = maxi(0, int(run_ledger.get(ledger_key, 0)))
	run_ledger["trophy_drops"] = _normalize_trophy_counts(run_ledger.get("trophy_drops", {}))
	run_ledger["echo_item_charges"] = clampi(int(run_ledger.get("echo_item_charges", 0)), 0, 4)
	run_ledger["pending_item_rarity_bonus"] = clampf(float(run_ledger.get("pending_item_rarity_bonus", 0.0)), 0.0, 0.18)
	run_ledger["pending_item_drop_bonus"] = clampf(float(run_ledger.get("pending_item_drop_bonus", 0.0)), 0.0, 0.30)
	var inventory_ejections_value: Variant = run_ledger.get("inventory_ejections", [])
	var restored_inventory_ejections: Array = inventory_ejections_value.duplicate(true) if typeof(inventory_ejections_value) == TYPE_ARRAY else []
	var normalized_inventory_ejections: Array = []
	var seen_ejection_ids: Dictionary = {}
	for ejected_item_value in restored_inventory_ejections:
		if typeof(ejected_item_value) != TYPE_DICTIONARY or not inventory_system.can_equip_item(ejected_item_value):
			continue
		var ejected_item: Dictionary = ejected_item_value
		var ejected_id := str(ejected_item.get("id", ""))
		if ejected_id.is_empty() or seen_ejection_ids.has(ejected_id):
			continue
		seen_ejection_ids[ejected_id] = true
		normalized_inventory_ejections.append(ejected_item.duplicate(true))
	while normalized_inventory_ejections.size() > 100:
		normalized_inventory_ejections.pop_front()
	run_ledger["inventory_ejections"] = normalized_inventory_ejections
	# Old saves only keep a bounded list of ejected items. Where the cumulative
	# conversion fields are absent, derive a safe value from the available entries.
	var ejection_inventory_system = InventorySystemScript.new()
	if run_ledger.has("inventory_ejections_dust"):
		run_ledger["inventory_ejections_dust"] = clampi(int(run_ledger.get("inventory_ejections_dust", 0)), 0, GameState.MAX_ECHO_DUST)
	else:
		var migrated_dust := 0
		for migrated_item_value in normalized_inventory_ejections:
			migrated_dust = mini(GameState.MAX_ECHO_DUST, migrated_dust + int(ejection_inventory_system.get_ejection_echo_dust(migrated_item_value)))
		run_ledger["inventory_ejections_dust"] = migrated_dust
	run_ledger["inventory_ejections_count"] = clampi(int(run_ledger.get("inventory_ejections_count", normalized_inventory_ejections.size())), normalized_inventory_ejections.size(), 1000000)
	last_inventory_evicted_item.clear()
	if not normalized_inventory_ejections.is_empty():
		var last_ejection_value: Variant = normalized_inventory_ejections.back()
		if typeof(last_ejection_value) == TYPE_DICTIONARY:
			last_inventory_evicted_item = (last_ejection_value as Dictionary).duplicate(true)
	var history_value: Variant = run_ledger.get("event_history", [])
	var restored_event_history: Array = history_value.duplicate(true) if typeof(history_value) == TYPE_ARRAY else []
	while restored_event_history.size() > int(ContentRegistry.BALANCE.get("max_event_history", 100)):
		restored_event_history.pop_front()
	run_ledger["event_history"] = restored_event_history
	# Imported/older snapshots are normalized before checkpoints can affect the UI.
	var checkpoint_value: Variant = run_ledger.get("long_run_checkpoints", [])
	var checkpoint_entries: Array = checkpoint_value.duplicate(true) if typeof(checkpoint_value) == TYPE_ARRAY else []
	var restored_checkpoints: Array = []
	var seen_checkpoint_loops: Dictionary = {}
	if expedition_mode_id == "long_expedition":
		for checkpoint_value_entry in checkpoint_entries:
			if typeof(checkpoint_value_entry) != TYPE_DICTIONARY:
				continue
			var checkpoint_entry: Dictionary = checkpoint_value_entry
			var checkpoint_loop := int(checkpoint_entry.get("loop", 0))
			if checkpoint_loop < 1 or checkpoint_loop > 12 or seen_checkpoint_loops.has(checkpoint_loop):
				continue
			var checkpoint_max_hp := clampi(int(checkpoint_entry.get("max_hp", 1)), 1, 1000000)
			restored_checkpoints.append({
				"loop": checkpoint_loop,
				"hp": clampi(int(checkpoint_entry.get("hp", 0)), 0, checkpoint_max_hp),
				"max_hp": checkpoint_max_hp,
				"danger": clampf(float(checkpoint_entry.get("danger", 1.0)), 1.0, 6.0),
				"bosses_defeated": clampi(int(checkpoint_entry.get("bosses_defeated", 0)), 0, 12),
				"scrap": maxi(0, int(checkpoint_entry.get("scrap", 0))),
				"crystals": maxi(0, int(checkpoint_entry.get("crystals", 0)))
			})
			seen_checkpoint_loops[checkpoint_loop] = true
	while restored_checkpoints.size() > 8:
		restored_checkpoints.pop_front()
	run_ledger["long_run_checkpoints"] = restored_checkpoints
	var flags_value: Variant = run_ledger.get("event_flags", {})
	run_ledger["event_flags"] = flags_value.duplicate(true) if typeof(flags_value) == TYPE_DICTIONARY else {}
	var placed_value: Variant = snapshot.get("placed_tiles", {})
	placed_tiles = placed_value.duplicate(true) if typeof(placed_value) == TYPE_DICTIONARY else {}
	var world_tiles_value: Variant = snapshot.get("world_tiles", {})
	world_tiles = world_tiles_value.duplicate(true) if typeof(world_tiles_value) == TYPE_DICTIONARY else {}
	# Preserve the old fully visible map for saves created before Stage 88. Newer
	# snapshots carry a bounded discovery dictionary and are validated on restore.
	if snapshot.has("discovered_world_cells"):
		discovered_world_cells = _normalize_discovered_world_cells(snapshot.get("discovered_world_cells", {}))
	else:
		discovered_world_cells = _get_all_offroad_cells_discovered()
	var hand_value: Variant = snapshot.get("tile_hand", [])
	tile_hand = hand_value.duplicate(true) if typeof(hand_value) == TYPE_ARRAY else []
	run_ledger["last_tile_exchange_loop"] = clampi(int(run_ledger.get("last_tile_exchange_loop", -1)), -1, maxi(-1, int(snapshot.get("loop_count", 0))))
	var bag_value: Variant = snapshot.get("bag", [])
	var legacy_bag: Array = bag_value.duplicate(true) if typeof(bag_value) == TYPE_ARRAY else []
	var field_cache_value: Variant = snapshot.get("field_cache", [])
	var legacy_cache: Array = field_cache_value.duplicate(true) if typeof(field_cache_value) == TYPE_ARRAY else []
	var inventory_order_version := clampi(int(snapshot.get("inventory_order_version", 1)), 1, INVENTORY_ORDER_VERSION)
	var imported_items: Array = []
	if inventory_order_version < INVENTORY_ORDER_VERSION:
		# Stage 78 and earlier stored oldest-first in bag, then newer overflow in field_cache.
		# Reverse the combined chronology to migrate to newest-first queue semantics.
		imported_items.append_array(legacy_bag)
		imported_items.append_array(legacy_cache)
		imported_items.reverse()
	else:
		imported_items = legacy_bag
		# Defensive recovery for a hand-edited snapshot that still has legacy overflow.
		if not legacy_cache.is_empty():
			var older_overflow: Array = legacy_cache.duplicate(true)
			older_overflow.reverse()
			imported_items.append_array(older_overflow)
	var normalized_bag: Array = []
	var seen_run_item_ids: Dictionary = {}
	for imported_item_value in imported_items:
		if typeof(imported_item_value) != TYPE_DICTIONARY:
			continue
		var imported_item: Dictionary = imported_item_value
		var imported_item_id := str(imported_item.get("id", ""))
		if imported_item_id.is_empty() or seen_run_item_ids.has(imported_item_id) or not inventory_system.can_equip_item(imported_item):
			continue
		seen_run_item_ids[imported_item_id] = true
		normalized_bag.append(imported_item.duplicate(true))
	while normalized_bag.size() > BACKPACK_CAPACITY:
		normalized_bag.pop_back()
	bag = normalized_bag
	field_cache.clear()
	var equipment_value: Variant = snapshot.get("equipment", {})
	var imported_equipment: Dictionary = equipment_value.duplicate(true) if typeof(equipment_value) == TYPE_DICTIONARY else {}
	var normalized_equipment: Dictionary = {}
	var seen_equipped_item_ids: Dictionary = {}
	# Repair the cross-container identity invariant when restoring old or hand-edited
	# snapshots: a single item ID may exist in exactly one equipment slot or bag cell.
	# Equipped gear takes precedence over a duplicate backpack copy.
	for slot_value in InventorySystemScript.EQUIPMENT_SLOTS:
		var slot := str(slot_value)
		var candidate_value: Variant = imported_equipment.get(slot, {})
		var candidate: Dictionary = candidate_value if typeof(candidate_value) == TYPE_DICTIONARY else {}
		var candidate_id := str(candidate.get("id", ""))
		if inventory_system.can_equip_item(candidate, slot) and not seen_equipped_item_ids.has(candidate_id):
			normalized_equipment[slot] = candidate.duplicate(true)
			seen_equipped_item_ids[candidate_id] = true
		else:
			normalized_equipment[slot] = {}
	equipment = normalized_equipment
	var unique_bag: Array = []
	for bag_item_value in bag:
		if typeof(bag_item_value) != TYPE_DICTIONARY:
			continue
		var bag_item: Dictionary = bag_item_value
		var bag_item_id := str(bag_item.get("id", ""))
		if seen_equipped_item_ids.has(bag_item_id):
			continue
		unique_bag.append(bag_item.duplicate(true))
	bag = unique_bag
	var enemy_value: Variant = snapshot.get("enemy", {})
	enemy = enemy_value.duplicate(true) if typeof(enemy_value) == TYPE_DICTIONARY else {}
	var encounter_value: Variant = snapshot.get("encounter_enemies", [])
	encounter_enemies = encounter_value.duplicate(true) if typeof(encounter_value) == TYPE_ARRAY else []
	if not enemy.is_empty() and encounter_enemies.is_empty():
		encounter_enemies.append(enemy.duplicate(true))
	elif not encounter_enemies.is_empty():
		enemy = encounter_enemies[0]
	if not enemy.is_empty():
		status_effect_system.normalize_legacy_entity(enemy)
	for encounter_entry in encounter_enemies:
		if typeof(encounter_entry) == TYPE_DICTIONARY:
			status_effect_system.normalize_legacy_entity(encounter_entry)
	if not encounter_enemies.is_empty():
		enemy = encounter_enemies[0]
	combat_cell = int(snapshot.get("combat_cell", -1))
	var timers_value: Variant = snapshot.get("combat_timers", {})
	combat_timers = timers_value.duplicate(true) if typeof(timers_value) == TYPE_DICTIONARY else {"hero": 0.0, "enemy": 0.0}
	combat_timers["hero"] = maxf(0.0, float(combat_timers.get("hero", 0.0)))
	combat_timers["enemy"] = maxf(0.0, float(combat_timers.get("enemy", 0.0)))
	combat_reward_bonus = float(snapshot.get("combat_reward_bonus", 0.0))
	current_tile_spawn_bonus = float(snapshot.get("current_tile_spawn_bonus", 0.0))
	pending_perk_count = maxi(0, int(snapshot.get("pending_perk_count", 0)))
	var perk_value: Variant = snapshot.get("pending_perk_choices", [])
	pending_perk_choices = perk_value.duplicate(true) if typeof(perk_value) == TYPE_ARRAY else []
	var event_value: Variant = snapshot.get("pending_event", {})
	pending_event = event_value.duplicate(true) if typeof(event_value) == TYPE_DICTIONARY else {}
	last_event_id = str(snapshot.get("last_event_id", ""))
	var log_value: Variant = snapshot.get("event_log", [])
	event_log = log_value.duplicate(true) if typeof(log_value) == TYPE_ARRAY else []
	distance = clampf(float(snapshot.get("distance", 0.0)), 0.0, float(maxi(1, route.size() * (int(snapshot.get("loop_count", 0)) + 1))))
	processed_steps = maxi(0, int(snapshot.get("processed_steps", floori(distance))))
	loop_count = maxi(0, int(snapshot.get("loop_count", 0)))
	danger = maxf(1.0, float(snapshot.get("danger", 1.0)))
	speed = clampf(float(snapshot.get("speed", 1.0)), 1.0, 3.0)
	paused = true # Resume safely in a paused state so no combat/event advances under a modal.
	active = true
	_refresh_accumulator = 0.0
	_autosave_elapsed = 0.0
	_sync_hero_stats()
	_log("Сохранённая экспедиция восстановлена и поставлена на паузу.")
	changed.emit()
	save_run_snapshot()
	return true

func _rng_for_draw() -> RandomNumberGenerator:
	return run_rng

func _tick_route(delta: float) -> void:
	if pending_perk_count > 0:
		return
	distance += delta * float(ContentRegistry.BALANCE.move_speed)
	var target_step := int(floor(distance))
	while processed_steps < target_step and active and enemy.is_empty() and pending_event.is_empty():
		processed_steps += 1
		var cell_index := posmod(processed_steps, route.size())
		if cell_index == 0:
			loop_count += 1
			var active_difficulty: Dictionary = ContentRegistry.DIFFICULTY_PRESETS.get(difficulty_id, ContentRegistry.DIFFICULTY_PRESETS["standard"])
			var floor_config: Dictionary = get_floor_config()
			danger += float(ContentRegistry.BALANCE.get("loop_danger_growth", 0.18)) * float(floor_config.get("danger_growth_multiplier", 1.0)) * float(active_difficulty.get("danger_growth_multiplier", 1.0)) * float(get_run_modifier().get("danger_growth_multiplier", 1.0)) * float(get_expedition_mode().get("danger_growth_multiplier", 1.0))
			danger = _clamp_long_mode_danger(danger)
			var loop_reward_base := int(ContentRegistry.BALANCE.route_reward_scrap) + GameState.get_effective_loop_scrap_bonus()
			var combined_reward_multiplier := float(floor_config.get("reward_multiplier", 1.0)) * float(active_difficulty.get("reward_multiplier", 1.0)) * float(get_run_modifier().get("reward_multiplier", 1.0))
			if expedition_mode_id == "long_expedition":
				combined_reward_multiplier = minf(combined_reward_multiplier, float(get_expedition_mode().get("reward_multiplier_cap", 1.8)))
			var loop_reward := int(round(float(loop_reward_base) * combined_reward_multiplier))
			resource_system.add(run_ledger, "scrap", loop_reward)
			if loop_count % maxi(1, int(ContentRegistry.BALANCE.get("loop_crystal_interval", 2))) == 0:
				resource_system.add(run_ledger, "crystals", 1 + int(GameState.get_unlock_effect("loop_crystal_bonus")))
			var loop_heal := _scale_healing(int(ContentRegistry.BALANCE.get("loop_heal_base", 5)) + int(GameState.get_unlock_effect("loop_heal_bonus")))
			hero.hp = mini(int(hero.max_hp), int(hero.hp) + loop_heal)
			_log("Цикл %d завершён: +%d материалов, здоровье частично восстановлено." % [loop_count, loop_reward])
			_record_long_expedition_checkpoint()
			if loop_count % maxi(1, int(ContentRegistry.BALANCE.get("loop_crystal_interval", 2))) == 0:
				_log("Сигнал маршрута: за второй завершённый цикл получен редкий ресурс.")
			_maybe_add_tile("Завершение цикла", 0.68)
		_visit_cell(cell_index)
		if not enemy.is_empty() or pending_perk_count > 0 or not pending_event.is_empty():
			# Save after snapping distance to the exact visited cell, so resume won't
			# accidentally skip the cell that initiated the encounter/event.
			distance = float(processed_steps)
			save_run_snapshot()
			break

func _normalize_discovered_world_cells(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(value) != TYPE_DICTIONARY:
		return result
	var source: Dictionary = value
	for cell_id_value in source.keys():
		var cell_id := str(cell_id_value)
		if not TileSystemScript.is_map_world_cell_id(cell_id):
			continue
		if bool(source.get(cell_id_value, false)):
			result[cell_id] = true
	return result

func _get_all_offroad_cells_discovered() -> Dictionary:
	var result: Dictionary = {}
	var road_lookup: Dictionary = {}
	for coord_value in TileSystemScript.get_road_grid_coordinates_for_seed(get_route_shape_id(), route_geometry_seed):
		var coord: Vector2i = coord_value
		road_lookup["%d:%d" % [coord.x, coord.y]] = true
	for row in range(TileSystemScript.MAP_ROWS):
		for col in range(TileSystemScript.MAP_COLUMNS):
			if road_lookup.has("%d:%d" % [col, row]):
				continue
			result[TileSystemScript.map_world_cell_id(col, row)] = true
	return result

func _reveal_world_cells_near_route_index(route_index: int) -> void:
	if route.is_empty():
		return
	var road_cells: Array[Vector2i] = TileSystemScript.get_road_grid_coordinates_for_seed(get_route_shape_id(), route_geometry_seed)
	if road_cells.is_empty():
		return
	var route_slot := posmod(roundi(float(route_index) * float(road_cells.size()) / float(route.size())), road_cells.size())
	var pivot: Vector2i = road_cells[route_slot]
	var road_lookup: Dictionary = {}
	for coord_value in road_cells:
		var coord: Vector2i = coord_value
		road_lookup["%d:%d" % [coord.x, coord.y]] = true
	# Reveal a small Manhattan-radius around the visited road cell. Discovery is
	# presentation-only: this does not change card eligibility or stable tile IDs.
	for row in range(TileSystemScript.MAP_ROWS):
		for col in range(TileSystemScript.MAP_COLUMNS):
			if absi(col - pivot.x) + absi(row - pivot.y) > 3:
				continue
			if road_lookup.has("%d:%d" % [col, row]):
				continue
			var cell_id := TileSystemScript.map_world_cell_id(col, row)
			discovered_world_cells[cell_id] = true

func _visit_cell(index: int) -> void:
	if route.is_empty():
		return
	_reveal_world_cells_near_route_index(index)
	var base_kind: String = route_system.get_cell_kind(route, index)
	var spawn_bonus := clampf(float(hero.get("equipped_tile_spawn_bonus", 0.0)) + float(hero.get("perk_tile_spawn_bonus", 0.0)), -0.25, 0.25)
	var strength_bonus := 0.0
	var reward_bonus := 0.0
	var should_offer_event: bool = false
	var cache_node_found: bool = base_kind == "cache"
	var messages: Array = []
	var encounter_pool: Array[String] = []
	match base_kind:
		"cache":
			resource_system.add(run_ledger, "scrap", 2 + mini(loop_count, 2))
			messages.append("Маршрутная находка: материалы добавлены в добычу.")
		"event":
			should_offer_event = true
			messages.append("На узле обнаружена ситуация, требующая решения.")
		"danger":
			spawn_bonus += 0.27
			strength_bonus += 0.08
			messages.append("Опасный участок повышает вероятность столкновения.")
		"shrine":
			if index != 0:
				var shrine_heal := _scale_healing(4)
				var healing := mini(shrine_heal, int(hero.max_hp) - int(hero.hp))
				hero.hp = mini(int(hero.max_hp), int(hero.hp) + shrine_heal)
				if healing > 0:
					messages.append("Тихая зона восстановила %d здоровья." % healing)
	if placed_tiles.has(str(index)):
		var placed_tile_value: Variant = placed_tiles[str(index)]
		if typeof(placed_tile_value) == TYPE_DICTIONARY and str(placed_tile_value.get("id", "")) == "cache":
			cache_node_found = true
		var effects: Dictionary = tile_system.apply_tile_visit(placed_tiles[str(index)], run_ledger, hero, loop_count)
		for pool_value in effects.get("enemy_pool", []):
			var pool_id := str(pool_value)
			if not pool_id.is_empty() and not encounter_pool.has(pool_id):
				encounter_pool.append(pool_id)
		var equipment_tile_scrap: int = clampi(int(hero.get("equipped_tile_scrap", 0)) + int(hero.get("perk_tile_scrap_bonus", 0)), 0, 5)
		if equipment_tile_scrap > 0:
			resource_system.add(run_ledger, "scrap", equipment_tile_scrap)
			effects.messages.append("Экипировка дала +%d материала за посещение тайла." % equipment_tile_scrap)
		spawn_bonus += float(effects.get("spawn_bonus", 0.0))
		strength_bonus += float(effects.get("enemy_bonus", 0.0))
		reward_bonus += float(effects.get("reward_bonus", 0.0))
		messages.append_array(effects.get("messages", []))
	for world_cell_value in world_tiles.keys():
		var world_cell_id := str(world_cell_value)
		var world_tile_value: Variant = world_tiles[world_cell_value]
		if typeof(world_tile_value) != TYPE_DICTIONARY:
			continue
		var world_tile: Dictionary = world_tile_value
		if int(world_tile.get("route_index", -1)) != index:
			continue
		if str(world_tile.get("id", "")) == "cache":
			cache_node_found = true
		var world_effects: Dictionary = tile_system.apply_tile_visit(world_tile, run_ledger, hero, loop_count)
		var landscape_affinity: Dictionary = inventory_system.get_landscape_affinity_effects(equipment, str(world_tile.get("id", "")))
		var affinity_heal := mini(_scale_healing(int(landscape_affinity.get("heal", 0))), maxi(0, int(hero.get("max_hp", 0)) - int(hero.get("hp", 0))))
		if affinity_heal > 0:
			hero["hp"] = mini(int(hero.get("max_hp", 0)), int(hero.get("hp", 0)) + affinity_heal)
			world_effects.messages.append("Резонанс экипировки восстановил %d здоровья." % affinity_heal)
		for affinity_resource in ["scrap", "crystals"]:
			var affinity_amount := maxi(0, int(landscape_affinity.get(affinity_resource, 0)))
			if affinity_amount > 0:
				resource_system.add(run_ledger, affinity_resource, affinity_amount)
				world_effects.messages.append("Резонанс экипировки: +%d %s." % [affinity_amount, "материала" if affinity_resource == "scrap" else "кристалл(ов)"])
		world_effects["spawn_bonus"] = clampf(float(world_effects.get("spawn_bonus", 0.0)) + float(landscape_affinity.get("spawn_bonus", 0.0)), -0.5, 0.5)
		world_effects["enemy_bonus"] = clampf(float(world_effects.get("enemy_bonus", 0.0)) + float(landscape_affinity.get("enemy_bonus", 0.0)), -0.5, 0.75)
		world_effects["reward_bonus"] = clampf(float(world_effects.get("reward_bonus", 0.0)) + float(landscape_affinity.get("reward_bonus", 0.0)), -0.25, 1.5)
		var affinity_messages: Variant = landscape_affinity.get("messages", [])
		if typeof(affinity_messages) == TYPE_ARRAY:
			world_effects.messages.append_array(affinity_messages)
		for world_pool_value in world_effects.get("enemy_pool", []):
			var world_pool_id := str(world_pool_value)
			if not world_pool_id.is_empty() and not encounter_pool.has(world_pool_id):
				encounter_pool.append(world_pool_id)
		var tile_scrap_bonus: int = clampi(int(hero.get("equipped_tile_scrap", 0)) + int(hero.get("perk_tile_scrap_bonus", 0)), 0, 5)
		if tile_scrap_bonus > 0:
			resource_system.add(run_ledger, "scrap", tile_scrap_bonus)
			world_effects.messages.append("Экипировка дала +%d материала за посещение клетки ландшафта." % tile_scrap_bonus)
		spawn_bonus += float(world_effects.get("spawn_bonus", 0.0))
		strength_bonus += float(world_effects.get("enemy_bonus", 0.0))
		reward_bonus += float(world_effects.get("reward_bonus", 0.0))
		messages.append_array(world_effects.get("messages", []))
	var world_synergy: Dictionary = tile_system.get_world_synergy_bonus_for_route_index(world_tiles, index)
	reward_bonus += float(world_synergy.get("reward", 0.0))
	spawn_bonus += float(world_synergy.get("spawn_bonus", 0.0))
	strength_bonus += float(world_synergy.get("enemy_bonus", 0.0))
	var world_synergy_scrap := maxi(0, int(world_synergy.get("scrap", 0)))
	if world_synergy_scrap > 0:
		resource_system.add(run_ledger, "scrap", world_synergy_scrap)
		messages.append("Соседство ландшафта принесло +%d материала." % world_synergy_scrap)
	var world_synergy_heal := mini(_scale_healing(int(world_synergy.get("heal", 0))), maxi(0, int(hero.get("max_hp", 0)) - int(hero.get("hp", 0))))
	if world_synergy_heal > 0:
		hero["hp"] = mini(int(hero.get("max_hp", 0)), int(hero.get("hp", 0)) + world_synergy_heal)
		messages.append("Сочетание ландшафта восстановило %d здоровья." % world_synergy_heal)
	messages.append_array(world_synergy.get("messages", []))
	var synergy: Dictionary = tile_system.get_synergy_bonus(placed_tiles, index, route.size(), equipment)
	reward_bonus += float(synergy.get("reward", 0.0))
	spawn_bonus += float(synergy.get("spawn_bonus", 0.0))
	strength_bonus += float(synergy.get("enemy_bonus", 0.0))
	var synergy_scrap: int = maxi(0, int(synergy.get("scrap", 0)))
	if synergy_scrap > 0:
		resource_system.add(run_ledger, "scrap", synergy_scrap)
		messages.append("Комбинация тайлов принесла +%d материала." % synergy_scrap)
	if int(synergy.get("heal", 0)) > 0:
		var scaled_synergy_heal: int = _scale_healing(int(synergy.get("heal", 0)))
		var synergy_heal: int = mini(scaled_synergy_heal, maxi(0, int(hero.max_hp) - int(hero.hp)))
		hero.hp = mini(int(hero.max_hp), int(hero.hp) + scaled_synergy_heal)
		if synergy_heal > 0:
			messages.append("Связка тайлов восстановила %d здоровья." % synergy_heal)
	var synergy_messages_value: Variant = synergy.get("messages", [])
	if typeof(synergy_messages_value) == TYPE_ARRAY:
		for synergy_message in synergy_messages_value:
			messages.append(str(synergy_message))
	_discover_landscape_secrets(index, messages)
	if cache_node_found:
		_try_cache_equipment_drop(index)
	# Final stage of the pipeline: apply limits once after base node, local,
	# equipment/perk, and neighbour modifiers have all been accumulated.
	var capped_visit: Dictionary = tile_system.clamp_visit_modifiers({"spawn_bonus": spawn_bonus, "enemy_bonus": strength_bonus, "reward_bonus": reward_bonus})
	spawn_bonus = float(capped_visit.get("spawn_bonus", spawn_bonus))
	strength_bonus = float(capped_visit.get("enemy_bonus", strength_bonus))
	reward_bonus = float(capped_visit.get("reward_bonus", reward_bonus))
	for cap_value in capped_visit.get("caps_applied", []):
		messages.append("Совокупный эффект «%s» ограничен безопасным пределом этого сектора." % str(cap_value))
	for message in messages:
		_log(str(message))
	if should_offer_event:
		_begin_expedition_event(index, spawn_bonus, strength_bonus, reward_bonus, encounter_pool)
		return
	var active_difficulty: Dictionary = ContentRegistry.DIFFICULTY_PRESETS.get(difficulty_id, ContentRegistry.DIFFICULTY_PRESETS["standard"])
	var floor_config: Dictionary = get_floor_config()
	var base_chance := clampf(float(ContentRegistry.BALANCE.get("encounter_chance_base", 0.22)) + float(loop_count) * float(ContentRegistry.BALANCE.get("encounter_chance_per_loop", 0.04)) + spawn_bonus + float(floor_config.get("encounter_chance_delta", 0.0)) + float(active_difficulty.get("encounter_chance_delta", 0.0)) + _get_modifier_chance_delta(), float(ContentRegistry.BALANCE.get("encounter_chance_min", 0.08)), float(ContentRegistry.BALANCE.get("encounter_chance_max", 0.96)))
	var boss_interval := maxi(1, int(floor_config.get("boss_loop", ContentRegistry.BALANCE.get("boss_loop_interval", 3))))
	var is_boss_node := index == 0 and loop_count > 0 and loop_count % boss_interval == 0
	if is_boss_node:
		_start_encounter(index, strength_bonus, reward_bonus, true)
	elif _rng_for_event().randf() < base_chance:
		_start_encounter(index, strength_bonus, reward_bonus, false, encounter_pool)
	else:
		if messages.is_empty():
			_log("Узел %d: маршрут свободен." % (index + 1))

func _try_cache_equipment_drop(route_index: int) -> void:
	var drop_rng := _rng_for_event()
	var echo_charges := clampi(int(run_ledger.get("echo_item_charges", 0)), 0, 4)
	var pending_drop_bonus := clampf(float(run_ledger.get("pending_item_drop_bonus", 0.0)), 0.0, 0.30)
	var cache_chance: float = loot_system.get_equipment_drop_chance("cache", 0.0, echo_charges, pending_drop_bonus)
	if drop_rng.randf() >= cache_chance:
		_log("Тайник на узле %d открыт, но экипировки внутри не оказалось. Шанс находки: %d%%; качество не бросалось, так как предмет не выпал." % [route_index + 1, int(round(cache_chance * 100.0))])
		return
	var pending_rarity_bonus := clampf(float(run_ledger.get("pending_item_rarity_bonus", 0.0)), 0.0, 0.18)
	var equipped_rarity_bonus := clampf(float(hero.get("equipped_rare_find_bonus", 0.0)), 0.0, 0.12)
	var effective_rarity_bonus: float = inventory_system.get_effective_rarity_bonus(equipped_rarity_bonus, pending_rarity_bonus, loot_system.get_source_rarity_bonus("cache"))
	var item: Dictionary = inventory_system.roll_item(drop_rng, loop_count, int(hero.get("level", 1)), effective_rarity_bonus)
	if item.is_empty():
		return
	item["drop_source"] = "cache"
	if not _store_run_item(item):
		_log("ТАЙНИК: предмет не удалось добавить в рюкзак — данные предмета не прошли проверку.")
		return
	if echo_charges > 0:
		run_ledger["echo_item_charges"] = maxi(0, echo_charges - 1)
	run_ledger["pending_item_rarity_bonus"] = 0.0
	run_ledger["pending_item_drop_bonus"] = 0.0
	var rarity_distribution: Dictionary = inventory_system.get_rarity_distribution(effective_rarity_bonus)
	var rolled_rarity := str(item.get("rarity", "Обычный"))
	var rolled_rarity_chance := float(rarity_distribution.get(rolled_rarity, 0.0))
	_log("ТАЙНИК ОТКРЫТ: %s · %s. Шанс предмета %d%%; шанс этого качества при текущей подготовке %.1f%%. Предмет в начало рюкзака; правый клик — быстро надеть." % [str(item.get("name", "Находка")), rolled_rarity, int(round(cache_chance * 100.0)), rolled_rarity_chance * 100.0])
	_request_feedback("loot", str(item.get("name", "Предмет из тайника")))

func _discover_landscape_secrets(route_index: int, messages: Array) -> void:
	if world_tiles.is_empty() or route_index < 0:
		return
	var flags_value: Variant = run_ledger.get("event_flags", {})
	var flags: Dictionary = flags_value.duplicate(true) if typeof(flags_value) == TYPE_DICTIONARY else {}
	var changed_flags := false
	for recipe_value in ContentRegistry.LANDSCAPE_SECRET_RECIPES:
		if typeof(recipe_value) != TYPE_DICTIONARY:
			continue
		var recipe: Dictionary = recipe_value
		var flag_id := str(recipe.get("flag", ""))
		if flag_id.is_empty() or bool(flags.get(flag_id, false)):
			continue
		var first_id := str(recipe.get("first_tile", ""))
		var second_id := str(recipe.get("second_tile", ""))
		var discovered := false
		for cell_value in world_tiles.keys():
			var cell_id := str(cell_value)
			var cell_value_data: Variant = world_tiles[cell_value]
			if typeof(cell_value_data) != TYPE_DICTIONARY:
				continue
			var current_tile: Dictionary = cell_value_data
			if int(current_tile.get("route_index", -1)) != route_index:
				continue
			if not TileSystemScript.is_world_cell_valid(cell_id):
				continue
			var current_id := str(current_tile.get("id", ""))
			# Visit each orthogonal pair once; works for legacy and full-board IDs.
			for neighbor_id in TileSystemScript.world_cell_neighbors(cell_id):
				if neighbor_id <= cell_id or not world_tiles.has(neighbor_id):
					continue
				var neighbor_value: Variant = world_tiles[neighbor_id]
				if typeof(neighbor_value) != TYPE_DICTIONARY:
					continue
				var neighbor_tile: Dictionary = neighbor_value
				if int(neighbor_tile.get("route_index", -1)) != route_index:
					continue
				var neighbor_tile_id := str(neighbor_tile.get("id", ""))
				var direct_match := current_id == first_id and neighbor_tile_id == second_id
				var reverse_match := current_id == second_id and neighbor_tile_id == first_id
				if direct_match or reverse_match:
					discovered = true
					break
			if discovered:
				break
		if discovered:
			flags[flag_id] = true
			changed_flags = true
			messages.append("ТАЙНА ОБНАРУЖЕНА — %s. %s На ближайшем узле события появится особый выбор." % [str(recipe.get("title", "Скрытый след")), str(recipe.get("clue", ""))])
	if changed_flags:
		run_ledger["event_flags"] = flags

func _begin_expedition_event(index: int, spawn_bonus: float, strength_bonus: float, reward_bonus: float, enemy_pool: Array = []) -> void:
	pending_event = expedition_event_system.draw_event(run_rng, loop_count, last_event_id, run_ledger.get("event_flags", {}))
	if pending_event.is_empty():
		_log("Событие не удалось сформировать; маршрут продолжается без остановки.")
		return
	last_event_id = str(pending_event.get("id", ""))
	pending_event["context"] = {
		"cell_index": index,
		"spawn_bonus": spawn_bonus,
		"strength_bonus": strength_bonus,
		"reward_bonus": reward_bonus,
		"enemy_pool": enemy_pool.duplicate(true)
	}
	_log("Событие «%s»: ожидается решение игрока." % str(pending_event.get("name", "Событие")))
	changed.emit()

func _get_pending_event_choice(choice_id: String) -> Dictionary:
	if pending_event.is_empty():
		return {}
	var choices_value: Variant = pending_event.get("choices", [])
	if typeof(choices_value) != TYPE_ARRAY:
		return {}
	for choice_value in choices_value:
		if typeof(choice_value) != TYPE_DICTIONARY:
			continue
		var choice: Dictionary = choice_value
		if str(choice.get("id", "")) == choice_id:
			return choice
	return {}

func event_choice_is_available(choice_id: String) -> bool:
	var choice: Dictionary = _get_pending_event_choice(choice_id)
	if choice.is_empty():
		return false
	var effects_value: Variant = choice.get("effects", {})
	if typeof(effects_value) != TYPE_DICTIONARY:
		return false
	var effects: Dictionary = effects_value
	return int(run_ledger.get("scrap", 0)) >= maxi(0, int(effects.get("cost_scrap", 0)))

func resolve_event_choice(choice_id: String) -> Dictionary:
	if not pending_end_outcome.is_empty():
		return {"ok": false, "reason": "Сначала повторите сохранение итогов экспедиции."}
	if not active or pending_event.is_empty():
		return {"ok": false, "reason": "Сейчас нет события, ожидающего решения."}
	var choice: Dictionary = _get_pending_event_choice(choice_id)
	if choice.is_empty():
		return {"ok": false, "reason": "Этот вариант больше недоступен."}
	var effects_value: Variant = choice.get("effects", {})
	if typeof(effects_value) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "У варианта повреждены данные эффектов."}
	var effects: Dictionary = effects_value
	var cost_scrap: int = maxi(0, int(effects.get("cost_scrap", 0)))
	if int(run_ledger.get("scrap", 0)) < cost_scrap:
		return {"ok": false, "reason": "Не хватает материалов в добыче этой экспедиции."}
	if cost_scrap > 0:
		run_ledger["scrap"] = maxi(0, int(run_ledger.get("scrap", 0)) - cost_scrap)
	resource_system.add(run_ledger, "scrap", maxi(0, int(effects.get("scrap", 0))))
	resource_system.add(run_ledger, "crystals", maxi(0, int(effects.get("crystals", 0))))
	var event_difficulty: Dictionary = ContentRegistry.DIFFICULTY_PRESETS.get(difficulty_id, ContentRegistry.DIFFICULTY_PRESETS["standard"])
	var floor_config: Dictionary = get_floor_config()
	var event_damage_value: float = float(effects.get("damage", 0)) * float(floor_config.get("event_damage_multiplier", 1.0)) * float(event_difficulty.get("event_damage_multiplier", 1.0)) * float(get_run_modifier().get("event_damage_multiplier", 1.0))
	var research_damage_reduction: float = clampf(GameState.get_unlock_effect("event_damage_reduction"), 0.0, 0.75)
	var damage: int = maxi(0, int(ceil(event_damage_value * (1.0 - research_damage_reduction))))
	var healing: int = _scale_healing(maxi(0, int(effects.get("heal", 0))))
	hero["hp"] = maxi(0, int(hero.get("hp", 0)) - damage)
	var event_heal_bonus: int = _scale_healing(clampi(int(hero.get("equipped_event_heal", 0)) + int(hero.get("perk_event_heal_bonus", 0)), 0, 10))
	hero["hp"] = mini(int(hero.get("max_hp", 1)), int(hero.get("hp", 0)) + healing + event_heal_bonus)
	if event_heal_bonus > 0:
		_log("Экипировка восстановила ещё до %d здоровья после решения события." % event_heal_bonus)
	danger = clampf(danger + float(effects.get("danger_delta", 0.0)), 1.0, float(ContentRegistry.BALANCE.get("max_danger", 6.0)))
	var context_value: Variant = pending_event.get("context", {})
	var context: Dictionary = context_value.duplicate(true) if typeof(context_value) == TYPE_DICTIONARY else {}
	var event_name: String = str(pending_event.get("name", "Событие"))
	var choice_title: String = str(choice.get("title", choice_id))
	var flags_value: Variant = run_ledger.get("event_flags", {})
	var event_flags: Dictionary = flags_value.duplicate(true) if typeof(flags_value) == TYPE_DICTIONARY else {}
	var set_flags_value: Variant = effects.get("set_flags", [])
	if typeof(set_flags_value) == TYPE_ARRAY:
		for flag_value in set_flags_value:
			var flag_id := str(flag_value)
			if not flag_id.is_empty():
				event_flags[flag_id] = true
	var clear_flags_value: Variant = effects.get("clear_flags", [])
	if typeof(clear_flags_value) == TYPE_ARRAY:
		for flag_value in clear_flags_value:
			event_flags.erase(str(flag_value))
	var resolved_flag := str(pending_event.get("resolved_flag", ""))
	if not resolved_flag.is_empty():
		event_flags[resolved_flag] = true
	run_ledger["event_flags"] = event_flags
	var granted_item_id := str(effects.get("grant_item_id", ""))
	if not granted_item_id.is_empty():
		_grant_secret_event_item(granted_item_id)
	pending_event.clear()
	run_ledger["events_resolved"] = int(run_ledger.get("events_resolved", 0)) + 1
	var history_value: Variant = run_ledger.get("event_history", [])
	if typeof(history_value) != TYPE_ARRAY:
		history_value = []
	var history: Array = history_value
	history.append({"event": event_name, "choice": choice_title})
	while history.size() > int(ContentRegistry.BALANCE.get("max_event_history", 100)):
		history.pop_front()
	run_ledger["event_history"] = history
	_log("Решение: «%s» — %s." % [event_name, choice_title])
	_request_feedback("event", choice_title)
	if cost_scrap > 0:
		_log("Потрачено материалов: %d." % cost_scrap)
	if int(effects.get("scrap", 0)) > 0 or int(effects.get("crystals", 0)) > 0:
		_log("Награда события: +%d материалов, +%d редких ресурсов." % [maxi(0, int(effects.get("scrap", 0))), maxi(0, int(effects.get("crystals", 0)))])
	if damage > 0:
		_log("Последствие выбора: герой потерял %d здоровья." % damage)
	if healing > 0:
		_log("Событие восстановило до %d здоровья." % healing)
	if not is_zero_approx(float(effects.get("danger_delta", 0.0))):
		_log("Опасность экспедиции теперь ×%.1f." % danger)
	if int(hero.get("hp", 0)) <= 0:
		_log("Последствия события оказались смертельными.")
		_finish_run("defeat")
		return {"ok": true, "reason": "Событие завершилось поражением."}
	var spawn_bonus: float = float(context.get("spawn_bonus", 0.0)) + float(effects.get("spawn_bonus", 0.0))
	var strength_bonus: float = float(context.get("strength_bonus", 0.0))
	var reward_bonus: float = float(context.get("reward_bonus", 0.0)) + float(effects.get("reward_bonus", 0.0))
	var event_pool_value: Variant = context.get("enemy_pool", [])
	var event_enemy_pool: Array = event_pool_value.duplicate(true) if typeof(event_pool_value) == TYPE_ARRAY else []
	var encounter_difficulty: Dictionary = ContentRegistry.DIFFICULTY_PRESETS.get(difficulty_id, ContentRegistry.DIFFICULTY_PRESETS["standard"])
	var base_chance: float = clampf(float(ContentRegistry.BALANCE.get("encounter_chance_base", 0.22)) + float(loop_count) * float(ContentRegistry.BALANCE.get("encounter_chance_per_loop", 0.04)) + spawn_bonus + float(encounter_difficulty.get("encounter_chance_delta", 0.0)) + _get_modifier_chance_delta(), float(ContentRegistry.BALANCE.get("encounter_chance_min", 0.08)), float(ContentRegistry.BALANCE.get("encounter_chance_max", 0.96)))
	if _rng_for_event().randf() < base_chance:
		_start_encounter(int(context.get("cell_index", current_cell())), strength_bonus, reward_bonus, false, event_enemy_pool)
	else:
		_log("После события маршрут остаётся свободным.")
	_update_objective_progress()
	changed.emit()
	save_run_snapshot()
	return {"ok": true, "reason": "Решение применено."}

func _grant_secret_event_item(relic_id: String) -> Dictionary:
	var item: Dictionary = inventory_system.make_secret_relic(relic_id, loop_count, int(hero.get("level", 1)), run_seed, GameState.runs_started)
	if item.is_empty():
		_log("Секретная награда не распознана: %s. Остальные последствия выбора сохранены." % relic_id)
		return {}
	if _store_run_item(item):
		var affinity_text := " Связана с ландшафтом: %s." % str(item.get("affinity_name", "неизвестный участок")) if not str(item.get("landscape_affinity", "")).is_empty() else ""
		_log("ТАЙНАЯ РЕЛИКВИЯ: %s. Помещена в начало рюкзака — наденьте её вручную.%s" % [str(item.get("name", "Новая реликвия")), affinity_text])
		if not last_inventory_evicted_item.is_empty():
			_log("Старейшая вещь вытеснена: %s." % str(last_inventory_evicted_item.get("name", "Предмет")))
	else:
		_log("ТАЙНАЯ РЕЛИКВИЯ: %s не удалось добавить в рюкзак; предмет не закреплён за убежищем." % str(item.get("name", "Новая реликвия")))
	_request_feedback("loot", str(item.get("name", "Тайная реликвия")))
	return item

func _start_encounter(index: int, strength_bonus: float, reward_bonus: float, boss_encounter: bool, enemy_pool: Array = []) -> void:
	var active_difficulty: Dictionary = ContentRegistry.DIFFICULTY_PRESETS.get(difficulty_id, ContentRegistry.DIFFICULTY_PRESETS["standard"])
	var floor_config: Dictionary = get_floor_config()
	var modifier: Dictionary = get_run_modifier()
	var encounter_scaling_loop := _effective_scaling_loop(loop_count)
	var effective_enemy_pool: Array = enemy_pool if not enemy_pool.is_empty() else floor_config.get("enemy_pool", [])
	var preferred_boss_id: String = str(floor_config.get("boss_id", "")) if boss_encounter else ""
	encounter_enemies = enemy_system.create_encounter(encounter_scaling_loop, danger, _rng_for_event(), strength_bonus, boss_encounter, int(floor_config.get("extra_group_members", 0)) + int(active_difficulty.get("extra_group_members", 0)) + int(modifier.get("extra_group_members", 0)), effective_enemy_pool, preferred_boss_id)
	if encounter_enemies.is_empty():
		return
	var elite_interval := maxi(1, int(ContentRegistry.BALANCE.get("elite_loop_interval", 4)))
	var elite_min_loop := maxi(1, int(ContentRegistry.BALANCE.get("elite_min_loop", 2)))
	var boss_interval := maxi(1, int(floor_config.get("boss_loop", ContentRegistry.BALANCE.get("boss_loop_interval", 3))))
	var elite_due := not boss_encounter and loop_count >= elite_min_loop and posmod(loop_count, elite_interval) == 0 and posmod(loop_count, boss_interval) != 0
	if elite_due:
		var promoted_elite: Dictionary = enemy_system.promote_encounter_to_elite(encounter_enemies, loop_count)
		if not promoted_elite.is_empty():
			_log("Разведка предупреждает: впереди элитный противник. Следите за сигналом перед его усиленной атакой.")
	for enemy_index in range(encounter_enemies.size()):
		var enemy_value: Variant = encounter_enemies[enemy_index]
		if typeof(enemy_value) != TYPE_DICTIONARY:
			continue
		var enemy_data: Dictionary = enemy_value
		var attack_multiplier := float(floor_config.get("enemy_attack_multiplier", 1.0)) * float(active_difficulty.get("enemy_attack_multiplier", 1.0)) * float(modifier.get("enemy_attack_multiplier", 1.0))
		var health_multiplier := float(floor_config.get("enemy_health_multiplier", 1.0)) * float(active_difficulty.get("enemy_health_multiplier", 1.0)) * float(modifier.get("enemy_health_multiplier", 1.0))
		var defense_multiplier := float(floor_config.get("enemy_defense_multiplier", 1.0)) * float(active_difficulty.get("enemy_defense_multiplier", 1.0)) * float(modifier.get("enemy_defense_multiplier", 1.0))
		if enemy_data.has("base_attack"):
			enemy_data["base_attack"] = maxf(1.0, float(enemy_data.get("base_attack", enemy_data.get("attack", 1.0))) * attack_multiplier)
			enemy_data["attack"] = maxf(1.0, float(enemy_data.get("attack", 1.0)) * attack_multiplier)
		if enemy_data.has("base_defense"):
			enemy_data["base_defense"] = maxi(0, int(round(float(enemy_data.get("base_defense", 0)) * defense_multiplier)))
			enemy_data["defense"] = maxi(0, int(round(float(enemy_data.get("defense", 0)) * defense_multiplier)))
		else:
			enemy_data["defense"] = maxi(0, int(round(float(enemy_data.get("defense", 0)) * defense_multiplier)))
		var scaled_max_hp := maxi(1, int(ceil(float(enemy_data.get("max_hp", enemy_data.get("hp", 1))) * health_multiplier)))
		var hp_ratio := float(enemy_data.get("hp", scaled_max_hp)) / maxf(1.0, float(enemy_data.get("max_hp", scaled_max_hp)))
		enemy_data["max_hp"] = scaled_max_hp
		enemy_data["hp"] = clampi(int(round(hp_ratio * scaled_max_hp)), 1, scaled_max_hp)
		encounter_enemies[enemy_index] = enemy_data
	var cadence_bonus := int(GameState.get_unlock_effect("boss_special_cadence_bonus"))
	if cadence_bonus > 0:
		for enemy_index in range(encounter_enemies.size()):
			var enemy_value: Variant = encounter_enemies[enemy_index]
			if typeof(enemy_value) != TYPE_DICTIONARY:
				continue
			var enemy_data: Dictionary = enemy_value
			if bool(enemy_data.get("is_boss", false)):
				enemy_data["special_every"] = maxi(2, int(enemy_data.get("special_every", 3)) + cadence_bonus)
				encounter_enemies[enemy_index] = enemy_data
	enemy = encounter_enemies[0]
	for enemy_value in encounter_enemies:
		if typeof(enemy_value) == TYPE_DICTIONARY:
			status_effect_system.normalize_legacy_entity(enemy_value)
	var barrier_strength := int(hero.get("barrier_on_encounter", 0))
	if barrier_strength > 0:
		var barrier_result: Dictionary = status_effect_system.apply_effect(hero, "barrier", -1.0, float(barrier_strength), "equipment_bastion")
		if bool(barrier_result.get("ok", false)):
			_log("Защитный барьер экипировки: %d поглощения урона." % int(round(float(barrier_result.get("magnitude", barrier_strength)))))
	combat_cell = index
	combat_timers = {"hero": 0.0, "enemy": 0.0}
	combat_reward_bonus = reward_bonus + clampf(float(hero.get("equipped_reward_bonus", 0.0)) + float(hero.get("perk_reward_bonus", 0.0)), 0.0, 1.5)
	combat_reward_bonus += maxf(0.0, float(floor_config.get("reward_multiplier", 1.0)) - 1.0)
	combat_reward_bonus += maxf(0.0, float(active_difficulty.get("reward_multiplier", 1.0)) - 1.0)
	combat_reward_bonus += maxf(0.0, float(get_run_modifier().get("reward_multiplier", 1.0)) - 1.0)
	var event_flags_value: Variant = run_ledger.get("event_flags", {})
	if typeof(event_flags_value) == TYPE_DICTIONARY and bool(event_flags_value.get("route_pulse", false)):
		combat_reward_bonus += 0.15
		var consumed_flags: Dictionary = event_flags_value.duplicate(true)
		consumed_flags.erase("route_pulse")
		run_ledger["event_flags"] = consumed_flags
		_log("Импульс цепочки событий усиливает награду следующего боя на 15%.")
	current_tile_spawn_bonus = strength_bonus
	if bool(enemy.get("is_boss", false)):
		_log("БОСС: %s. Особая атака «%s» срабатывает каждый %d-й удар." % [str(enemy.name), str(enemy.special_name), int(enemy.get("special_every", 3))])
	elif bool(enemy.get("is_elite", false)):
		_log("ЭЛИТА: %s · способность «%s». Усиленная атака будет предварительно обозначена." % [str(enemy.get("name", "Противник")), str(enemy.get("elite_ability", "Усиленный удар"))])
		if encounter_enemies.size() > 1:
			_log("Элитная цель возглавляет группу из %d противников." % encounter_enemies.size())
	elif encounter_enemies.size() > 1:
		_log("Группа противников (%d): цель — %s. Все враги атакуют независимо." % [encounter_enemies.size(), str(enemy.name)])
	else:
		_log("Столкновение: %s (опасность ×%.1f)." % [enemy.name, float(enemy.danger_rating)])
		_log("Тактика врага: %s." % str(enemy.get("behavior_hint", "обычная атака")))

func _rng_for_event() -> RandomNumberGenerator:
	return run_rng


func _get_current_landscape_tile_ids() -> Array[String]:
	var tile_ids: Array[String] = []
	for cell_value in world_tiles.keys():
		var tile_value: Variant = world_tiles[cell_value]
		if typeof(tile_value) != TYPE_DICTIONARY:
			continue
		var world_tile: Dictionary = tile_value
		if int(world_tile.get("route_index", -1)) != combat_cell:
			continue
		var tile_id := str(world_tile.get("id", ""))
		if not tile_id.is_empty() and not tile_ids.has(tile_id):
			tile_ids.append(tile_id)
	return tile_ids

func _get_biome_stat(enemy_data: Dictionary, stat_suffix: String) -> float:
	var tag := str(enemy_data.get("biome_tag", ""))
	if tag.is_empty():
		return 0.0
	var universal_key := "biome_damage_bonus" if stat_suffix == "damage_bonus" else "biome_resistance"
	var specific_key := tag + "_" + stat_suffix
	return maxf(0.0, float(hero.get(universal_key, 0.0)) + float(hero.get(specific_key, 0.0)))

func _tick_combat(delta: float) -> void:
	if enemy.is_empty() or encounter_enemies.is_empty() or pending_perk_count > 0:
		return
	combat_timers.hero = float(combat_timers.get("hero", 0.0)) + delta
	var status_events: Array[Dictionary] = status_effect_system.tick_effects(hero, delta)
	for status_event in status_events:
		if str(status_event.get("type", "")) == "damage":
			_log("Эффект «%s» наносит герою %d урона." % [str(status_event.get("name", "Статус")), int(status_event.get("amount", 0))])
		elif str(status_event.get("type", "")) == "expired":
			_log("Эффект «%s» закончился." % str(status_event.get("name", "Статус")))
	if int(hero.get("hp", 0)) <= 0:
		_log("Герой пал от периодического эффекта. Будет сохранена только часть добычи.")
		_finish_run("defeat")
		return
	for fighter_status_value in encounter_enemies:
		if typeof(fighter_status_value) != TYPE_DICTIONARY:
			continue
		var fighter_status: Dictionary = fighter_status_value
		var fighter_status_events: Array[Dictionary] = status_effect_system.tick_effects(fighter_status, delta)
		for fighter_status_event in fighter_status_events:
			if str(fighter_status_event.get("type", "")) == "damage":
				_log("Эффект «%s» наносит %s %d урона." % [str(fighter_status_event.get("name", "Статус")), str(fighter_status.get("name", "противнику")), int(fighter_status_event.get("amount", 0))])
			elif str(fighter_status_event.get("type", "")) == "expired":
				_log("Эффект «%s» на враге %s закончился." % [str(fighter_status_event.get("name", "Статус")), str(fighter_status.get("name", ""))])
	if not encounter_enemies.is_empty() and typeof(encounter_enemies[0]) == TYPE_DICTIONARY and int(encounter_enemies[0].get("hp", 0)) <= 0:
		enemy = encounter_enemies[0]
		_log("Периодический эффект добивает цель.")
		_on_victory()
		if not active or pending_perk_count > 0 or encounter_enemies.is_empty():
			return
	var speed_penalty := status_effect_system.get_modifier(hero, "attack_speed_penalty")
	var hero_interval := maxf(0.24, float(ContentRegistry.BALANCE.hero_attack_interval) / maxf(0.35, float(hero.get("attack_speed", 1.0)) * (1.0 - speed_penalty)))
	if float(combat_timers.hero) >= hero_interval:
		combat_timers.hero = float(combat_timers.hero) - hero_interval
		var player_attack_source: Dictionary = hero.duplicate(true)
		var elite_boss_bonus := clampf(float(hero.get("elite_boss_damage_bonus", 0.0)), 0.0, 0.25)
		if (bool(enemy.get("is_elite", false)) or bool(enemy.get("is_boss", false))) and elite_boss_bonus > 0.0:
			player_attack_source["attack"] = float(player_attack_source.get("attack", 1.0)) * (1.0 + elite_boss_bonus)
		var biome_bonus := clampf(_get_biome_stat(enemy, "damage_bonus"), 0.0, 0.35)
		var affinity_bonus_data: Dictionary = inventory_system.get_landscape_combat_bonus(equipment, _get_current_landscape_tile_ids(), enemy)
		var affinity_bonus := float(affinity_bonus_data.get("bonus", 0.0))
		var combined_biome_bonus := clampf(biome_bonus + affinity_bonus, 0.0, 0.35)
		if combined_biome_bonus > 0.0:
			player_attack_source["attack"] = float(player_attack_source.get("attack", 1.0)) * (1.0 + combined_biome_bonus)
		var player_hit: Dictionary = combat_system.perform_attack(player_attack_source, enemy, _rng_for_event())
		var lifesteal_ratio := clampf(float(hero.get("lifesteal", 0.0)), 0.0, 0.25)
		var stolen_health := mini(maxi(0, int(hero.get("max_hp", 1)) - int(hero.get("hp", 1))), int(floor(float(player_hit.get("damage", 0)) * lifesteal_ratio)))
		if stolen_health > 0:
			hero["hp"] = int(hero.get("hp", 1)) + stolen_health
			_log("Живой импульс возвращает %d здоровья." % stolen_health)
		var bleed_chance := clampf(float(hero.get("bleed_chance", 0.0)), 0.0, 0.5)
		if not bool(player_hit.get("defeated", false)) and bleed_chance > 0.0 and _rng_for_event().randf() < bleed_chance:
			var bleed_result: Dictionary = status_effect_system.apply_effect(enemy, "bleed", -1.0, float(maxi(1, int(hero.get("bleed_damage", 2)))), "equipment_weapon")
			if bool(bleed_result.get("ok", false)):
				_log("Оружие накладывает кровотечение на %s." % str(enemy.get("name", "противника")))
		if bool(player_hit.get("critical", false)):
			var exposed_result: Dictionary = status_effect_system.apply_effect(enemy, "exposed", -1.0, -1.0, "hero_critical")
			if bool(exposed_result.get("ok", false)):
				_log("Критический удар накладывает уязвимость: защита цели снижена на время эффекта.")
		var target_note := ""
		if combined_biome_bonus > 0.0:
			target_note = " · настройка против биома +%d%%" % int(round(combined_biome_bonus * 100.0))
		_log("Герой наносит %d урона%s цели «%s»%s." % [int(player_hit.damage), " — критический удар" if bool(player_hit.critical) else "", str(enemy.get("name", "противник")), target_note])
		if int(player_hit.get("absorbed", 0)) > 0:
			_log("Защитный барьер цели поглотил %d урона." % int(player_hit.get("absorbed", 0)))
		if not bool(player_hit.defeated):
			_update_boss_phase()
		if bool(player_hit.defeated):
			_on_victory()
			if not active or pending_perk_count > 0 or encounter_enemies.is_empty():
				return
	# Group fights are simultaneous: supporting enemies attack independently,
	# but their staggered opening timers reduce unavoidable burst damage.
	var attackers: Array = encounter_enemies.duplicate()
	for fighter_value in attackers:
		if not active or encounter_enemies.is_empty():
			return
		if typeof(fighter_value) != TYPE_DICTIONARY:
			continue
		var fighter: Dictionary = fighter_value
		if int(fighter.get("hp", 0)) <= 0:
			continue
		fighter["attack_timer"] = float(fighter.get("attack_timer", 0.0)) + delta
		var attack_slow := status_effect_system.get_modifier(fighter, "attack_speed_penalty")
		var enemy_interval := maxf(0.35, float(fighter.get("attack_interval", ContentRegistry.BALANCE.enemy_attack_interval)) * (1.0 + attack_slow))
		if float(fighter.get("attack_timer", 0.0)) < enemy_interval:
			continue
		fighter["attack_timer"] = float(fighter.get("attack_timer", 0.0)) - enemy_interval
		var role := str(fighter.get("role", ""))
		if role == "support" and encounter_enemies.size() > 1:
			var ally: Dictionary = _get_lowest_health_ally(fighter)
			if not ally.is_empty():
				var heal_amount := maxi(3, int(round(float(ally.get("max_hp", 1)) * 0.12)))
				var before_hp := int(ally.get("hp", 0))
				ally["hp"] = mini(int(ally.get("max_hp", before_hp)), before_hp + heal_amount)
				var healed := int(ally.get("hp", before_hp)) - before_hp
				if healed > 0:
					_log("%s поддерживает союзника: +%d здоровья." % [str(fighter.get("name", "Поддержка")), healed])
					continue
		var attack_source: Dictionary = fighter.duplicate(true)
		var is_boss_attacker := bool(fighter.get("is_boss", false))
		var is_elite_attacker := bool(fighter.get("is_elite", false))
		var next_attack_count := int(fighter.get("attack_count", 0)) + 1
		var cadence := maxi(1, int(fighter.get("special_every", 3)))
		var is_special := (is_boss_attacker or is_elite_attacker) and next_attack_count % cadence == 0
		if is_special and not bool(fighter.get("telegraph_pending", false)):
			fighter["telegraph_pending"] = true
			fighter["attack_timer"] = 0.0
			var telegraph_status_id := str(fighter.get("elite_ability_id", "")) if is_elite_attacker else str(fighter.get("special_effect_id", ""))
			var telegraph_resistance := clampf(float(hero.get(telegraph_status_id + "_resistance", 0.0)), 0.0, 0.25) if not telegraph_status_id.is_empty() else 0.0
			var counter_hint := ""
			if telegraph_resistance > 0.0:
				counter_hint = " · экипировка: %d%% шанс подавить статус «%s»" % [int(round(telegraph_resistance * 100.0)), str(ContentRegistry.STATUS_EFFECTS.get(telegraph_status_id, {}).get("name", telegraph_status_id))]
			_log("ПРЕДУПРЕЖДЕНИЕ: %s — %s%s" % [str(fighter.get("name", "Противник")), str(fighter.get("phase_telegraph", "готовит особую атаку")), counter_hint])
			continue
		fighter["attack_count"] = next_attack_count
		if is_special:
			fighter["telegraph_pending"] = false
			var special_multiplier := float(ContentRegistry.BALANCE.get("boss_special_multiplier", 1.65)) if is_boss_attacker else float(ContentRegistry.BALANCE.get("elite_special_multiplier", 1.50))
			attack_source.attack = float(attack_source.get("attack", 1.0)) * special_multiplier
			_log("%s применяет особую атаку «%s»!" % [str(fighter.get("name", "Противник")), str(fighter.get("special_name", "Усиленный удар"))])
		if role == "hunter" and float(hero.get("hp", 1)) / maxf(1.0, float(hero.get("max_hp", 1))) <= 0.35:
			attack_source["attack"] = float(attack_source.get("attack", 1.0)) * 1.35
			_log("Охотник замечает слабость героя и усиливает удар!")
		var special_guard := clampf(float(hero.get("special_damage_reduction", 0.0)), 0.0, 0.35)
		if is_special and special_guard > 0.0:
			attack_source["attack"] = float(attack_source.get("attack", 1.0)) * (1.0 - special_guard)
			_log("Экипировка рассеивает %d%% усиления особой атаки." % int(round(special_guard * 100.0)))
		var biome_resistance := clampf(_get_biome_stat(fighter, "resistance"), 0.0, 0.30)
		if biome_resistance > 0.0:
			attack_source["attack"] = float(attack_source.get("attack", 1.0)) * (1.0 - biome_resistance)
			if is_special or int(fighter.get("attack_count", 0)) == 1:
				_log("Экипировка смягчает удар биома «%s» на %d%%." % [str(fighter.get("biome_tag", "")), int(round(biome_resistance * 100.0))])
		var enemy_hit: Dictionary = combat_system.perform_attack(attack_source, hero, _rng_for_event())
		if bool(enemy_hit.get("dodged", false)):
			_log("Герой уходит в фазовый шаг и полностью избегает атаки %s." % str(fighter.get("name", "противника")))
			continue
		var hit_message := "%s наносит %d урона герою." % [str(fighter.get("name", "Противник")), int(enemy_hit.damage)]
		if int(enemy_hit.get("absorbed", 0)) > 0:
			hit_message += " Барьер поглотил %d." % int(enemy_hit.get("absorbed", 0))
		_log(hit_message)
		if int(enemy_hit.damage) > 0:
			_request_feedback("damage", "−%d здоровья" % int(enemy_hit.damage))
		if is_special and is_elite_attacker:
			var elite_status_id := str(fighter.get("elite_ability_id", ""))
			if not elite_status_id.is_empty():
				var elite_status_result: Dictionary = _apply_enemy_status_effect(elite_status_id, float(fighter.get("elite_effect_duration", 3.0)), float(fighter.get("elite_effect_magnitude", 0.0)), str(fighter.get("uid", "elite")))
				if bool(elite_status_result.get("ok", false)):
					_log("Элитная способность накладывает на героя эффект «%s»." % str(elite_status_result.get("name", elite_status_id)))
		if is_special and is_boss_attacker:
			var boss_effect_id := str(fighter.get("special_effect_id", "wound"))
			var boss_effect_result: Dictionary = _apply_enemy_status_effect(boss_effect_id, float(fighter.get("special_effect_duration", 4.0)), float(fighter.get("special_effect_magnitude", 0.12)), str(fighter.get("id", "boss")))
			if bool(boss_effect_result.get("ok", false)):
				var boss_effect_log := str(fighter.get("special_effect_log", "Особая атака босса накладывает эффект «%s»." % str(boss_effect_result.get("name", boss_effect_id))))
				_log(boss_effect_log)
		if role == "hunter" and int(fighter.get("attack_count", 0)) % 3 == 0 and not is_elite_attacker:
			var weakness_result: Dictionary = _apply_enemy_status_effect("weakness", 3.0, 0.18, str(fighter.get("id", "hunter")))
			if bool(weakness_result.get("ok", false)):
				_log("Охотник ослабляет ответный удар героя на время эффекта.")
		if role == "caster" and int(fighter.get("attack_count", 0)) % 3 == 0 and not is_elite_attacker:
			var applied_status: Dictionary = _apply_enemy_status_effect("distortion", float(ContentRegistry.BALANCE.get("enemy_caster_debuff_duration", 3.5)), float(ContentRegistry.BALANCE.get("enemy_caster_debuff", 0.18)), str(fighter.get("id", "caster")))
			if bool(applied_status.get("ok", false)):
				_log("Искажение замедляет атаки героя на %.1f секунды." % float(applied_status.get("duration", 3.5)))
		if int(hero.hp) <= 0:
			_log("Герой потерял сознание. Будет сохранена только часть добычи.")
			_finish_run("defeat")
			return

func _apply_enemy_status_effect(effect_id: String, duration: float, magnitude: float, source_id: String) -> Dictionary:
	var resistance := clampf(float(hero.get(effect_id + "_resistance", 0.0)), 0.0, 0.25)
	if resistance > 0.0 and _rng_for_event().randf() < resistance:
		var definition: Dictionary = ContentRegistry.STATUS_EFFECTS.get(effect_id, {})
		var effect_name := str(definition.get("name", effect_id))
		_log("Контр-экипировка подавляет эффект «%s» (%d%% шанс сопротивления)." % [effect_name, int(round(resistance * 100.0))])
		return {"ok": false, "resisted": true, "reason": "equipment_resisted", "id": effect_id, "name": effect_name}
	return status_effect_system.apply_effect(hero, effect_id, duration, magnitude, source_id)

func _update_boss_phase() -> void:
	if enemy.is_empty() or not bool(enemy.get("is_boss", false)):
		return
	var phases_value: Variant = enemy.get("phases", [])
	if typeof(phases_value) != TYPE_ARRAY:
		return
	var phases: Array = phases_value
	var current_phase := int(enemy.get("phase_index", 0))
	var next_phase := current_phase + 1
	if next_phase >= phases.size() or typeof(phases[next_phase]) != TYPE_DICTIONARY:
		return
	var phase: Dictionary = phases[next_phase]
	var hp_ratio := float(enemy.get("hp", 0)) / maxf(1.0, float(enemy.get("max_hp", 1)))
	if hp_ratio > float(phase.get("threshold", 0.0)):
		return
	enemy["phase_index"] = next_phase
	enemy["phase_name"] = str(phase.get("name", "Фаза %d" % (next_phase + 1)))
	enemy["phase_telegraph"] = str(phase.get("telegraph", "готовит особую атаку"))
	enemy["attack"] = float(enemy.get("base_attack", enemy.get("attack", 1.0))) * float(phase.get("attack_multiplier", 1.0))
	enemy["defense"] = int(enemy.get("base_defense", enemy.get("defense", 0))) + int(phase.get("defense_bonus", 0))
	enemy["attack_interval"] = maxf(0.55, float(phase.get("attack_interval", 1.1)))
	var cadence_bonus := int(GameState.get_unlock_effect("boss_special_cadence_bonus"))
	enemy["special_every"] = maxi(2, int(phase.get("special_every", 3)) + cadence_bonus)
	enemy["telegraph_pending"] = false
	var phase_effect_value: Variant = phase.get("status_on_enter", {})
	if typeof(phase_effect_value) == TYPE_DICTIONARY and not phase_effect_value.is_empty():
		var phase_effect: Dictionary = phase_effect_value
		var phase_effect_id := str(phase_effect.get("id", ""))
		var effect_target: Dictionary = hero if str(phase_effect.get("target", "boss")) == "hero" else enemy
		if not phase_effect_id.is_empty():
			var phase_status_result: Dictionary
			if effect_target == hero:
				phase_status_result = _apply_enemy_status_effect(phase_effect_id, float(phase_effect.get("duration", 3.0)), float(phase_effect.get("magnitude", 0.0)), str(enemy.get("id", "boss_phase")))
			else:
				phase_status_result = status_effect_system.apply_effect(effect_target, phase_effect_id, float(phase_effect.get("duration", 3.0)), float(phase_effect.get("magnitude", 0.0)), str(enemy.get("id", "boss_phase")))
			if bool(phase_status_result.get("ok", false)):
				var target_label := "героя" if effect_target == hero else "босса"
				_log("Фаза накладывает на %s эффект «%s»." % [target_label, str(phase_status_result.get("name", phase_effect_id))])
	_log("ФАЗА БОССА: %s. %s" % [str(enemy.phase_name), str(enemy.phase_telegraph)])
	_request_feedback("boss", str(enemy.phase_name))
	changed.emit()
	save_run_snapshot()

func _get_lowest_health_ally(source: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_ratio := 1.0
	for member_value in encounter_enemies:
		if typeof(member_value) != TYPE_DICTIONARY:
			continue
		var member: Dictionary = member_value
		if member == source or int(member.get("hp", 0)) <= 0:
			continue
		var ratio := float(member.get("hp", 0)) / maxf(1.0, float(member.get("max_hp", 1)))
		if ratio < best_ratio:
			best_ratio = ratio
			best = member
	return best

func _on_victory() -> void:
	if enemy.is_empty():
		return
	var defeated_enemy := enemy.duplicate(true)
	var is_boss := bool(defeated_enemy.get("is_boss", false))
	var is_elite := bool(defeated_enemy.get("is_elite", false)) and not is_boss
	var reward_bonus := combat_reward_bonus + (float(ContentRegistry.BALANCE.get("boss_reward_bonus", 0.60)) if is_boss else 0.0)
	if is_elite:
		reward_bonus += float(ContentRegistry.BALANCE.get("elite_reward_bonus", 0.40))
	var trophy_rng := _rng_for_event()
	var defeated_biome := str(defeated_enemy.get("biome_tag", ""))
	var contextual_trophy_bonus := clampf(float(hero.get("equipped_" + defeated_biome + "_trophy_bonus", 0.0)), 0.0, 0.12)
	var trophy: Dictionary = loot_system.roll_biome_trophy(defeated_enemy, trophy_rng, _get_current_landscape_tile_ids(), float(hero.get("equipped_trophy_find_bonus", 0.0)), contextual_trophy_bonus)
	var reward: Dictionary = loot_system.roll_victory(defeated_enemy, loop_count, trophy_rng, reward_bonus)
	resource_system.add(run_ledger, "scrap", int(reward.scrap))
	resource_system.add(run_ledger, "crystals", int(reward.crystals))
	if not trophy.is_empty():
		var trophy_counts := _normalize_trophy_counts(run_ledger.get("trophy_drops", {}))
		var trophy_id := str(trophy.get("material_id", ""))
		var trophy_amount := clampi(int(trophy.get("amount", 1)), 1, 3)
		if trophy_counts.has(trophy_id):
			trophy_counts[trophy_id] = mini(1000000, int(trophy_counts[trophy_id]) + trophy_amount)
			run_ledger["trophy_drops"] = trophy_counts
			match str(trophy.get("biome_tag", "")):
				"spore":
					var trophy_heal := _scale_healing(2 * trophy_amount)
					var missing_hp := maxi(0, int(hero.get("max_hp", 0)) - int(hero.get("hp", 0)))
					var actual_trophy_heal := mini(missing_hp, trophy_heal)
					if actual_trophy_heal > 0:
						hero["hp"] = mini(int(hero.get("max_hp", 1)), int(hero.get("hp", 0)) + actual_trophy_heal)
						_log("Трофей «%s» восстановил %d здоровья." % [str(trophy.get("name", "Пыльца")), actual_trophy_heal])
				"crystal":
					resource_system.add(run_ledger, "crystals", trophy_amount)
					_log("ТРОФЕЙ: %s ×%d · +%d кристалл(ов)." % [str(trophy.get("name", "Осколок призмы")), trophy_amount, trophy_amount])
				"bone":
					resource_system.add(run_ledger, "scrap", trophy_amount)
					_log("ТРОФЕЙ: %s ×%d · +%d материала." % [str(trophy.get("name", "Фрагмент")), trophy_amount, trophy_amount])
				"echo":
					run_ledger["echo_item_charges"] = clampi(int(run_ledger.get("echo_item_charges", 0)) + trophy_amount, 0, 4)
					_log("ТРОФЕЙ: %s ×%d · шанс находки повышен до следующего предмета." % [str(trophy.get("name", "Остаток эха")), trophy_amount])
			if bool(trophy.get("focused_by_landscape", false)):
				_log("Родной ландшафт усилил трофей: шанс выпадения был повышен.")
	run_ledger.victories = int(run_ledger.get("victories", 0)) + 1
	GameState.record_victory()
	if is_boss:
		run_ledger.bosses_defeated = int(run_ledger.get("bosses_defeated", 0)) + 1
		GameState.record_boss_victory()
		_log("БОСС ПОВЕРЖЕН: +%d материалов, +%d редких ресурсов и гарантированная экипировка." % [int(reward.scrap), int(reward.crystals)])
	elif is_elite:
		run_ledger["elites_defeated"] = int(run_ledger.get("elites_defeated", 0)) + 1
		GameState.record_elite_victory()
		_log("ЭЛИТНЫЙ ПРОТИВНИК ПОВЕРЖЕН: повышенная добыча +%d материалов и +%d редких ресурсов." % [int(reward.scrap), int(reward.crystals)])
	else:
		_log("Победа: +%d материалов, +%d редкого ресурса, +%d опыта." % [int(reward.scrap), int(reward.crystals), int(reward.xp)])
	_update_objective_progress()
	_maybe_add_tile("Награда за бой", 0.28)
	var kill_heal: int = _scale_healing(clampi(int(hero.get("equipped_kill_heal", 0)) + int(hero.get("perk_kill_heal_bonus", 0)), 0, 10))
	if kill_heal > 0:
		var actual_kill_heal: int = mini(kill_heal, maxi(0, int(hero.get("max_hp", 0)) - int(hero.get("hp", 0))))
		hero["hp"] = mini(int(hero.get("max_hp", 1)), int(hero.get("hp", 0)) + kill_heal)
		if actual_kill_heal > 0:
			_log("Эффект оружия восстановил %d здоровья после победы." % actual_kill_heal)
	var xp_levels: int = progression_system.add_experience(hero, int(reward.xp))
	if xp_levels > 0:
		_request_feedback("level", "Уровень %d" % int(hero.get("level", 1)))
		pending_perk_count += xp_levels
		_prepare_perk_choice()
	var drop_rng := _rng_for_event()
	var echo_charges := clampi(int(run_ledger.get("echo_item_charges", 0)), 0, 4)
	var pending_drop_bonus := clampf(float(run_ledger.get("pending_item_drop_bonus", 0.0)), 0.0, 0.30)
	var drop_source := "boss" if is_boss else ("elite" if is_elite else "enemy")
	var item_chance: float = loot_system.get_equipment_drop_chance(drop_source, combat_reward_bonus, echo_charges, pending_drop_bonus)
	var pending_rarity_bonus := clampf(float(run_ledger.get("pending_item_rarity_bonus", 0.0)), 0.0, 0.18)
	var equipped_rarity_bonus := clampf(float(hero.get("equipped_rare_find_bonus", 0.0)), 0.0, 0.12)
	var source_quality_bonus: float = 0.0 if is_boss else loot_system.get_source_rarity_bonus(drop_source)
	var effective_rarity_bonus: float = inventory_system.get_effective_rarity_bonus(equipped_rarity_bonus, pending_rarity_bonus, source_quality_bonus)
	if drop_rng.randf() < item_chance:
		if not is_boss and echo_charges > 0:
			run_ledger["echo_item_charges"] = maxi(0, echo_charges - 1)
		var item: Dictionary = inventory_system.roll_boss_item(defeated_enemy, drop_rng, loop_count, int(hero.level)) if is_boss else {}
		if item.is_empty():
			var boss_rarity_bonus: float = 0.0 if is_boss else effective_rarity_bonus
			item = inventory_system.roll_item(drop_rng, loop_count, int(hero.level), boss_rarity_bonus)
		if not is_boss:
			# Prepared road-card bonuses are consumed only when an ordinary/elite
			# equipment drop actually succeeds, never by a failed chance roll.
			run_ledger["pending_item_rarity_bonus"] = 0.0
			run_ledger["pending_item_drop_bonus"] = 0.0
		# Unknown boss profiles retain generic boss gear; registered bosses use
		# named relics with signature stats and a linked two-piece set.
		if is_boss and not bool(item.get("is_boss_relic", false)):
			item["rarity"] = "Боссовая"
			item["name"] = "%s · Награда за босса" % str(item.get("name", "Предмет"))
			for stat_key in ["attack", "defense", "hp"]:
				var stat_value := int(item.get(stat_key, 0))
				if stat_value > 0:
					item[stat_key] = maxi(1, int(ceil(float(stat_value) * 1.25)))
			item["speed"] = minf(0.24, float(item.get("speed", 0.0)) * 1.20)
			item["crit"] = minf(0.20, float(item.get("crit", 0.0)) * 1.20)
		elif is_elite:
			# Elites increase both drop reliability and quality bias, but do not
			# force every item into a separate rarity tier. Preserve its actual
			# Common/Rare/Epic/Relic roll and apply a separate 10% stat premium.
			item["name"] = "%s · Трофей элиты" % str(item.get("name", "Предмет"))
			for stat_key in ["attack", "defense", "hp"]:
				var elite_stat_value := int(item.get(stat_key, 0))
				if elite_stat_value > 0:
					item[stat_key] = maxi(1, int(ceil(float(elite_stat_value) * 1.10)))
		item["power"] = inventory_system.item_power(item)
		item["drop_source"] = drop_source
		if _store_run_item(item):
			var slot_label := inventory_system.slot_name(str(item.get("slot", "")))
			var item_kind := "ИМЕННАЯ РЕЛИКВИЯ БОССА" if bool(item.get("is_boss_relic", false)) else "НАЙДЕН ПРЕДМЕТ"
			if is_boss:
				var boss_item_label := "Именная реликвия" if bool(item.get("is_boss_relic", false)) else "Боссовая экипировка"
				_log("%s: %s · %s. %s — гарантированная награда босса; обычная шкала редкости для неё не используется. Предмет помещён в ячейку 01." % [item_kind, str(item.get("name", "Предмет")), slot_label, boss_item_label])
			else:
				var rarity_distribution: Dictionary = inventory_system.get_rarity_distribution(0.0 if is_boss else effective_rarity_bonus)
				var rolled_rarity := str(item.get("rarity", "Обычный"))
				var rolled_rarity_chance := float(rarity_distribution.get(rolled_rarity, 0.0))
				_log("%s: %s · %s. Шанс предмета: %d%%; шанс качества «%s» при текущей подготовке: %.1f%%. Предмет в ячейку 01 — решайте, экипировать ли." % [item_kind, str(item.get("name", "Предмет")), slot_label, int(round(item_chance * 100.0)), rolled_rarity.to_lower(), rolled_rarity_chance * 100.0])
			if not last_inventory_evicted_item.is_empty():
				_log("РЮКЗАК ПЕРЕПОЛНЕН: вытеснен старейший предмет «%s» из ячейки 12." % str(last_inventory_evicted_item.get("name", "Старая вещь")))
		else:
			_log("НАЙДЕН ПРЕДМЕТ: %s не удалось поместить в текущий рюкзак; коллекция убежища остаётся нетронутой." % str(item.get("name", "Предмет")))
		_request_feedback("loot", str(item.get("name", "Предмет найден")))
	else:
		_log("Предмет не выпал: шанс экипировки для этой победы составлял %d%%. Шанс редкости не бросался, поскольку предмета нет." % int(round(item_chance * 100.0)))
	# Remove only the focused target. Remaining members keep their attack timers
	# and continue the same battle; no extra rewards are granted for the target swap.
	if not encounter_enemies.is_empty():
		encounter_enemies.pop_front()
	if not encounter_enemies.is_empty():
		enemy = encounter_enemies[0]
		_log("Следующая цель: %s. Осталось противников: %d." % [str(enemy.get("name", "Противник")), encounter_enemies.size()])
	else:
		enemy.clear()
		encounter_enemies.clear()
		combat_cell = -1
		combat_reward_bonus = 0.0
		current_tile_spawn_bonus = 0.0
		_maybe_finish_long_expedition()
	changed.emit()
	if active:
		save_run_snapshot()

func get_tile_exchange_preview(hand_index: int) -> Dictionary:
	if not active:
		return {"ok": false, "reason": "Переписывать карты можно только во время экспедиции."}
	if not pending_end_outcome.is_empty():
		return {"ok": false, "reason": "Сначала завершите сохранение итогов экспедиции."}
	if not enemy.is_empty() or not pending_event.is_empty() or pending_perk_count > 0:
		return {"ok": false, "reason": "В бою и во время текущего решения карты переписывать нельзя."}
	if hand_index < 0 or hand_index >= tile_hand.size():
		return {"ok": false, "reason": "Сначала выберите карту в руке."}
	if int(run_ledger.get("last_tile_exchange_loop", -1)) == loop_count:
		return {"ok": false, "reason": "Картограф уже переписал одну карту в этом цикле."}
	if int(run_ledger.get("crystals", 0)) < 1:
		return {"ok": false, "reason": "Для переписывания карты нужен 1 кристалл."}
	var tile_value: Variant = tile_hand[hand_index]
	if typeof(tile_value) != TYPE_DICTIONARY or str(tile_value.get("id", "")).is_empty():
		return {"ok": false, "reason": "Выбранная карта повреждена; обмен отменён."}
	return {"ok": true, "reason": "Можно переписать карту за 1 кристалл. Один обмен на цикл.", "cost_crystals": 1, "tile_name": str(tile_value.get("name", "Тайл"))}

func exchange_tile(hand_index: int) -> Dictionary:
	var availability := get_tile_exchange_preview(hand_index)
	if not bool(availability.get("ok", false)):
		return availability
	var previous_hand := tile_hand.duplicate(true)
	var previous_ledger := run_ledger.duplicate(true)
	var previous_rng_state := run_rng.state
	var previous_event_log := event_log.duplicate(true)
	var old_tile: Dictionary = tile_hand[hand_index].duplicate(true)
	var old_tile_id := str(old_tile.get("id", ""))
	run_ledger["crystals"] = maxi(0, int(run_ledger.get("crystals", 0)) - 1)
	run_ledger["last_tile_exchange_loop"] = loop_count
	var unlock_rare := loop_count >= 3 or GameState.get_unlock_effect("unlock_rare_tiles") > 0.0
	var new_tile: Dictionary = tile_system.draw_tile(run_rng, unlock_rare, [old_tile_id])
	if str(new_tile.get("id", "")) == old_tile_id:
		# Fail closed if the eligible pool ever changes to contain only one card.
		run_ledger = previous_ledger
		run_rng.state = previous_rng_state
		return {"ok": false, "reason": "Нет другой доступной карты для обмена."}
	tile_hand[hand_index] = new_tile
	_log("Картограф переписал «%s» в «%s»: потрачен 1 кристалл. Повторный обмен будет доступен в следующем цикле." % [str(old_tile.get("name", old_tile_id)), str(new_tile.get("name", new_tile.get("id", "Тайл")))])
	if not save_run_snapshot():
		tile_hand = previous_hand
		run_ledger = previous_ledger
		run_rng.state = previous_rng_state
		event_log = previous_event_log
		_log("Обмен карты отменён: новое состояние не удалось надёжно сохранить. Кристалл возвращён.")
		changed.emit()
		return {"ok": false, "reason": "Не удалось сохранить обмен; карта и кристалл восстановлены."}
	changed.emit()
	return {"ok": true, "reason": "«%s» заменён на «%s». Потрачен 1 кристалл." % [str(old_tile.get("name", old_tile_id)), str(new_tile.get("name", new_tile.get("id", "Тайл")))], "old_tile": old_tile, "new_tile": new_tile}

func _maybe_add_tile(source: String, chance: float) -> void:
	if tile_hand.size() >= get_tile_hand_limit():
		return
	if run_rng.randf() < clampf(chance, 0.0, 1.0):
		var new_tile: Dictionary = tile_system.draw_tile(run_rng, loop_count >= 3 or GameState.get_unlock_effect("unlock_rare_tiles") > 0.0)
		tile_hand.append(new_tile)
		_log("%s: получен тайл «%s»." % [source, str(new_tile.name)])

func _prepare_perk_choice() -> void:
	while pending_perk_count > 0:
		pending_perk_choices = progression_system.make_perk_choices(_rng_for_event(), hero)
		if not pending_perk_choices.is_empty():
			_log("Уровень повышен до %d. Выберите одно улучшение." % int(hero.level))
			return
		# Safe fallback for an extreme long run where all perk stacks are capped.
		pending_perk_count -= 1
		hero["attack_bonus"] = int(hero.get("attack_bonus", 0)) + 1
		_sync_hero_stats()
		_log("Все навыки достигли предела: вместо выбора получен +1 к атаке.")
	pending_perk_choices.clear()

func choose_perk(perk_id: String) -> bool:
	if not pending_end_outcome.is_empty():
		return false
	if pending_perk_count <= 0 or not pending_perk_choices.has(perk_id):
		return false
	var perk: Dictionary = ContentRegistry.PERKS[perk_id]
	progression_system.apply_perk(hero, perk_id)
	pending_perk_count -= 1
	_sync_hero_stats()
	_log("Выбрано улучшение: %s." % str(perk.name))
	if pending_perk_count > 0:
		_prepare_perk_choice()
	else:
		pending_perk_choices.clear()
		_maybe_finish_long_expedition()
	changed.emit()
	if active:
		save_run_snapshot()
	return true

func _sync_hero_stats() -> void:
	if hero.is_empty():
		return
	var perk_counts_value: Variant = hero.get("perk_counts", {})
	var perk_counts: Dictionary = perk_counts_value if typeof(perk_counts_value) == TYPE_DICTIONARY else {}
	var build: Dictionary = inventory_system.calculate_loadout_stats(equipment, perk_counts)
	var equipment_stats: Dictionary = build.get("equipment", {})
	var perk_stats: Dictionary = build.get("perks", {})
	var combined_stats: Dictionary = build.get("combined", {})
	var old_max := int(hero.get("max_hp", 1))
	# Older snapshots store perk totals directly in *_bonus. Subtract the
	# calculated perk contribution before adding the combined result so those
	# snapshots remain compatible while current derived values come from counts.
	var legacy_attack_bonus := int(hero.get("attack_bonus", 0)) - int(perk_stats.get("attack", 0))
	var legacy_hp_bonus := int(hero.get("hp_bonus", 0)) - int(perk_stats.get("hp", 0))
	var legacy_defense_bonus := int(hero.get("defense_bonus", 0)) - int(perk_stats.get("defense", 0))
	var legacy_speed_bonus := float(hero.get("speed_bonus", 0.0)) - float(perk_stats.get("speed", 0.0))
	var legacy_crit_bonus := float(hero.get("crit_bonus", 0.0)) - float(perk_stats.get("crit", 0.0))
	hero.max_hp = maxi(1, int(hero.get("base_hp", ContentRegistry.BALANCE.base_hp)) + legacy_hp_bonus + int(combined_stats.get("hp", 0)))
	hero.attack = maxi(0, int(hero.get("base_attack", ContentRegistry.BALANCE.base_attack)) + legacy_attack_bonus + int(combined_stats.get("attack", 0)))
	hero.defense = maxi(0, int(hero.get("base_defense", ContentRegistry.BALANCE.base_defense)) + legacy_defense_bonus + int(combined_stats.get("defense", 0)))
	hero.attack_speed = clampf(1.0 + legacy_speed_bonus + float(combined_stats.get("speed", 0.0)), 0.5, 2.5)
	hero.crit = clampf(0.05 + legacy_crit_bonus + float(combined_stats.get("crit", 0.0)), 0.0, 0.75)
	# Combat, reward and exploration systems read these dedicated legacy-facing
	# fields; rebuild them from the same calculators rather than incrementing them.
	hero["equipped_kill_heal"] = int(equipment_stats.get("kill_heal", 0))
	hero["equipped_tile_scrap"] = int(equipment_stats.get("tile_scrap", 0))
	hero["equipped_event_heal"] = int(equipment_stats.get("event_heal", 0))
	hero["equipped_reward_bonus"] = float(equipment_stats.get("reward_bonus", 0.0))
	hero["equipped_tile_spawn_bonus"] = float(equipment_stats.get("tile_spawn_bonus", 0.0))
	hero["perk_kill_heal_bonus"] = int(perk_stats.get("kill_heal", 0))
	hero["perk_tile_scrap_bonus"] = int(perk_stats.get("tile_scrap", 0))
	hero["perk_event_heal_bonus"] = int(perk_stats.get("event_heal", 0))
	hero["perk_reward_bonus"] = float(perk_stats.get("reward_bonus", 0.0))
	hero["perk_tile_spawn_bonus"] = float(perk_stats.get("tile_spawn_bonus", 0.0))
	hero["bleed_chance"] = clampf(float(equipment_stats.get("bleed_chance", 0.0)), 0.0, 0.5)
	hero["bleed_damage"] = clampi(int(equipment_stats.get("bleed_damage", 0)), 0, 100)
	hero["barrier_on_encounter"] = clampi(int(equipment_stats.get("barrier_on_encounter", 0)), 0, 100)
	hero["lifesteal"] = clampf(float(equipment_stats.get("lifesteal", 0.0)), 0.0, 0.25)
	hero["dodge_chance"] = clampf(float(equipment_stats.get("dodge_chance", 0.0)), 0.0, 0.25)
	hero["special_damage_reduction"] = clampf(float(equipment_stats.get("special_damage_reduction", 0.0)), 0.0, 0.35)
	hero["elite_boss_damage_bonus"] = clampf(float(equipment_stats.get("elite_boss_damage_bonus", 0.0)), 0.0, 0.25)
	hero["biome_damage_bonus"] = clampf(float(equipment_stats.get("biome_damage_bonus", 0.0)), 0.0, 0.20)
	hero["biome_resistance"] = clampf(float(equipment_stats.get("biome_resistance", 0.0)), 0.0, 0.20)
	hero["equipped_trophy_find_bonus"] = clampf(float(equipment_stats.get("trophy_find_bonus", 0.0)), 0.0, 0.25)
	for trophy_biome in ["spore", "crystal", "bone", "echo"]:
		hero["equipped_" + trophy_biome + "_trophy_bonus"] = clampf(float(equipment_stats.get(trophy_biome + "_trophy_bonus", 0.0)), 0.0, 0.12)
	hero["equipped_rare_find_bonus"] = clampf(float(equipment_stats.get("rare_find_bonus", 0.0)), 0.0, 0.12)
	for status_id in ["poison", "bleed", "wound", "distortion", "weakness"]:
		hero[status_id + "_resistance"] = clampf(float(equipment_stats.get(status_id + "_resistance", 0.0)), 0.0, 0.25)
	for biome_tag in ["spore", "crystal", "bone", "echo"]:
		hero[biome_tag + "_damage_bonus"] = clampf(float(equipment_stats.get(biome_tag + "_damage_bonus", 0.0)), 0.0, 0.25)
		hero[biome_tag + "_resistance"] = clampf(float(equipment_stats.get(biome_tag + "_resistance", 0.0)), 0.0, 0.20)
	hero["equipment_sets"] = equipment_stats.get("active_sets", []).duplicate(true)
	hero["equipment_synergies"] = equipment_stats.get("active_synergies", []).duplicate(true)
	if int(hero.max_hp) > old_max:
		hero.hp = mini(int(hero.max_hp), int(hero.get("hp", old_max)) + int(hero.max_hp) - old_max)
	else:
		hero.hp = mini(int(hero.max_hp), int(hero.get("hp", 1)))

func place_tile(hand_index: int, cell_index: int) -> Dictionary:
	if not pending_end_outcome.is_empty():
		return {"ok": false, "reason": "Сначала повторите сохранение итогов экспедиции."}
	if not active:
		return {"ok": false, "reason": "Экспедиция не активна."}
	if not enemy.is_empty():
		return {"ok": false, "reason": "Во время боя размещение временно недоступно."}
	if not pending_event.is_empty() or pending_perk_count > 0:
		return {"ok": false, "reason": "Сначала завершите текущее решение."}
	if hand_index < 0 or hand_index >= tile_hand.size():
		return {"ok": false, "reason": "Выберите тайл из руки."}
	var tile: Dictionary = tile_hand[hand_index].duplicate(true)
	var can_place: Dictionary = tile_system.can_place(route, placed_tiles, cell_index, tile)
	if not bool(can_place.get("ok", false)):
		return can_place
	# Placement is a small transaction: never report success until the new hand
	# and board state are durably snapshotted.
	var previous_hand: Array = tile_hand.duplicate(true)
	var previous_placed_tiles: Dictionary = placed_tiles.duplicate(true)
	var previous_event_log: Array = event_log.duplicate(true)
	placed_tiles[str(cell_index)] = tile
	tile_hand.remove_at(hand_index)
	_log("Размещён тайл «%s» на дорожном узле %d. Рука теперь содержит %d тайла(ов)." % [str(tile.get("name", "Тайл")), cell_index + 1, tile_hand.size()])
	if not save_run_snapshot():
		tile_hand = previous_hand
		placed_tiles = previous_placed_tiles
		event_log = previous_event_log
		return {"ok": false, "reason": "Не удалось сохранить размещение. Карта возвращена в руку, поле восстановлено."}
	changed.emit()
	return {"ok": true, "reason": "Тайл размещён на дорожном узле.", "tile": tile}

func place_world_tile(hand_index: int, cell_id: String) -> Dictionary:
	if not pending_end_outcome.is_empty():
		return {"ok": false, "reason": "Сначала повторите сохранение итогов экспедиции."}
	if not active:
		return {"ok": false, "reason": "Экспедиция не активна."}
	if not enemy.is_empty():
		return {"ok": false, "reason": "Во время боя размещение временно недоступно."}
	if not pending_event.is_empty() or pending_perk_count > 0:
		return {"ok": false, "reason": "Сначала завершите текущее решение."}
	if hand_index < 0 or hand_index >= tile_hand.size():
		return {"ok": false, "reason": "Выберите тайл из руки."}
	var tile: Dictionary = tile_hand[hand_index].duplicate(true)
	var placement: Dictionary = tile_system.can_place_world(route, world_tiles, cell_id, tile, get_route_shape_id(), get_route_geometry_seed())
	if not bool(placement.get("ok", false)):
		return placement
	var previous_hand: Array = tile_hand.duplicate(true)
	var previous_world_tiles: Dictionary = world_tiles.duplicate(true)
	var previous_discovered_cells: Dictionary = discovered_world_cells.duplicate(true)
	var previous_event_log: Array = event_log.duplicate(true)
	var field_coord: Vector2i = TileSystemScript.world_cell_coordinates(cell_id)
	tile["field_x"] = field_coord.x
	tile["field_y"] = field_coord.y
	tile["field_schema"] = 3 if TileSystemScript.is_map_world_cell_id(cell_id) else 2
	tile["route_index"] = int(placement.get("route_index", -1))
	world_tiles[cell_id] = tile
	if TileSystemScript.is_map_world_cell_id(cell_id):
		discovered_world_cells[cell_id] = true
	tile_hand.remove_at(hand_index)
	_log("Тайл «%s» размещён на ландшафте (%d, %d), сектор маршрута %d." % [str(tile.get("name", "Тайл")), int(tile.field_x) + 1, int(tile.field_y) + 1, int(tile.route_index) + 1])
	if not save_run_snapshot():
		tile_hand = previous_hand
		world_tiles = previous_world_tiles
		discovered_world_cells = previous_discovered_cells
		event_log = previous_event_log
		return {"ok": false, "reason": "Не удалось сохранить размещение. Карта возвращена в руку, ландшафт восстановлен."}
	changed.emit()
	return {"ok": true, "reason": "Тайл размещён на ландшафте.", "tile": tile, "route_index": int(tile.route_index)}

func set_pause(value: bool) -> void:
	if not pending_end_outcome.is_empty() and not value:
		return
	paused = value
	_log("Экспедиция поставлена на паузу." if paused else "Экспедиция продолжается.")
	changed.emit()
	save_run_snapshot()

func set_speed(value: float) -> void:
	if not pending_end_outcome.is_empty():
		return
	speed = clampf(value, 1.0, 3.0)
	changed.emit()
	save_run_snapshot()

func end_run(outcome: String = "return") -> void:
	if not active:
		return
	# Once an end-of-run transaction failed, a later UI action may retry it but
	# cannot convert a defeat into a voluntary return (or vice versa).
	if not pending_end_outcome.is_empty():
		outcome = pending_end_outcome
	_finish_run(outcome)

func _collect_run_items_for_settlement(outcome: String) -> Array:
	var collected: Array = []
	var seen_ids: Dictionary = {}
	# Equipped items survive defeat because they define the finalized loadout.
	for slot_value in InventorySystemScript.EQUIPMENT_SLOTS:
		var equipped_value: Variant = equipment.get(str(slot_value), {})
		if typeof(equipped_value) != TYPE_DICTIONARY:
			continue
		var equipped_item: Dictionary = equipped_value
		var equipped_id := str(equipped_item.get("id", ""))
		if equipped_id.is_empty() or seen_ids.has(equipped_id) or not inventory_system.can_equip_item(equipped_item, str(slot_value)):
			continue
		seen_ids[equipped_id] = true
		collected.append(equipped_item.duplicate(true))
	# On a safe return, the still-carried backpack items are banked too. On defeat,
	# un-equipped backpack items are lost; ejected items are never eligible to bank.
	if outcome == "return":
		for bag_item_value in bag:
			if typeof(bag_item_value) != TYPE_DICTIONARY:
				continue
			var bag_item: Dictionary = bag_item_value
			var bag_item_id := str(bag_item.get("id", ""))
			if bag_item_id.is_empty() or seen_ids.has(bag_item_id) or not inventory_system.can_equip_item(bag_item):
				continue
			seen_ids[bag_item_id] = true
			collected.append(bag_item.duplicate(true))
	return collected

func _finish_run(outcome: String) -> void:
	if not active:
		return
	if pending_end_outcome.is_empty():
		pending_end_outcome = outcome if outcome in ["return", "defeat"] else "defeat"
	outcome = pending_end_outcome
	_update_challenge_progress()
	active = false
	paused = false
	var active_difficulty: Dictionary = ContentRegistry.DIFFICULTY_PRESETS.get(difficulty_id, ContentRegistry.DIFFICULTY_PRESETS["standard"])
	var floor_config: Dictionary = get_floor_config()
	var defeat_keep_ratio := clampf(float(floor_config.get("defeat_keep_ratio", active_difficulty.get("defeat_keep_ratio", ContentRegistry.BALANCE.get("defeat_keep_ratio", 0.4))), 0.0, 1.0)
	# Build every durable result field before the settlement transaction. Rewards,
	# checkpoint deletion, campaign journal and difficulty record must become durable
	# together, so a crash cannot consume rewards but lose the replay summary.
	var run_event_history_value: Variant = run_ledger.get("event_history", [])
	var run_event_history: Array = run_event_history_value.duplicate(true) if typeof(run_event_history_value) == TYPE_ARRAY else []
	var endgame_goal: Dictionary = get_expedition_goal_progress()
	var raw_score := loop_count * 10 + int(run_ledger.get("victories", 0)) * 2 + int(run_ledger.get("bosses_defeated", 0)) * 40 + int(run_ledger.get("elites_defeated", 0)) * 15 + int(run_ledger.get("events_resolved", 0)) * 3
	if bool(run_challenge.get("completed", false)):
		raw_score += 20
	if bool(run_contract.get("completed", false)) and not bool(run_contract.get("failed", false)):
		raw_score += 15
	if bool(run_ledger.get("endgame_completed", false)):
		raw_score += 250
	if outcome == "return":
		raw_score += 15
	var challenge_score := maxi(0, int(floor(float(raw_score) * maxf(1.0, float(active_difficulty.get("challenge_score_multiplier", 1.0))))))
	var recent_tile_names: Array[String] = []
	for tile_value in world_tiles.values():
		if typeof(tile_value) != TYPE_DICTIONARY:
			continue
		var tile_name := str(tile_value.get("name", tile_value.get("id", "Тайл")))
		if not recent_tile_names.has(tile_name) and recent_tile_names.size() < 5:
			recent_tile_names.append(tile_name)
	var recent_decisions: Array[String] = []
	for history_value in run_event_history:
		if typeof(history_value) != TYPE_DICTIONARY:
			continue
		recent_decisions.append("%s → %s" % [str(history_value.get("event", "Событие")), str(history_value.get("choice", "Решение"))])
		if recent_decisions.size() >= 5:
			break
	var contract_status := "completed" if bool(run_contract.get("completed", false)) and not bool(run_contract.get("failed", false)) else ("failed" if bool(run_contract.get("failed", false)) else ("active" if not run_contract.is_empty() else "none"))
	var record_key := "floor_%02d" % floor_number
	var inventory_ejections_value: Variant = run_ledger.get("inventory_ejections", [])
	var inventory_ejection_count: int = inventory_ejections_value.size() if typeof(inventory_ejections_value) == TYPE_ARRAY else 0
	var summary_metadata: Dictionary = {
		"events_resolved": int(run_ledger.get("events_resolved", 0)),
		"event_history": run_event_history,
		"bosses_defeated": int(run_ledger.get("bosses_defeated", 0)),
		"elites_defeated": int(run_ledger.get("elites_defeated", 0)),
		"seed": run_seed,
		"floor_number": floor_number,
		"floor_name": get_floor_name(),
		"floor_biome": str(get_floor_config().get("biome", "")),
		"floor_boss_id": str(get_floor_config().get("boss_id", "")),
		"floor_cleared": bool(run_ledger.get("floor_cleared", false)),
		"difficulty_id": difficulty_id,
		"modifier_id": run_modifier_id,
		"difficulty_name": str(ContentRegistry.DIFFICULTY_PRESETS.get(difficulty_id, {}).get("name", "Стандарт")),
		"modifier_name": str(get_run_modifier().get("name", "Обычная экспедиция")),
		"expedition_mode_id": expedition_mode_id,
		"expedition_mode_name": str(get_expedition_mode().get("name", "Обычная экспедиция")),
		"endgame_target_loops": int(endgame_goal.get("target_loops", 0)),
		"endgame_target_bosses": int(endgame_goal.get("target_bosses", 0)),
		"endgame_completed": bool(run_ledger.get("endgame_completed", false)),
		"endgame_checkpoints": (run_ledger.get("long_run_checkpoints", []).duplicate(true) if typeof(run_ledger.get("long_run_checkpoints", [])) == TYPE_ARRAY else []),
		"challenge": run_challenge.duplicate(true),
		"objective": run_objective.duplicate(true),
		"contract": run_contract.duplicate(true),
		"best_hp": int(hero.get("hp", 0)),
		"danger": snappedf(danger, 0.1),
		"challenge_score": challenge_score,
		"run_id": "%d-%d-floor%d" % [GameState.runs_started, run_seed, floor_number],
		"timestamp_unix": int(Time.get_unix_time_from_system()),
		"date": Time.get_datetime_string_from_system(false, true),
		"game_version": str(ProjectSettings.get_setting("application/config/version", "0.61.0")),
		"retention_percent": int(round((1.0 if outcome == "return" else defeat_keep_ratio) * 100.0)),
		# Stage68B: local-only real-run measurements. Old in-progress snapshots remain
		# explicitly marked as partial rather than manufacturing baseline values.
		"telemetry_schema": 1 if not run_baseline.is_empty() else 0,
		"measurement_quality": "complete" if not run_baseline.is_empty() else "legacy_partial",
		"run_elapsed_seconds": maxi(0, int(round(run_elapsed_seconds))),
		"start_hp": int(run_baseline.get("start_hp", 0)),
		"start_max_hp": int(run_baseline.get("start_max_hp", 0)),
		"start_attack": int(run_baseline.get("start_attack", 0)),
		"start_defense": int(run_baseline.get("start_defense", 0)),
		"start_profile_scrap": int(run_baseline.get("start_profile_scrap", 0)),
		"start_profile_crystals": int(run_baseline.get("start_profile_crystals", 0)),
		"contract_scrap_cost": maxi(0, int(run_contract.get("scrap_cost", 0))),
		"contract_crystal_cost": maxi(0, int(run_contract.get("crystal_cost", 0))),
		"end_hp": maxi(0, int(hero.get("hp", 0))),
		"end_max_hp": maxi(0, int(hero.get("max_hp", 0))),
		"end_attack": maxi(0, int(hero.get("attack", 0))),
		"end_defense": maxi(0, int(hero.get("defense", 0))),
		"field_cache_item_names": [],
		"field_cache_item_count": 0,
		"backpack_item_count": bag.size(),
		"backpack_ejected_item_count": inventory_ejection_count,
		"backpack_last_evicted_name": str(last_inventory_evicted_item.get("name", "")),
		"road_placements": placed_tiles.size(),
		"world_placements": world_tiles.size(),
		"route_cells": route.size(),
		"processed_steps": maxi(0, processed_steps),
		"start_loadout_ids": (run_baseline.get("loadout_ids", {}).duplicate(true) if typeof(run_baseline.get("loadout_ids", {})) == TYPE_DICTIONARY else {}),
		"objective_name": str(run_objective.get("name", "")),
		"objective_completed": bool(run_objective.get("completed", false)),
		"contract_name": str(run_contract.get("name", "")),
		"contract_status": contract_status,
		"tiles": recent_tile_names,
		"event_decisions": recent_decisions
	}
	var retained_run_items := _collect_run_items_for_settlement(outcome)
	var summary: Dictionary = GameState.settle_expedition(
		run_ledger, outcome, loop_count, int(hero.get("level", 1)), defeat_keep_ratio,
		summary_metadata, record_key, challenge_score,
		int(run_ledger.get("bosses_defeated", 0)), int(run_ledger.get("elites_defeated", 0)), equipment, retained_run_items
	)
	if not bool(summary.get("_persistence_ok", true)):
		active = true
		paused = true
		_request_feedback("error", str(summary.get("reason", "Не удалось сохранить итог экспедиции.")))
		_log("Завершение не зафиксировано на диске. Экспедиция остановлена; повторите «Вернуться на базу», чтобы повторить тот же результат.")
		changed.emit()
		return
	summary.erase("_persistence_ok")
	pending_end_outcome = ""
	pending_event.clear()
	encounter_enemies.clear()
	enemy.clear()
	_log("Экспедиция завершена: %s." % ("возвращение на базу" if outcome == "return" else "поражение"))
	changed.emit()
	run_finished.emit(summary.duplicate(true))

func _get_field_cache_item_names() -> Array[String]:
	var names: Array[String] = []
	for item_value in field_cache:
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_value
		names.append(str(item.get("name", "Предмет")))
	return names

func _build_run_baseline() -> Dictionary:
	var loadout_ids: Dictionary = {}
	for slot_value in InventorySystemScript.EQUIPMENT_SLOTS:
		var slot := str(slot_value)
		var item_value: Variant = equipment.get(slot, {})
		var item: Dictionary = item_value if typeof(item_value) == TYPE_DICTIONARY else {}
		loadout_ids[slot] = str(item.get("id", ""))
	return {
		"start_hp": maxi(0, int(hero.get("hp", 0))),
		"start_max_hp": maxi(0, int(hero.get("max_hp", 0))),
		"start_attack": maxi(0, int(hero.get("attack", 0))),
		"start_defense": maxi(0, int(hero.get("defense", 0))),
		# Captured before the contract fee is atomically deducted, so campaign
		# resource movement can be reconciled with contract_scrap/crystal_cost.
		"start_profile_scrap": maxi(0, int(GameState.scrap)),
		"start_profile_crystals": maxi(0, int(GameState.crystals)),
		"loadout_ids": loadout_ids
	}

func _scale_healing(amount: int) -> int:
	if amount <= 0:
		return 0
	var difficulty: Dictionary = ContentRegistry.DIFFICULTY_PRESETS.get(difficulty_id, ContentRegistry.DIFFICULTY_PRESETS["standard"])
	var floor_config: Dictionary = get_floor_config()
	var multiplier := clampf(float(floor_config.get("healing_multiplier", 1.0)) * float(difficulty.get("healing_multiplier", 1.0)), 0.1, 2.0)
	return maxi(1, int(floor(float(amount) * multiplier)))

func current_cell() -> int:
	if route.is_empty():
		return 0
	return posmod(int(floor(distance)), route.size())

func hero_progress_for_draw() -> float:
	return maxf(0.0, distance)

func _request_feedback(kind: String, message: String) -> void:
	feedback_requested.emit(kind, message)

func _log(message: String) -> void:
	event_log.push_front(message)
	while event_log.size() > int(ContentRegistry.BALANCE.get("max_event_log_entries", 8)):
		event_log.pop_back()

func _store_run_item(item: Dictionary, except_equipped_slot: String = "") -> bool:
	if not inventory_system.can_equip_item(item):
		return false
	var item_id := str(item.get("id", ""))
	if item_id.is_empty():
		return false
	# A duplicate is not a successful reward: do not consume one-shot loot bonuses,
	# emit loot feedback, or evict a different item for an item that was never added.
	if not find_run_item(item_id).is_empty():
		return false
	for slot_value in InventorySystemScript.EQUIPMENT_SLOTS:
		var equipped_slot := str(slot_value)
		if equipped_slot == except_equipped_slot:
			continue
		var equipped_value: Variant = equipment.get(equipped_slot, {})
		if typeof(equipped_value) == TYPE_DICTIONARY and str(equipped_value.get("id", "")) == item_id:
			return false
	last_inventory_evicted_item.clear()
	# The item enters the first (top-left) cell. If full, the oldest item at the
	# end (bottom-right) is ejected from this expedition's backpack queue.
	if bag.size() >= BACKPACK_CAPACITY:
		var evicted_value: Variant = bag.pop_back()
		if typeof(evicted_value) == TYPE_DICTIONARY:
			last_inventory_evicted_item = (evicted_value as Dictionary).duplicate(true)
			var ejections_value: Variant = run_ledger.get("inventory_ejections", [])
			var ejections: Array = ejections_value.duplicate(true) if typeof(ejections_value) == TYPE_ARRAY else []
			ejections.append(last_inventory_evicted_item.duplicate(true))
			var dust_value := inventory_system.get_ejection_echo_dust(last_inventory_evicted_item)
			run_ledger["inventory_ejections_dust"] = clampi(int(run_ledger.get("inventory_ejections_dust", 0)) + dust_value, 0, GameState.MAX_ECHO_DUST)
			run_ledger["inventory_ejections_count"] = mini(1000000, int(run_ledger.get("inventory_ejections_count", 0)) + 1)
			while ejections.size() > 100:
				ejections.pop_front()
			run_ledger["inventory_ejections"] = ejections
			_log("РЮКЗАК ПЕРЕПОЛНЕН: «%s» вытеснен и исчез из экспедиционного рюкзака." % str(last_inventory_evicted_item.get("name", "Старая вещь")))
	bag.push_front(item.duplicate(true))
	return true

func find_bag_item(item_id: String) -> Dictionary:
	if item_id.is_empty():
		return {}
	for item_value in bag:
		if typeof(item_value) == TYPE_DICTIONARY and str(item_value.get("id", "")) == item_id:
			return item_value.duplicate(true)
	return {}

func find_field_cache_item(_item_id: String) -> Dictionary:
	# Retained for compatibility with older callers; current expeditions have no extra cache.
	return {}

func find_run_item(item_id: String) -> Dictionary:
	return find_bag_item(item_id)

func equip_bag_item(item_id: String) -> Dictionary:
	if not active or not pending_end_outcome.is_empty():
		return {"ok": false, "message": "Сейчас экипировку менять нельзя."}
	if not pending_event.is_empty() or pending_perk_count > 0:
		return {"ok": false, "message": "Сначала завершите текущее событие или выбор улучшения."}
	var item_index := -1
	for index in range(bag.size()):
		var item_value: Variant = bag[index]
		if typeof(item_value) == TYPE_DICTIONARY and str(item_value.get("id", "")) == item_id:
			item_index = index
			break
	if item_index < 0:
		return {"ok": false, "message": "Предмет больше не находится в рюкзаке: он мог быть вытеснен новой добычей."}
	var candidate: Dictionary = bag[item_index].duplicate(true)
	if not inventory_system.can_equip_item(candidate):
		return {"ok": false, "message": "Предмет не подходит ни к одному слоту экипировки."}
	var candidate_id := str(candidate.get("id", ""))
	for slot_value in InventorySystemScript.EQUIPMENT_SLOTS:
		var equipped_value: Variant = equipment.get(str(slot_value), {})
		if typeof(equipped_value) == TYPE_DICTIONARY and str(equipped_value.get("id", "")) == candidate_id:
			return {"ok": false, "message": "Этот экземпляр предмета уже экипирован; дубликат не будет создан."}
	var slot := str(candidate.get("slot", ""))
	var old_bag: Array = bag.duplicate(true)
	var old_equipment: Dictionary = equipment.duplicate(true)
	var old_hero: Dictionary = hero.duplicate(true)
	var old_event_log: Array = event_log.duplicate(true)
	var current_value: Variant = equipment.get(slot, {})
	var displaced: Dictionary = current_value.duplicate(true) if typeof(current_value) == TYPE_DICTIONARY else {}
	bag.remove_at(item_index)
	# Loop Hero-style replacement: the previously equipped run item is not
	# moved back into the backpack. Permanent shelter collection is a separate system.
	equipment[slot] = candidate.duplicate(true)
	var hp_before_change := int(hero.get("hp", 1))
	_sync_hero_stats()
	hero["hp"] = mini(int(hero.get("max_hp", hp_before_change)), hp_before_change)
	_log("Экипировано вручную: %s → %s. Старая экипировка не возвращается в рюкзак." % [str(candidate.get("name", "Предмет")), inventory_system.slot_name(slot)])
	if not save_run_snapshot():
		bag = old_bag
		equipment = old_equipment
		hero = old_hero
		event_log = old_event_log
		return {"ok": false, "message": "Не удалось сохранить смену экипировки. Изменения отменены."}
	changed.emit()
	return {"ok": true, "message": "Предмет экипирован.", "item": candidate, "displaced": displaced, "source": "bag"}

func unequip_run_slot(slot: String) -> Dictionary:
	if not active or not InventorySystemScript.EQUIPMENT_SLOTS.has(slot):
		return {"ok": false, "message": "Этот слот недоступен."}
	if not pending_event.is_empty() or pending_perk_count > 0 or not pending_end_outcome.is_empty():
		return {"ok": false, "message": "Сначала завершите текущее решение."}
	var item_value: Variant = equipment.get(slot, {})
	if typeof(item_value) != TYPE_DICTIONARY or item_value.is_empty():
		return {"ok": false, "message": "Слот уже пуст."}
	var old_bag: Array = bag.duplicate(true)
	var old_equipment: Dictionary = equipment.duplicate(true)
	var old_hero: Dictionary = hero.duplicate(true)
	var old_event_log: Array = event_log.duplicate(true)
	var old_run_ledger: Dictionary = run_ledger.duplicate(true)
	var old_evicted: Dictionary = last_inventory_evicted_item.duplicate(true)
	var stored: bool = _store_run_item(item_value, slot)
	if not stored:
		return {"ok": false, "message": "Не удалось переместить предмет в рюкзак."}
	equipment[slot] = {}
	var hp_before_change := int(hero.get("hp", 1))
	_sync_hero_stats()
	hero["hp"] = mini(int(hero.get("max_hp", hp_before_change)), hp_before_change)
	_log("Снят предмет: %s. Он помещён в начало рюкзака." % str(item_value.get("name", "Предмет")))
	if not save_run_snapshot():
		bag = old_bag
		equipment = old_equipment
		hero = old_hero
		event_log = old_event_log
		run_ledger = old_run_ledger
		last_inventory_evicted_item = old_evicted
		return {"ok": false, "message": "Не удалось сохранить изменение. Экипировка восстановлена."}
	changed.emit()
	return {"ok": true, "message": "Предмет снят."}

func can_reorder_run_bag_item(item_id: String, target_index: int) -> bool:
	if not active or not pending_end_outcome.is_empty() or not pending_event.is_empty() or pending_perk_count > 0:
		return false
	if bag.is_empty() or target_index < 0 or target_index >= BACKPACK_CAPACITY:
		return false
	return not find_bag_item(item_id).is_empty()

func reorder_run_bag_item(item_id: String, target_index: int) -> Dictionary:
	if not can_reorder_run_bag_item(item_id, target_index):
		return {"ok": false, "message": "Нельзя переставить этот предмет сейчас."}
	var source_index := -1
	for index in range(bag.size()):
		if str(bag[index].get("id", "")) == item_id:
			source_index = index
			break
	if source_index < 0:
		return {"ok": false, "message": "Предмет больше не находится в рюкзаке."}
	var normalized_target := clampi(target_index, 0, bag.size() - 1)
	if source_index == normalized_target:
		return {"ok": true, "message": "Порядок рюкзака не изменился."}
	var old_bag: Array = bag.duplicate(true)
	var old_log: Array = event_log.duplicate(true)
	var item: Dictionary = bag[source_index].duplicate(true)
	bag.remove_at(source_index)
	bag.insert(normalized_target, item)
	_log("Предмет перемещён в ячейку %02d рюкзака; порядок вытеснения обновлён." % (normalized_target + 1))
	if not save_run_snapshot():
		bag = old_bag
		event_log = old_log
		return {"ok": false, "message": "Не удалось сохранить порядок рюкзака. Изменения отменены."}
	changed.emit()
	return {"ok": true, "message": "Порядок рюкзака изменён."}

func discard_run_bag_item(item_id: String) -> Dictionary:
	if not active or not pending_end_outcome.is_empty():
		return {"ok": false, "message": "Сейчас нельзя менять содержимое рюкзака."}
	if not pending_event.is_empty() or pending_perk_count > 0:
		return {"ok": false, "message": "Сначала завершите текущее решение."}
	var item_index := -1
	for index in range(bag.size()):
		var item_value: Variant = bag[index]
		if typeof(item_value) == TYPE_DICTIONARY and str(item_value.get("id", "")) == item_id:
			item_index = index
			break
	if item_index < 0:
		return {"ok": false, "message": "Предмет не найден в рюкзаке; он мог быть вытеснен новой добычей."}
	var old_bag: Array = bag.duplicate(true)
	var old_event_log: Array = event_log.duplicate(true)
	var item: Dictionary = bag[item_index].duplicate(true)
	bag.remove_at(item_index)
	_log("Убрано из текущего забега: %s. Постоянная коллекция убежища хранится отдельно." % str(item.get("name", "Предмет")))
	if not save_run_snapshot():
		bag = old_bag
		event_log = old_event_log
		return {"ok": false, "message": "Не удалось сохранить изменение. Предмет возвращён."}
	changed.emit()
	return {"ok": true, "message": "Предмет убран из текущего забега; копия в арсенале сохранена."}

func get_equipment_summary() -> Array:
	var lines: Array = []
	for slot_value in InventorySystemScript.EQUIPMENT_SLOTS:
		var slot := str(slot_value)
		var item_value: Variant = equipment.get(slot, {})
		var item: Dictionary = item_value if typeof(item_value) == TYPE_DICTIONARY else {}
		if item.is_empty():
			lines.append("%s: пусто" % EQUIPMENT_SLOT_NAMES[slot])
		else:
			var bonuses: Array[String] = []
			if int(item.get("attack", 0)) > 0:
				bonuses.append("АТК +%d" % int(item.attack))
			if int(item.get("defense", 0)) > 0:
				bonuses.append("ЗАЩ +%d" % int(item.defense))
			if int(item.get("hp", 0)) > 0:
				bonuses.append("ЗДР +%d" % int(item.hp))
			if float(item.get("speed", 0.0)) > 0.0:
				bonuses.append("СКР +%d%%" % int(round(float(item.speed) * 100.0)))
			if float(item.get("crit", 0.0)) > 0.0:
				bonuses.append("КРИТ +%d%%" % int(round(float(item.crit) * 100.0)))
			if float(item.get("bleed_chance", 0.0)) > 0.0:
				bonuses.append("Кровотечение %d%%" % int(round(float(item.get("bleed_chance", 0.0)) * 100.0)))
			if int(item.get("barrier_on_encounter", 0)) > 0:
				bonuses.append("Барьер %d" % int(item.get("barrier_on_encounter", 0)))
			if float(item.get("lifesteal", 0.0)) > 0.0:
				bonuses.append("вампиризм %d%%" % int(round(float(item.get("lifesteal", 0.0)) * 100.0)))
			if float(item.get("dodge_chance", 0.0)) > 0.0:
				bonuses.append("уклонение %d%%" % int(round(float(item.get("dodge_chance", 0.0)) * 100.0)))
			var archetype_text := str(item.get("archetype_name", ""))
			if not archetype_text.is_empty():
				bonuses.append("профиль: " + archetype_text)
			lines.append("%s: %s (%s)" % [EQUIPMENT_SLOT_NAMES[slot], str(item.name), ", ".join(bonuses)])
	for set_line in inventory_system.set_summary(equipment):
		lines.append("Набор: " + set_line)
	var derived_gear: Dictionary = inventory_system.total_equipment_stats(equipment)
	for synergy_name_value in derived_gear.get("active_synergies", []):
		lines.append("СИНЕРГИЯ АКТИВНА: " + str(synergy_name_value))
	return lines

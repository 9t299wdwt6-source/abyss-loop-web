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
const EQUIPMENT_SLOT_NAMES := {"weapon": "Оружие", "armor": "Броня", "core": "Ядро"}
const LANDSCAPE_SECRET_RECIPES := [
	{"first_tile": "archive", "second_tile": "rift", "flag": "secret_archive_rift_found", "title": "Архив и разлом", "clue": "Архивная карта сошлась с глубинным разломом."},
	{"first_tile": "nursery", "second_tile": "snare", "flag": "secret_nursery_snare_found", "title": "Питомник и сеть", "clue": "Сеть резонанса удерживает скрытое гнездо в питомнике."}
]

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
# Bounded local measurements for reproducible balance capture; no network telemetry.
var run_elapsed_seconds: float = 0.0
var run_baseline: Dictionary = {}
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
var tile_hand: Array = []
var bag: Array = []
var equipment: Dictionary = {"weapon": {}, "armor": {}, "core": {}}
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

func start_run(requested_difficulty_id: String = "standard", requested_seed: int = 0, requested_modifier_id: String = "standard", requested_contract_id: String = "none", requested_mode_id: String = "standard") -> bool:
	if active:
		return false
	pending_end_outcome = ""
	_snapshot_save_failure_notified = false
	var contract_acceptance := can_accept_contract(requested_contract_id)
	if not bool(contract_acceptance.get("ok", false)):
		return false
	difficulty_id = requested_difficulty_id if ContentRegistry.DIFFICULTY_PRESETS.has(requested_difficulty_id) else "standard"
	run_modifier_id = requested_modifier_id if ContentRegistry.RUN_MODIFIERS.has(requested_modifier_id) else "standard"
	expedition_mode_id = requested_mode_id if ContentRegistry.EXPEDITION_MODES.has(requested_mode_id) else "standard"
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
	run_elapsed_seconds = 0.0
	run_baseline.clear()
	run_rng = RandomNumberGenerator.new()
	run_rng.seed = run_seed
	route = route_system.create_route(run_seed, int(ContentRegistry.BALANCE.route_cells))
	run_objective = _choose_objective_for_seed(run_seed, run_modifier_id)
	distance = 0.0
	processed_steps = 0
	loop_count = 0
	var difficulty_config: Dictionary = ContentRegistry.DIFFICULTY_PRESETS[difficulty_id]
	danger = maxf(1.0, float(difficulty_config.get("starting_danger", 1.0)))
	paused = false
	speed = 1.0
	run_ledger = {"scrap": 0, "crystals": 0, "victories": 0, "bosses_defeated": 0, "elites_defeated": 0, "events_resolved": 0, "event_history": [], "event_flags": {}}
	placed_tiles.clear()
	world_tiles.clear()
	tile_hand.clear()
	bag.clear()
	equipment = GameState.loadout.duplicate(true)
	for slot in ["weapon", "armor", "core"]:
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
	_log("Экспедиция началась. Маршрут сгенерирован по seed %d." % run_seed)
	_log("Режим: %s." % str(get_expedition_mode().get("name", "Обычная экспедиция")))
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
	var projected_danger := minf(float(ContentRegistry.BALANCE.get("max_danger", 6.0)), danger + float(ContentRegistry.BALANCE.get("loop_danger_growth", 0.18)) * float(active_difficulty.get("danger_growth_multiplier", 1.0)) * float(modifier.get("danger_growth_multiplier", 1.0)))
	var projected_scrap_base := int(ContentRegistry.BALANCE.get("route_reward_scrap", 4)) + GameState.get_effective_loop_scrap_bonus()
	var projected_scrap := int(round(float(projected_scrap_base) * float(active_difficulty.get("reward_multiplier", 1.0)) * float(modifier.get("reward_multiplier", 1.0))))
	var crystal_interval := maxi(1, int(ContentRegistry.BALANCE.get("loop_crystal_interval", 2)))
	var projected_crystals := 1 if next_loop % crystal_interval == 0 else 0
	var chance := clampf(float(ContentRegistry.BALANCE.get("encounter_chance_base", 0.22)) + float(next_loop) * float(ContentRegistry.BALANCE.get("encounter_chance_per_loop", 0.04)) + float(active_difficulty.get("encounter_chance_delta", 0.0)) + _get_modifier_chance_delta(), float(ContentRegistry.BALANCE.get("encounter_chance_min", 0.08)), float(ContentRegistry.BALANCE.get("encounter_chance_max", 0.96)))
	var boss_interval := maxi(1, int(ContentRegistry.BALANCE.get("boss_loop_interval", 3)))
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
		"difficulty_name": str(active_difficulty.get("name", "Стандарт"))
	}

func export_run_state() -> Dictionary:
	if not active or route.is_empty() or hero.is_empty():
		return {}
	return {
		"snapshot_version": 4,
		"telemetry_schema": 1 if not run_baseline.is_empty() else 0,
		"run_elapsed_seconds": maxf(0.0, run_elapsed_seconds),
		"run_baseline": run_baseline.duplicate(true),
		"status_schema": 1,
		"field_schema": 2,
		"world_tiles": world_tiles.duplicate(true),
		"active": true,
		"run_seed": run_seed,
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
	run_elapsed_seconds = maxf(0.0, float(snapshot.get("run_elapsed_seconds", 0.0)))
	var baseline_value: Variant = snapshot.get("run_baseline", {})
	run_baseline = baseline_value.duplicate(true) if typeof(baseline_value) == TYPE_DICTIONARY else {}
	difficulty_id = str(snapshot.get("difficulty_id", "standard"))
	if not ContentRegistry.DIFFICULTY_PRESETS.has(difficulty_id):
		difficulty_id = "standard"
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
	var hand_value: Variant = snapshot.get("tile_hand", [])
	tile_hand = hand_value.duplicate(true) if typeof(hand_value) == TYPE_ARRAY else []
	var bag_value: Variant = snapshot.get("bag", [])
	bag = bag_value.duplicate(true) if typeof(bag_value) == TYPE_ARRAY else []
	var equipment_value: Variant = snapshot.get("equipment", {})
	equipment = equipment_value.duplicate(true) if typeof(equipment_value) == TYPE_DICTIONARY else {"weapon": {}, "armor": {}, "core": {}}
	for slot in ["weapon", "armor", "core"]:
		if typeof(equipment.get(slot, {})) != TYPE_DICTIONARY:
			equipment[slot] = {}
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
			danger += float(ContentRegistry.BALANCE.get("loop_danger_growth", 0.18)) * float(active_difficulty.get("danger_growth_multiplier", 1.0)) * float(get_run_modifier().get("danger_growth_multiplier", 1.0)) * float(get_expedition_mode().get("danger_growth_multiplier", 1.0))
			danger = _clamp_long_mode_danger(danger)
			var loop_reward_base := int(ContentRegistry.BALANCE.route_reward_scrap) + GameState.get_effective_loop_scrap_bonus()
			var combined_reward_multiplier := float(active_difficulty.get("reward_multiplier", 1.0)) * float(get_run_modifier().get("reward_multiplier", 1.0))
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

func _visit_cell(index: int) -> void:
	if route.is_empty():
		return
	var base_kind: String = route_system.get_cell_kind(route, index)
	var spawn_bonus := clampf(float(hero.get("equipped_tile_spawn_bonus", 0.0)) + float(hero.get("perk_tile_spawn_bonus", 0.0)), -0.25, 0.25)
	var strength_bonus := 0.0
	var reward_bonus := 0.0
	var should_offer_event: bool = false
	var messages: Array = []
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
		var effects: Dictionary = tile_system.apply_tile_visit(placed_tiles[str(index)], run_ledger, hero, loop_count)
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
		var world_effects: Dictionary = tile_system.apply_tile_visit(world_tile, run_ledger, hero, loop_count)
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
	var synergy: Dictionary = tile_system.get_synergy_bonus(placed_tiles, index, route.size())
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
		_begin_expedition_event(index, spawn_bonus, strength_bonus, reward_bonus)
		return
	var active_difficulty: Dictionary = ContentRegistry.DIFFICULTY_PRESETS.get(difficulty_id, ContentRegistry.DIFFICULTY_PRESETS["standard"])
	var base_chance := clampf(float(ContentRegistry.BALANCE.get("encounter_chance_base", 0.22)) + float(loop_count) * float(ContentRegistry.BALANCE.get("encounter_chance_per_loop", 0.04)) + spawn_bonus + float(active_difficulty.get("encounter_chance_delta", 0.0)) + _get_modifier_chance_delta(), float(ContentRegistry.BALANCE.get("encounter_chance_min", 0.08)), float(ContentRegistry.BALANCE.get("encounter_chance_max", 0.96)))
	var boss_interval := maxi(1, int(ContentRegistry.BALANCE.get("boss_loop_interval", 3)))
	var is_boss_node := index == 0 and loop_count > 0 and loop_count % boss_interval == 0
	if is_boss_node:
		_start_encounter(index, strength_bonus, reward_bonus, true)
	elif _rng_for_event().randf() < base_chance:
		_start_encounter(index, strength_bonus, reward_bonus, false)
	else:
		if messages.is_empty():
			_log("Узел %d: маршрут свободен." % (index + 1))

func _discover_landscape_secrets(route_index: int, messages: Array) -> void:
	if world_tiles.is_empty() or route_index < 0:
		return
	var flags_value: Variant = run_ledger.get("event_flags", {})
	var flags: Dictionary = flags_value.duplicate(true) if typeof(flags_value) == TYPE_DICTIONARY else {}
	var changed_flags := false
	for recipe_value in LANDSCAPE_SECRET_RECIPES:
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
			var coordinates := cell_id.split(":")
			if coordinates.size() != 2 or not coordinates[0].is_valid_int() or not coordinates[1].is_valid_int():
				continue
			var col := int(coordinates[0])
			var row := int(coordinates[1])
			var current_id := str(current_tile.get("id", ""))
			# Scan only right/down neighbours to visit each physical pair once.
			for position in [Vector2i(col + 1, row), Vector2i(col, row + 1)]:
				var neighbor_id := TileSystemScript.world_cell_id(position.x, position.y)
				if not TileSystemScript.is_world_cell_valid(neighbor_id) or not world_tiles.has(neighbor_id):
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

func _begin_expedition_event(index: int, spawn_bonus: float, strength_bonus: float, reward_bonus: float) -> void:
	pending_event = expedition_event_system.draw_event(run_rng, loop_count, last_event_id, run_ledger.get("event_flags", {}))
	if pending_event.is_empty():
		_log("Событие не удалось сформировать; маршрут продолжается без остановки.")
		return
	last_event_id = str(pending_event.get("id", ""))
	pending_event["context"] = {
		"cell_index": index,
		"spawn_bonus": spawn_bonus,
		"strength_bonus": strength_bonus,
		"reward_bonus": reward_bonus
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
	var event_damage_value: float = float(effects.get("damage", 0)) * float(event_difficulty.get("event_damage_multiplier", 1.0)) * float(get_run_modifier().get("event_damage_multiplier", 1.0))
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
	var encounter_difficulty: Dictionary = ContentRegistry.DIFFICULTY_PRESETS.get(difficulty_id, ContentRegistry.DIFFICULTY_PRESETS["standard"])
	var base_chance: float = clampf(float(ContentRegistry.BALANCE.get("encounter_chance_base", 0.22)) + float(loop_count) * float(ContentRegistry.BALANCE.get("encounter_chance_per_loop", 0.04)) + spawn_bonus + float(encounter_difficulty.get("encounter_chance_delta", 0.0)) + _get_modifier_chance_delta(), float(ContentRegistry.BALANCE.get("encounter_chance_min", 0.08)), float(ContentRegistry.BALANCE.get("encounter_chance_max", 0.96)))
	if _rng_for_event().randf() < base_chance:
		_start_encounter(int(context.get("cell_index", current_cell())), strength_bonus, reward_bonus, false)
	else:
		_log("После события маршрут остаётся свободным.")
	_update_objective_progress()
	changed.emit()
	save_run_snapshot()
	return {"ok": true, "reason": "Решение применено."}

func _grant_secret_event_item(relic_id: String) -> Dictionary:
	var item: Dictionary = inventory_system.make_secret_relic(relic_id, loop_count, int(hero.get("level", 1)), run_seed)
	if item.is_empty():
		_log("Секретная награда не распознана: %s. Остальные последствия выбора сохранены." % relic_id)
		return {}
	bag.append(item.duplicate(true))
	GameState.register_item(item)
	var slot := str(item.get("slot", ""))
	var current: Dictionary = equipment.get(slot, {})
	if inventory_system.should_equip(item, current):
		equipment[slot] = item.duplicate(true)
		GameState.loadout[slot] = item.duplicate(true)
		GameState.save_now()
		_sync_hero_stats()
		_log("ТАЙНАЯ РЕЛИКВИЯ: %s. Автоматически экипирована." % str(item.get("name", "Новая реликвия")))
	else:
		_log("ТАЙНАЯ РЕЛИКВИЯ: %s. Сохранена в арсенале для будущей сборки." % str(item.get("name", "Новая реликвия")))
	_request_feedback("loot", str(item.get("name", "Тайная реликвия")))
	return item

func _start_encounter(index: int, strength_bonus: float, reward_bonus: float, boss_encounter: bool) -> void:
	var active_difficulty: Dictionary = ContentRegistry.DIFFICULTY_PRESETS.get(difficulty_id, ContentRegistry.DIFFICULTY_PRESETS["standard"])
	var modifier: Dictionary = get_run_modifier()
	var encounter_scaling_loop := _effective_scaling_loop(loop_count)
	encounter_enemies = enemy_system.create_encounter(encounter_scaling_loop, danger, _rng_for_event(), strength_bonus, boss_encounter, int(active_difficulty.get("extra_group_members", 0)) + int(modifier.get("extra_group_members", 0)))
	if encounter_enemies.is_empty():
		return
	var elite_interval := maxi(1, int(ContentRegistry.BALANCE.get("elite_loop_interval", 4)))
	var elite_min_loop := maxi(1, int(ContentRegistry.BALANCE.get("elite_min_loop", 2)))
	var boss_interval := maxi(1, int(ContentRegistry.BALANCE.get("boss_loop_interval", 3)))
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
		var attack_multiplier := float(active_difficulty.get("enemy_attack_multiplier", 1.0)) * float(modifier.get("enemy_attack_multiplier", 1.0))
		var health_multiplier := float(active_difficulty.get("enemy_health_multiplier", 1.0)) * float(modifier.get("enemy_health_multiplier", 1.0))
		var defense_multiplier := float(active_difficulty.get("enemy_defense_multiplier", 1.0)) * float(modifier.get("enemy_defense_multiplier", 1.0))
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
		var player_hit: Dictionary = combat_system.perform_attack(hero, enemy, _rng_for_event())
		var bleed_chance := clampf(float(hero.get("bleed_chance", 0.0)), 0.0, 0.5)
		if not bool(player_hit.get("defeated", false)) and bleed_chance > 0.0 and _rng_for_event().randf() < bleed_chance:
			var bleed_result: Dictionary = status_effect_system.apply_effect(enemy, "bleed", -1.0, float(maxi(1, int(hero.get("bleed_damage", 2)))), "equipment_weapon")
			if bool(bleed_result.get("ok", false)):
				_log("Оружие накладывает кровотечение на %s." % str(enemy.get("name", "противника")))
		if bool(player_hit.get("critical", false)):
			var exposed_result: Dictionary = status_effect_system.apply_effect(enemy, "exposed", -1.0, -1.0, "hero_critical")
			if bool(exposed_result.get("ok", false)):
				_log("Критический удар накладывает уязвимость: защита цели снижена на время эффекта.")
		_log("Герой наносит %d урона%s цели «%s»." % [int(player_hit.damage), " — критический удар" if bool(player_hit.critical) else "", str(enemy.get("name", "противник"))])
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
			_log("ПРЕДУПРЕЖДЕНИЕ: %s — %s" % [str(fighter.get("name", "Противник")), str(fighter.get("phase_telegraph", "готовит особую атаку"))])
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
		var enemy_hit: Dictionary = combat_system.perform_attack(attack_source, hero, _rng_for_event())
		var hit_message := "%s наносит %d урона герою." % [str(fighter.get("name", "Противник")), int(enemy_hit.damage)]
		if int(enemy_hit.get("absorbed", 0)) > 0:
			hit_message += " Барьер поглотил %d." % int(enemy_hit.get("absorbed", 0))
		_log(hit_message)
		if int(enemy_hit.damage) > 0:
			_request_feedback("damage", "−%d здоровья" % int(enemy_hit.damage))
		if is_special and is_elite_attacker:
			var elite_status_id := str(fighter.get("elite_ability_id", ""))
			if not elite_status_id.is_empty():
				var elite_status_result: Dictionary = status_effect_system.apply_effect(hero, elite_status_id, float(fighter.get("elite_effect_duration", 3.0)), float(fighter.get("elite_effect_magnitude", 0.0)), str(fighter.get("uid", "elite")))
				if bool(elite_status_result.get("ok", false)):
					_log("Элитная способность накладывает на героя эффект «%s»." % str(elite_status_result.get("name", elite_status_id)))
		if is_special and is_boss_attacker:
			var boss_effect_id := str(fighter.get("special_effect_id", "wound"))
			var boss_effect_result: Dictionary = status_effect_system.apply_effect(hero, boss_effect_id, float(fighter.get("special_effect_duration", 4.0)), float(fighter.get("special_effect_magnitude", 0.12)), str(fighter.get("id", "boss")))
			if bool(boss_effect_result.get("ok", false)):
				var boss_effect_log := str(fighter.get("special_effect_log", "Особая атака босса накладывает эффект «%s»." % str(boss_effect_result.get("name", boss_effect_id))))
				_log(boss_effect_log)
		if role == "hunter" and int(fighter.get("attack_count", 0)) % 3 == 0 and not is_elite_attacker:
			var weakness_result: Dictionary = status_effect_system.apply_effect(hero, "weakness", 3.0, 0.18, str(fighter.get("id", "hunter")))
			if bool(weakness_result.get("ok", false)):
				_log("Охотник ослабляет ответный удар героя на время эффекта.")
		if role == "caster" and int(fighter.get("attack_count", 0)) % 3 == 0 and not is_elite_attacker:
			var applied_status: Dictionary = status_effect_system.apply_effect(hero, "distortion", float(ContentRegistry.BALANCE.get("enemy_caster_debuff_duration", 3.5)), float(ContentRegistry.BALANCE.get("enemy_caster_debuff", 0.18)), str(fighter.get("id", "caster")))
			if bool(applied_status.get("ok", false)):
				_log("Искажение замедляет атаки героя на %.1f секунды." % float(applied_status.get("duration", 3.5)))
		if int(hero.hp) <= 0:
			_log("Герой потерял сознание. Будет сохранена только часть добычи.")
			_finish_run("defeat")
			return

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
			var phase_status_result: Dictionary = status_effect_system.apply_effect(effect_target, phase_effect_id, float(phase_effect.get("duration", 3.0)), float(phase_effect.get("magnitude", 0.0)), str(enemy.get("id", "boss_phase")))
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
	var reward: Dictionary = loot_system.roll_victory(defeated_enemy, loop_count, _rng_for_event(), reward_bonus)
	resource_system.add(run_ledger, "scrap", int(reward.scrap))
	resource_system.add(run_ledger, "crystals", int(reward.crystals))
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
	var item_chance := 1.0 if is_boss else float(ContentRegistry.BALANCE.loot_item_chance) + minf(float(ContentRegistry.BALANCE.loot_item_bonus_cap), combat_reward_bonus * float(ContentRegistry.BALANCE.loot_item_bonus_multiplier))
	if is_elite:
		item_chance = maxf(item_chance, float(ContentRegistry.BALANCE.get("elite_item_chance", 0.45)))
	if drop_rng.randf() < item_chance:
		var item: Dictionary = inventory_system.roll_boss_item(defeated_enemy, drop_rng, loop_count, int(hero.level)) if is_boss else {}
		if item.is_empty():
			item = inventory_system.roll_item(drop_rng, loop_count, int(hero.level))
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
			item["rarity"] = "Элитная"
			item["name"] = "%s · Элитная находка" % str(item.get("name", "Предмет"))
			for stat_key in ["attack", "defense", "hp"]:
				var elite_stat_value := int(item.get(stat_key, 0))
				if elite_stat_value > 0:
					item[stat_key] = maxi(1, int(ceil(float(elite_stat_value) * 1.10)))
		item["power"] = inventory_system.item_power(item)
		bag.append(item)
		GameState.register_item(item)
		var slot := str(item.slot)
		var current: Dictionary = equipment.get(slot, {})
		if inventory_system.should_equip(item, current):
			equipment[slot] = item
			GameState.loadout[slot] = item.duplicate(true)
			GameState.save_now()
			_sync_hero_stats()
			_log(("ИМЕННАЯ РЕЛИКВИЯ БОССА: %s. Она автоматически экипирована." if bool(item.get("is_boss_relic", false)) else "Найден предмет: %s. Он автоматически экипирован.") % str(item.get("name", "Предмет")))
			_request_feedback("loot", str(item.get("name", "Предмет найден")))
		else:
			_log(("ИМЕННАЯ РЕЛИКВИЯ БОССА: %s. Предмет сохранён в арсенале — текущая экипировка сильнее." if bool(item.get("is_boss_relic", false)) else "Найден предмет: %s. Текущая экипировка лучше.") % str(item.get("name", "Предмет")))
			_request_feedback("loot", str(item.get("name", "Предмет найден")))
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
	var can_place: Dictionary = tile_system.can_place(route, placed_tiles, cell_index)
	if not bool(can_place.ok):
		return can_place
	var tile: Dictionary = tile_hand[hand_index].duplicate(true)
	placed_tiles[str(cell_index)] = tile
	tile_hand.remove_at(hand_index)
	_log("Размещён тайл «%s» на дорожном узле %d. Рука теперь содержит %d тайла(ов)." % [tile.name, cell_index + 1, tile_hand.size()])
	changed.emit()
	save_run_snapshot()
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
	var placement: Dictionary = tile_system.can_place_world(route, world_tiles, cell_id)
	if not bool(placement.get("ok", false)):
		return placement
	var tile: Dictionary = tile_hand[hand_index].duplicate(true)
	var parts := cell_id.split(":")
	tile["field_x"] = int(parts[0])
	tile["field_y"] = int(parts[1])
	tile["route_index"] = int(placement.get("route_index", -1))
	world_tiles[cell_id] = tile
	tile_hand.remove_at(hand_index)
	_log("Тайл «%s» размещён на ландшафте (%d, %d), сектор маршрута %d." % [str(tile.get("name", "Тайл")), int(tile.field_x) + 1, int(tile.field_y) + 1, int(tile.route_index) + 1])
	changed.emit()
	save_run_snapshot()
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
	var defeat_keep_ratio := clampf(float(active_difficulty.get("defeat_keep_ratio", ContentRegistry.BALANCE.get("defeat_keep_ratio", 0.4))), 0.0, 1.0)
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
	var record_key := difficulty_id if expedition_mode_id == "standard" else "%s:%s" % [difficulty_id, expedition_mode_id]
	var summary_metadata: Dictionary = {
		"events_resolved": int(run_ledger.get("events_resolved", 0)),
		"event_history": run_event_history,
		"bosses_defeated": int(run_ledger.get("bosses_defeated", 0)),
		"elites_defeated": int(run_ledger.get("elites_defeated", 0)),
		"seed": run_seed,
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
		"run_id": "%d-%d-%s" % [GameState.runs_started, run_seed, difficulty_id],
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
	var summary: Dictionary = GameState.settle_expedition(
		run_ledger, outcome, loop_count, int(hero.get("level", 1)), defeat_keep_ratio,
		summary_metadata, record_key, challenge_score,
		int(run_ledger.get("bosses_defeated", 0)), int(run_ledger.get("elites_defeated", 0)), equipment
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

func _build_run_baseline() -> Dictionary:
	var loadout_ids: Dictionary = {}
	for slot in ["weapon", "armor", "core"]:
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
	var multiplier := clampf(float(difficulty.get("healing_multiplier", 1.0)), 0.1, 2.0)
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

func get_equipment_summary() -> Array:
	var lines: Array = []
	for slot in ["weapon", "armor", "core"]:
		var item: Dictionary = equipment.get(slot, {})
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

extends Node

signal changed

const ResourceSystemScript = preload("res://scripts/systems/resource_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const RESEARCH_RESET_REFUND_PERCENT := 80
const MAX_EXPEDITION_HISTORY := 50
const MAX_SETTLED_EXPEDITION_IDS := 1000
const MAX_ECHO_DUST := 1000000
const TROPHY_IDS: Array[String] = ["spore_pollen", "prism_fragment", "bone_fragment", "echo_residue"]

const DEFAULT_BUILDINGS := {"forge": 0, "infirmary": 0, "salvage": 0, "cartographer": 0}
var scrap: int = 60
var crystals: int = 14
var echo_dust: int = 0
var settled_expedition_ids: Array = []
var bestiary_trophies: Dictionary = {"spore_pollen": 0, "prism_fragment": 0, "bone_fragment": 0, "echo_residue": 0}
var buildings: Dictionary = DEFAULT_BUILDINGS.duplicate(true)
var loadout: Dictionary = {"weapon": {}, "helmet": {}, "armor": {}, "shield": {}, "amulet": {}, "core": {}}
var armory: Array = []
var runs_started: int = 0
var runs_completed: int = 0
var highest_unlocked_floor: int = 1
var best_loop: int = 0
var total_victories: int = 0
var total_bosses_defeated: int = 0
var total_elites_defeated: int = 0
var total_events_resolved: int = 0
var unlocked_nodes: Array = []
# Actual purchase prices let a later respec refund what was paid, even if balance costs change.
var research_investments: Dictionary = {}
var saved_expedition: Dictionary = {}
var tutorial_page: int = 0
var tutorial_completed: bool = false
var load_notice: String = ""
const DEFAULT_SETTINGS := {
	"master_volume": 0.8,
	"music_volume": 0.7,
	"effects_volume": 0.85,
	"ui_scale": 1.0,
	"window_mode": "windowed",
	"reduced_motion": false,
	"reduce_flashes": true,
	"high_contrast": false,
	"status_symbols": true,
	"animation_speed": 1.0
}
var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var last_summary: Dictionary = {}
var difficulty_records: Dictionary = {}
# A bounded local journal. Records contain summaries only, never full expedition snapshots.
var expedition_history: Array = []

func _empty_trophy_counts() -> Dictionary:
	return {"spore_pollen": 0, "prism_fragment": 0, "bone_fragment": 0, "echo_residue": 0}

func _normalize_trophy_counts(value: Variant) -> Dictionary:
	var result := _empty_trophy_counts()
	if typeof(value) != TYPE_DICTIONARY:
		return result
	var source: Dictionary = value
	for trophy_id in TROPHY_IDS:
		result[trophy_id] = clampi(int(source.get(trophy_id, 0)), 0, 100000000)
	return result

func _subtract_trophy_counts(total: Dictionary, kept: Dictionary) -> Dictionary:
	var result := _empty_trophy_counts()
	for trophy_id in TROPHY_IDS:
		result[trophy_id] = maxi(0, int(total.get(trophy_id, 0)) - int(kept.get(trophy_id, 0)))
	return result

func _ready() -> void:
	var saved: Dictionary = SaveSystem.load_game()
	if str(SaveSystem.last_load_status) == "recovered_backup":
		load_notice = "Основное сохранение повреждено. Прогресс восстановлен из резервной копии; проверьте результат перед продолжением."
	elif str(SaveSystem.last_load_status) == "recovered_backup_missing_primary":
		load_notice = "Основной файл сохранения отсутствовал. Прогресс восстановлен из резервной копии."
	elif str(SaveSystem.last_load_status) == "migrated_legacy_profile":
		load_notice = "Найден прогресс предыдущей версии Abyss Loop. Он перенесён в постоянный профиль; исходный файл сохранён."
	elif str(SaveSystem.last_load_status) == "legacy_profile_migration_failed":
		load_notice = "Найдено старое сохранение, но его не удалось перенести. Исходный профиль не изменён; проверьте доступ к папке сохранений."
	elif str(SaveSystem.last_load_status) == "backup_recovery_failed":
		load_notice = "Найдена резервная копия, но восстановить её безопасно не удалось. Исходные файлы оставлены для диагностики."
	elif str(SaveSystem.last_load_status) == "corrupt_no_backup":
		load_notice = "Сохранение не удалось проверить, а резервная копия недоступна. Исходные файлы сохранены для диагностики; игра запущена с настройками по умолчанию."
	if not saved.is_empty():
		scrap = maxi(0, int(saved.get("scrap", scrap)))
		crystals = maxi(0, int(saved.get("crystals", crystals)))
		echo_dust = clampi(int(saved.get("echo_dust", 0)), 0, MAX_ECHO_DUST)
		var settled_ids_value: Variant = saved.get("settled_expedition_ids", [])
		settled_expedition_ids.clear()
		if typeof(settled_ids_value) == TYPE_ARRAY:
			for settled_id_value in settled_ids_value:
				if typeof(settled_id_value) != TYPE_STRING:
					continue
				var settled_id := str(settled_id_value).strip_edges()
				if not settled_id.is_empty() and not settled_expedition_ids.has(settled_id):
					settled_expedition_ids.append(settled_id)
		while settled_expedition_ids.size() > MAX_SETTLED_EXPEDITION_IDS:
			settled_expedition_ids.pop_front()
		var saved_trophies_value: Variant = saved.get("bestiary_trophies", {})
		bestiary_trophies = _normalize_trophy_counts(saved_trophies_value)
		var saved_buildings: Variant = saved.get("buildings", DEFAULT_BUILDINGS)
		if typeof(saved_buildings) == TYPE_DICTIONARY:
			for building_id in DEFAULT_BUILDINGS.keys():
				buildings[building_id] = clampi(int(saved_buildings.get(building_id, 0)), 0, int(ContentRegistry.BUILDINGS[building_id].get("max_level", 5)))
		var saved_loadout: Variant = saved.get("loadout", loadout)
		if typeof(saved_loadout) == TYPE_DICTIONARY:
			for slot in InventorySystemScript.EQUIPMENT_SLOTS:
				var saved_item: Variant = saved_loadout.get(slot, {})
				loadout[slot] = saved_item.duplicate(true) if typeof(saved_item) == TYPE_DICTIONARY else {}
		var saved_armory: Variant = saved.get("armory", [])
		if typeof(saved_armory) == TYPE_ARRAY:
			armory.clear()
			for armory_item_data in saved_armory:
				if typeof(armory_item_data) == TYPE_DICTIONARY:
					armory.append(armory_item_data.duplicate(true))
		runs_started = maxi(0, int(saved.get("runs_started", 0)))
		runs_completed = maxi(0, int(saved.get("runs_completed", 0)))
		highest_unlocked_floor = clampi(int(saved.get("highest_unlocked_floor", 1)), 1, ContentRegistry.FLOOR_COUNT)
		best_loop = maxi(0, int(saved.get("best_loop", 0)))
		total_victories = maxi(0, int(saved.get("total_victories", 0)))
		total_bosses_defeated = maxi(0, int(saved.get("total_bosses_defeated", 0)))
		total_elites_defeated = maxi(0, int(saved.get("total_elites_defeated", 0)))
		total_events_resolved = maxi(0, int(saved.get("total_events_resolved", 0)))
		var saved_unlocks: Variant = saved.get("unlocked_nodes", [])
		if typeof(saved_unlocks) == TYPE_ARRAY:
			unlocked_nodes.clear()
			for node_value in saved_unlocks:
				# Keep stable IDs even if a content definition is temporarily absent. Known
				# effects are only applied by get_unlock_effect(); unknown IDs remain dormant.
				if typeof(node_value) == TYPE_STRING:
					var node_id := str(node_value)
					var canonical_id := ContentRegistry.canonical_research_id(node_id)
					if not canonical_id.is_empty() and not unlocked_nodes.has(canonical_id):
						unlocked_nodes.append(canonical_id)
		var saved_investments: Variant = saved.get("research_investments", {})
		if typeof(saved_investments) == TYPE_DICTIONARY:
			research_investments.clear()
			for research_id_value in saved_investments.keys():
				var research_id := str(research_id_value)
				var canonical_id := ContentRegistry.canonical_research_id(research_id)
				var investment_value: Variant = saved_investments[research_id_value]
				if not canonical_id.is_empty() and typeof(investment_value) == TYPE_DICTIONARY:
					# Prefer a canonical ledger entry if both a legacy alias and its successor exist.
					if not research_investments.has(canonical_id) or research_id == canonical_id:
						research_investments[canonical_id] = {
							"scrap": maxi(0, int(investment_value.get("scrap", 0))),
							"crystals": maxi(0, int(investment_value.get("crystals", 0)))
						}
		var saved_run_value: Variant = saved.get("saved_expedition", {})
		if typeof(saved_run_value) == TYPE_DICTIONARY and bool(saved_run_value.get("active", false)):
			var saved_route_value: Variant = saved_run_value.get("route", [])
			if typeof(saved_route_value) == TYPE_ARRAY:
				var saved_route: Array = saved_route_value
				if not saved_route.is_empty() and int(saved_run_value.get("snapshot_version", 1)) in [1, 2, 3, 4]:
					saved_expedition = SaveSystem.migrate_expedition_snapshot(saved_run_value)
		var saved_tutorial_page: Variant = saved.get("tutorial_page", 0)
		if typeof(saved_tutorial_page) == TYPE_INT:
			tutorial_page = clampi(int(saved_tutorial_page), 0, 5)
		tutorial_completed = bool(saved.get("tutorial_completed", false))
		var saved_settings: Variant = saved.get("settings", DEFAULT_SETTINGS)
		settings = DEFAULT_SETTINGS.duplicate(true)
		if typeof(saved_settings) == TYPE_DICTIONARY:
			for setting_key in DEFAULT_SETTINGS.keys():
				if saved_settings.has(setting_key):
					settings[setting_key] = saved_settings[setting_key]
		var summary: Variant = saved.get("last_summary", {})
		if typeof(summary) == TYPE_DICTIONARY:
			last_summary = summary.duplicate(true)
		var records_value: Variant = saved.get("difficulty_records", {})
		if typeof(records_value) == TYPE_DICTIONARY:
			difficulty_records.clear()
			for record_key_value in records_value.keys():
				var record_value: Variant = records_value[record_key_value]
				if typeof(record_value) == TYPE_DICTIONARY:
					var record_data: Dictionary = record_value
					difficulty_records[str(record_key_value)] = {
						"runs": maxi(0, int(record_data.get("runs", 0))),
						"returns": maxi(0, int(record_data.get("returns", 0))),
						"best_score": maxi(0, int(record_data.get("best_score", 0))),
						"best_loops": maxi(0, int(record_data.get("best_loops", 0))),
						"bosses": maxi(0, int(record_data.get("bosses", 0))),
						"elites": maxi(0, int(record_data.get("elites", 0)))
					}
		var history_value: Variant = saved.get("expedition_history", [])
		if typeof(history_value) == TYPE_ARRAY:
			expedition_history.clear()
			for history_entry_value in history_value:
				if typeof(history_entry_value) != TYPE_DICTIONARY:
					continue
				var history_entry: Dictionary = history_entry_value
				var run_id := str(history_entry.get("run_id", ""))
				if run_id.is_empty():
					continue
				expedition_history.append(_normalize_history_entry(history_entry))
			if expedition_history.size() > MAX_EXPEDITION_HISTORY:
				expedition_history = expedition_history.slice(expedition_history.size() - MAX_EXPEDITION_HISTORY)
	_normalize_settings()
	changed.emit()

func _normalize_settings() -> void:
	for setting_key in DEFAULT_SETTINGS.keys():
		if not settings.has(setting_key):
			settings[setting_key] = DEFAULT_SETTINGS[setting_key]
	for setting_key in ["master_volume", "music_volume", "effects_volume"]:
		settings[setting_key] = clampf(float(settings.get(setting_key, DEFAULT_SETTINGS[setting_key])), 0.0, 1.0)
	settings["ui_scale"] = clampf(float(settings.get("ui_scale", 1.0)), 0.85, 1.10)
	settings["animation_speed"] = clampf(float(settings.get("animation_speed", 1.0)), 0.5, 1.5)
	if not ["windowed", "fullscreen"].has(str(settings.get("window_mode", "windowed"))):
		settings["window_mode"] = "windowed"
	for setting_key in ["reduced_motion", "reduce_flashes", "high_contrast", "status_symbols"]:
		settings[setting_key] = bool(settings.get(setting_key, DEFAULT_SETTINGS[setting_key]))

func get_attack_bonus() -> int:
	return int(buildings.get("forge", 0)) * int(ContentRegistry.BUILDINGS.forge.attack_per_level)

func get_health_bonus() -> int:
	return int(buildings.get("infirmary", 0)) * int(ContentRegistry.BUILDINGS.infirmary.hp_per_level)

func get_defense_bonus() -> int:
	return int(buildings.get("infirmary", 0)) * int(ContentRegistry.BUILDINGS.infirmary.defense_per_level)

func get_loop_scrap_bonus() -> int:
	return int(buildings.get("salvage", 0)) * int(ContentRegistry.BUILDINGS.salvage.loop_scrap_per_level)

func get_effective_loop_scrap_bonus() -> int:
	# All permanent income sources share one cap. The route's base reward and
	# expedition risk still scale separately, so meta-progression cannot erase run pressure.
	var building_bonus := get_loop_scrap_bonus()
	var research_bonus := int(get_unlock_effect("loop_scrap_bonus")) + int(get_unlock_effect("route_reward_bonus"))
	var cap := maxi(0, int(ContentRegistry.BALANCE.get("shelter_loop_scrap_bonus_cap", 6)))
	return clampi(building_bonus + research_bonus, 0, cap)

func get_rare_tile_weight_multiplier() -> float:
	# The observatory increases discovery chance without letting rare cards dominate
	# the hand. The 1.50 ceiling is shared by both route and landscape tile draws.
	var level := clampi(int(buildings.get("cartographer", 0)), 0, int(ContentRegistry.BUILDINGS.get("cartographer", {}).get("max_level", 5)))
	var per_level := 0.10
	return 1.0 + minf(0.50, float(level) * per_level)

func has_research(research_id: String) -> bool:
	return unlocked_nodes.has(research_id)

func get_research_reset_preview() -> Dictionary:
	if has_saved_expedition():
		return {"ok": false, "reason": "active_expedition", "message": "Перераспределение доступно только между экспедициями."}
	var research_ids: Array[String] = []
	var research_names: Array[String] = []
	var preserved_unknown_ids: Array[String] = []
	var legacy_price_fallback := false
	var spent_scrap := 0
	var spent_crystals := 0
	for research_id_value in unlocked_nodes:
		var research_id := str(research_id_value)
		if research_ids.has(research_id) or preserved_unknown_ids.has(research_id):
			continue
		if not ContentRegistry.BASE_RESEARCH.has(research_id):
			# Content that isn't registered in this build is never deleted/refunded by respec.
			preserved_unknown_ids.append(research_id)
			continue
		research_ids.append(research_id)
		var definition: Dictionary = ContentRegistry.BASE_RESEARCH[research_id]
		research_names.append(str(definition.get("name", research_id)))
		var paid_scrap := maxi(0, int(definition.get("scrap_cost", 0)))
		var paid_crystals := maxi(0, int(definition.get("crystal_cost", 0)))
		var investment_value: Variant = research_investments.get(research_id, null)
		if typeof(investment_value) == TYPE_DICTIONARY:
			paid_scrap = maxi(0, int(investment_value.get("scrap", paid_scrap)))
			paid_crystals = maxi(0, int(investment_value.get("crystals", paid_crystals)))
		else:
			# Legacy saves did not record actual paid prices; preview labels this estimate.
			legacy_price_fallback = true
		spent_scrap += paid_scrap
		spent_crystals += paid_crystals
	if research_ids.is_empty():
		return {"ok": false, "reason": "nothing_to_reset", "message": "Нет доступных изученных узлов для сброса. Неизвестные ID сохранены."}
	var refund_scrap := floori(float(spent_scrap) * float(RESEARCH_RESET_REFUND_PERCENT) / 100.0)
	var refund_crystals := floori(float(spent_crystals) * float(RESEARCH_RESET_REFUND_PERCENT) / 100.0)
	return {
		"ok": true,
		"research_ids": research_ids,
		"research_names": research_names,
		"preserved_unknown_ids": preserved_unknown_ids,
		"research_count": research_ids.size(),
		"preserved_unknown_count": preserved_unknown_ids.size(),
		"legacy_price_fallback": legacy_price_fallback,
		"spent_scrap": spent_scrap,
		"spent_crystals": spent_crystals,
		"refund_scrap": refund_scrap,
		"refund_crystals": refund_crystals,
		"lost_scrap": spent_scrap - refund_scrap,
		"lost_crystals": spent_crystals - refund_crystals,
		"refund_percent": RESEARCH_RESET_REFUND_PERCENT
	}

func reset_research_tree() -> Dictionary:
	# Respec is a single persistent transaction. Never alter resources or unlocks
	# if a checkpoint is active, no registered nodes are refundable, or saving fails.
	var preview := get_research_reset_preview()
	if not bool(preview.get("ok", false)):
		return {"ok": false, "message": str(preview.get("message", "Сброс исследований недоступен."))}
	var reset_ids: Array = preview.get("research_ids", [])
	var old_unlocked_nodes: Array = unlocked_nodes.duplicate(true)
	var old_investments: Dictionary = research_investments.duplicate(true)
	var old_scrap := scrap
	var old_crystals := crystals
	var remaining_nodes: Array = []
	for node_value in unlocked_nodes:
		# Preserve unknown/future IDs. Only registered research nodes are reset.
		if not reset_ids.has(str(node_value)):
			remaining_nodes.append(node_value)
	for research_id_value in reset_ids:
		research_investments.erase(str(research_id_value))
	scrap += int(preview.get("refund_scrap", 0))
	crystals += int(preview.get("refund_crystals", 0))
	unlocked_nodes = remaining_nodes
	if not save_now():
		unlocked_nodes = old_unlocked_nodes
		research_investments = old_investments
		scrap = old_scrap
		crystals = old_crystals
		return {"ok": false, "message": "Не удалось сохранить перераспределение. Исследования и ресурсы восстановлены без изменений."}
	changed.emit()
	return {
		"ok": true,
		"message": "Дерево исследований сброшено. Возвращено %d материалов и %d кристаллов; не возвращённая часть удержана как плата за перераспределение." % [int(preview.get("refund_scrap", 0)), int(preview.get("refund_crystals", 0))],
		"refund_scrap": int(preview.get("refund_scrap", 0)),
		"refund_crystals": int(preview.get("refund_crystals", 0)),
		"research_count": int(preview.get("research_count", 0)),
		"preserved_unknown_count": int(preview.get("preserved_unknown_count", 0))
	}

func get_unlock_effect(effect_id: String) -> float:
	var total: float = 0.0
	for research_id_value in unlocked_nodes:
		var research_id := str(research_id_value)
		var definition_value: Variant = ContentRegistry.BASE_RESEARCH.get(research_id, {})
		if typeof(definition_value) != TYPE_DICTIONARY:
			continue
		var effects_value: Variant = definition_value.get("effects", {})
		if typeof(effects_value) == TYPE_DICTIONARY:
			total += float(effects_value.get(effect_id, 0.0))
	return total

func has_saved_expedition() -> bool:
	if not bool(saved_expedition.get("active", false)) or not [1, 2, 3, 4].has(int(saved_expedition.get("snapshot_version", 1))):
		return false
	var route_value: Variant = saved_expedition.get("route", [])
	if typeof(route_value) != TYPE_ARRAY:
		return false
	var route: Array = route_value
	return not route.is_empty()

func set_saved_expedition(snapshot: Dictionary) -> bool:
	if not bool(snapshot.get("active", false)) or not [1, 2, 3, 4].has(int(snapshot.get("snapshot_version", 1))):
		return false
	var route_value: Variant = snapshot.get("route", [])
	if typeof(route_value) != TYPE_ARRAY:
		return false
	var route: Array = route_value
	if route.is_empty():
		return false
	# Do not leave a newer checkpoint in memory when the disk transaction fails.
	# That mismatch used to make the UI appear saved even though a restart reverted it.
	var previous_snapshot: Dictionary = saved_expedition.duplicate(true)
	saved_expedition = snapshot.duplicate(true)
	if not save_now():
		saved_expedition = previous_snapshot
		return false
	return true

func clear_saved_expedition() -> bool:
	if saved_expedition.is_empty():
		return true
	# Discard is a persistent transaction too: if the save fails, keep the checkpoint
	# so the user never loses the only recoverable copy of an expedition.
	var previous_snapshot: Dictionary = saved_expedition.duplicate(true)
	saved_expedition.clear()
	if not save_now():
		saved_expedition = previous_snapshot
		return false
	changed.emit()
	return true

func record_run_started() -> void:
	runs_started += 1
	save_now()
	changed.emit()

func commit_expedition_start(snapshot: Dictionary, scrap_cost: int = 0, crystal_cost: int = 0) -> bool:
	# Commit contract costs, the run counter, and the first checkpoint in one save.
	# If persistence fails, roll back the in-memory values so no contract fee is lost.
	if not bool(snapshot.get("active", false)) or int(snapshot.get("snapshot_version", 0)) != 4:
		return false
	var route_value: Variant = snapshot.get("route", [])
	if typeof(route_value) != TYPE_ARRAY:
		return false
	var route: Array = route_value
	if route.is_empty():
		return false
	var safe_scrap_cost := maxi(0, scrap_cost)
	var safe_crystal_cost := maxi(0, crystal_cost)
	if scrap < safe_scrap_cost or crystals < safe_crystal_cost:
		return false
	var old_scrap := scrap
	var old_crystals := crystals
	var old_runs_started := runs_started
	var old_snapshot := saved_expedition.duplicate(true)
	scrap -= safe_scrap_cost
	crystals -= safe_crystal_cost
	runs_started += 1
	saved_expedition = snapshot.duplicate(true)
	if not save_now():
		scrap = old_scrap
		crystals = old_crystals
		runs_started = old_runs_started
		saved_expedition = old_snapshot
		return false
	changed.emit()
	return true

func register_item(item: Dictionary) -> void:
	var item_id := str(item.get("id", ""))
	if item_id.is_empty():
		return
	for existing in armory:
		if str(existing.get("id", "")) == item_id:
			return
	armory.append(item.duplicate(true))
	while armory.size() > 80:
		armory.pop_front()
	save_now()
	changed.emit()

func equip_item(item_id: String) -> bool:
	for item in armory:
		if str(item.get("id", "")) == item_id:
			var slot := str(item.get("slot", ""))
			if not InventorySystemScript.EQUIPMENT_SLOTS.has(slot):
				return false
			var old_loadout: Dictionary = loadout.duplicate(true)
			loadout[slot] = item.duplicate(true)
			if not save_now():
				loadout = old_loadout
				return false
			changed.emit()
			return true
	return false

func is_item_equipped(item_id: String) -> bool:
	if item_id.is_empty():
		return false
	for slot_value in loadout.keys():
		var item_value: Variant = loadout.get(str(slot_value), {})
		if typeof(item_value) == TYPE_DICTIONARY and str(item_value.get("id", "")) == item_id:
			return true
	return false

func get_armory_item(item_id: String) -> Dictionary:
	if item_id.is_empty():
		return {}
	for item_value in armory:
		if typeof(item_value) == TYPE_DICTIONARY and str(item_value.get("id", "")) == item_id:
			return item_value.duplicate(true)
	return {}

func upgrade_armory_item(item_id: String) -> Dictionary:
	if has_saved_expedition():
		return {"ok": false, "message": "Улучшение доступно только между экспедициями."}
	var item_index := -1
	for index in range(armory.size()):
		var item_value: Variant = armory[index]
		if typeof(item_value) == TYPE_DICTIONARY and str(item_value.get("id", "")) == item_id:
			item_index = index
			break
	if item_index < 0:
		return {"ok": false, "message": "Предмет не найден в арсенале."}
	var inventory_system = InventorySystemScript.new()
	var original: Dictionary = armory[item_index].duplicate(true)
	var cost: Dictionary = inventory_system.get_upgrade_cost(original)
	if not bool(cost.get("available", false)):
		return {"ok": false, "message": "Предмет достиг максимального уровня улучшения."}
	var scrap_cost := int(cost.get("scrap", 0))
	var crystal_cost := int(cost.get("crystals", 0))
	if scrap < scrap_cost or crystals < crystal_cost:
		return {"ok": false, "message": "Недостаточно ресурсов. Нужно %d материалов и %d кристаллов." % [scrap_cost, crystal_cost]}
	var upgraded: Dictionary = inventory_system.preview_upgrade_item(original)
	if upgraded.is_empty():
		return {"ok": false, "message": "Не удалось рассчитать улучшение этого предмета."}
	var old_scrap := scrap
	var old_crystals := crystals
	var old_armory: Array = armory.duplicate(true)
	var old_loadout: Dictionary = loadout.duplicate(true)
	scrap -= scrap_cost
	crystals -= crystal_cost
	armory[item_index] = upgraded.duplicate(true)
	for slot_value in InventorySystemScript.EQUIPMENT_SLOTS:
		var slot := str(slot_value)
		var equipped_value: Variant = loadout.get(slot, {})
		if typeof(equipped_value) == TYPE_DICTIONARY and str(equipped_value.get("id", "")) == item_id:
			loadout[slot] = upgraded.duplicate(true)
	if not save_now():
		scrap = old_scrap
		crystals = old_crystals
		armory = old_armory
		loadout = old_loadout
		return {"ok": false, "message": "Сохранение не удалось. Улучшение и списание ресурсов отменены."}
	changed.emit()
	return {"ok": true, "item": upgraded.duplicate(true), "scrap_spent": scrap_cost, "crystals_spent": crystal_cost, "message": "Предмет улучшен до уровня +%d." % int(upgraded.get("upgrade_level", 0))}

func salvage_armory_item(item_id: String) -> Dictionary:
	if has_saved_expedition():
		return {"ok": false, "message": "Разбор доступен только между экспедициями."}
	if is_item_equipped(item_id):
		return {"ok": false, "message": "Сначала снимите предмет. Экипировку нельзя разобрать."}
	var item_index := -1
	for index in range(armory.size()):
		var item_value: Variant = armory[index]
		if typeof(item_value) == TYPE_DICTIONARY and str(item_value.get("id", "")) == item_id:
			item_index = index
			break
	if item_index < 0:
		return {"ok": false, "message": "Предмет не найден в арсенале."}
	var inventory_system = InventorySystemScript.new()
	var item: Dictionary = armory[item_index].duplicate(true)
	var reward: Dictionary = inventory_system.get_salvage_reward(item)
	if reward.is_empty():
		return {"ok": false, "message": "Для этого предмета нельзя рассчитать возврат ресурсов."}
	var old_scrap := scrap
	var old_crystals := crystals
	var old_armory: Array = armory.duplicate(true)
	scrap += int(reward.get("scrap", 0))
	crystals += int(reward.get("crystals", 0))
	armory.remove_at(item_index)
	if not save_now():
		scrap = old_scrap
		crystals = old_crystals
		armory = old_armory
		return {"ok": false, "message": "Сохранение не удалось. Разбор и выдача ресурсов отменены."}
	changed.emit()
	return {"ok": true, "item_name": str(item.get("name", "Предмет")), "scrap_gained": int(reward.get("scrap", 0)), "crystals_gained": int(reward.get("crystals", 0)), "message": "Предмет разобран: +%d материалов и +%d кристаллов." % [int(reward.get("scrap", 0)), int(reward.get("crystals", 0))]}

func unequip_slot(slot: String) -> bool:
	if not InventorySystemScript.EQUIPMENT_SLOTS.has(slot):
		return false
	var old_loadout: Dictionary = loadout.duplicate(true)
	loadout[slot] = {}
	if not save_now():
		loadout = old_loadout
		return false
	changed.emit()
	return true

func record_victory() -> void:
	total_victories += 1

func record_boss_victory() -> void:
	total_bosses_defeated += 1

func record_elite_victory() -> void:
	total_elites_defeated += 1

func settle_expedition(earned: Dictionary, outcome: String, loops: int, hero_level: int, defeat_keep_ratio_override: float = -1.0, summary_metadata: Dictionary = {}, difficulty_record_key: String = "", challenge_score: int = 0, bosses: int = 0, elites: int = 0, final_loadout: Dictionary = {}, retained_run_items: Array = []) -> Dictionary:
	# A run ID is the idempotency key for every persistent reward, including dust
	# from overflowed items. A retried settlement returns the committed summary only.
	var requested_run_id := str(summary_metadata.get("run_id", "")).strip_edges()
	if not requested_run_id.is_empty() and settled_expedition_ids.has(requested_run_id):
		var already_committed: Dictionary = {}
		if str(last_summary.get("run_id", "")) == requested_run_id:
			already_committed = last_summary.duplicate(true)
		else:
			for history_value in expedition_history:
				if typeof(history_value) == TYPE_DICTIONARY and str(history_value.get("run_id", "")) == requested_run_id:
					already_committed = (history_value as Dictionary).duplicate(true)
					break
		if already_committed.is_empty():
			already_committed = {"run_id": requested_run_id, "outcome": outcome, "loops": maxi(0, loops), "hero_level": maxi(1, hero_level)}
		already_committed["_persistence_ok"] = true
		already_committed["_already_settled"] = true
		return already_committed
	# The completion is one durable transaction: rewards, checkpoint removal, rich
	# last-summary data, bounded history, difficulty record and loadout are committed
	# together. A crash cannot leave a paid-out run without its replay/history row.
	var old_scrap := scrap
	var old_crystals := crystals
	var old_echo_dust := echo_dust
	var old_settled_expedition_ids: Array = settled_expedition_ids.duplicate(true)
	var old_bestiary_trophies := bestiary_trophies.duplicate(true)
	var old_runs_completed := runs_completed
	var old_best_loop := best_loop
	var old_highest_unlocked_floor := highest_unlocked_floor
	var old_total_events_resolved := total_events_resolved
	var old_saved_expedition: Dictionary = saved_expedition.duplicate(true)
	var old_last_summary: Dictionary = last_summary.duplicate(true)
	var old_difficulty_records: Dictionary = difficulty_records.duplicate(true)
	var old_expedition_history: Array = expedition_history.duplicate(true)
	var old_loadout: Dictionary = loadout.duplicate(true)
	var old_armory: Array = armory.duplicate(true)
	var fallback_ratio := float(ContentRegistry.BALANCE.defeat_keep_ratio)
	var configured_ratio := fallback_ratio if defeat_keep_ratio_override < 0.0 else clampf(defeat_keep_ratio_override, 0.0, 1.0)
	var ratio: float = 1.0 if outcome == "return" else configured_ratio
	var ejection_items_value: Variant = earned.get("inventory_ejections", [])
	var ejection_items: Array = ejection_items_value if typeof(ejection_items_value) == TYPE_ARRAY else []
	var ejected_item_count := maxi(0, int(earned.get("inventory_ejections_count", ejection_items.size())))
	var raw_ejection_dust := -1
	if earned.has("inventory_ejections_dust"):
		raw_ejection_dust = clampi(int(earned.get("inventory_ejections_dust", 0)), 0, MAX_ECHO_DUST)
	else:
		# Legacy checkpoints only stored the most recent ejected item records.
		# Derive a conservative migration value from those records instead of dropping them.
		var ejection_inventory = InventorySystemScript.new()
		raw_ejection_dust = 0
		for ejected_item_value in ejection_items:
			if typeof(ejected_item_value) == TYPE_DICTIONARY:
				raw_ejection_dust = mini(MAX_ECHO_DUST, raw_ejection_dust + int(ejection_inventory.get_ejection_echo_dust(ejected_item_value)))
	var retained_ejection_dust := int(floor(float(raw_ejection_dust) * ratio))
	if outcome == "return":
		retained_ejection_dust = raw_ejection_dust
	elif raw_ejection_dust > 0 and ratio > 0.0:
		# A defeat can preserve a small trace of the overflow salvage, never more than
		# its normal retained-resource ratio. This also avoids zero dust for one common ejection.
		retained_ejection_dust = maxi(1, retained_ejection_dust)
	var echo_dust_before_cap := retained_ejection_dust
	var echo_dust_awarded := mini(echo_dust_before_cap, maxi(0, MAX_ECHO_DUST - echo_dust))
	var echo_dust_cap_lost := maxi(0, echo_dust_before_cap - echo_dust_awarded)
	var resource_system = ResourceSystemScript.new()
	var settled: Dictionary = resource_system.settle(earned, ratio)
	var kept_scrap := int(settled.get("scrap", 0))
	var kept_crystals := int(settled.get("crystals", 0))
	var earned_trophies := _normalize_trophy_counts(earned.get("trophy_drops", {}))
	var kept_trophies := _empty_trophy_counts()
	for trophy_id in TROPHY_IDS:
		kept_trophies[trophy_id] = int(floor(float(earned_trophies[trophy_id]) * ratio))
		bestiary_trophies[trophy_id] = mini(100000000, int(bestiary_trophies.get(trophy_id, 0)) + int(kept_trophies[trophy_id]))
	var events_resolved: int = maxi(0, int(earned.get("events_resolved", 0)))
	var event_history_value: Variant = earned.get("event_history", [])
	var event_history: Array = []
	if typeof(event_history_value) == TYPE_ARRAY:
		event_history = event_history_value.duplicate(true)
	total_events_resolved += events_resolved
	saved_expedition.clear()
	scrap += kept_scrap
	crystals += kept_crystals
	echo_dust = clampi(echo_dust + echo_dust_awarded, 0, MAX_ECHO_DUST)
	runs_completed += 1
	best_loop = maxi(best_loop, loops)
	var summary: Dictionary = {
		"outcome": outcome,
		"loops": loops,
		"hero_level": hero_level,
		"earned_scrap": int(earned.get("scrap", 0)),
		"earned_crystals": int(earned.get("crystals", 0)),
		"kept_scrap": kept_scrap,
		"kept_crystals": kept_crystals,
		"lost_scrap": maxi(0, int(earned.get("scrap", 0)) - kept_scrap),
		"lost_crystals": maxi(0, int(earned.get("crystals", 0)) - kept_crystals),
		"ejected_item_count": ejected_item_count,
		"earned_echo_dust": raw_ejection_dust,
		"kept_echo_dust": echo_dust_awarded,
		"lost_echo_dust": maxi(0, raw_ejection_dust - retained_ejection_dust),
		"echo_dust_cap_lost": echo_dust_cap_lost,
		"total_echo_dust": echo_dust,
		"earned_trophies": earned_trophies.duplicate(true),
		"kept_trophies": kept_trophies.duplicate(true),
		"lost_trophies": _subtract_trophy_counts(earned_trophies, kept_trophies),
		"bestiary_trophies": bestiary_trophies.duplicate(true),
		"victories": int(earned.get("victories", 0)),
		"bosses_defeated": maxi(0, int(earned.get("bosses_defeated", 0))),
		"elites_defeated": maxi(0, int(earned.get("elites_defeated", 0))),
		"events_resolved": events_resolved,
		"event_history": event_history,
		"retention": ratio
	}
	summary.merge(summary_metadata, true)
	# Unlock the next floor in the same durable transaction as the boss reward and summary.
	if bool(summary_metadata.get("floor_cleared", false)):
		var cleared_floor := clampi(int(summary_metadata.get("floor_number", 1)), 1, ContentRegistry.FLOOR_COUNT)
		highest_unlocked_floor = maxi(highest_unlocked_floor, mini(ContentRegistry.FLOOR_COUNT, cleared_floor + 1))
	# Core transaction fields are authoritative and cannot be overwritten by metadata.
	summary["outcome"] = outcome
	summary["loops"] = maxi(0, loops)
	summary["hero_level"] = maxi(1, hero_level)
	summary["earned_scrap"] = maxi(0, int(earned.get("scrap", 0)))
	summary["earned_crystals"] = maxi(0, int(earned.get("crystals", 0)))
	summary["kept_scrap"] = kept_scrap
	summary["kept_crystals"] = kept_crystals
	summary["lost_scrap"] = maxi(0, int(earned.get("scrap", 0)) - kept_scrap)
	summary["lost_crystals"] = maxi(0, int(earned.get("crystals", 0)) - kept_crystals)
	summary["ejected_item_count"] = ejected_item_count
	summary["earned_echo_dust"] = raw_ejection_dust
	summary["kept_echo_dust"] = echo_dust_awarded
	summary["lost_echo_dust"] = maxi(0, raw_ejection_dust - retained_ejection_dust)
	summary["echo_dust_cap_lost"] = echo_dust_cap_lost
	summary["total_echo_dust"] = echo_dust
	summary["retention"] = ratio

	var committed_record: Dictionary = {}
	if not difficulty_record_key.strip_edges().is_empty():
		var previous_record_value: Variant = difficulty_records.get(difficulty_record_key, {})
		committed_record = previous_record_value.duplicate(true) if typeof(previous_record_value) == TYPE_DICTIONARY else {}
		committed_record["runs"] = maxi(0, int(committed_record.get("runs", 0))) + 1
		committed_record["returns"] = maxi(0, int(committed_record.get("returns", 0))) + (1 if outcome == "return" else 0)
		committed_record["best_score"] = maxi(maxi(0, int(committed_record.get("best_score", 0))), maxi(0, challenge_score))
		committed_record["best_loops"] = maxi(maxi(0, int(committed_record.get("best_loops", 0))), maxi(0, loops))
		committed_record["bosses"] = maxi(0, int(committed_record.get("bosses", 0))) + maxi(0, bosses)
		committed_record["elites"] = maxi(0, int(committed_record.get("elites", 0))) + maxi(0, elites)
		difficulty_records[difficulty_record_key] = committed_record.duplicate(true)
	summary["difficulty_record"] = committed_record.duplicate(true)
	summary["difficulty_record_saved"] = not difficulty_record_key.strip_edges().is_empty()

	var summary_run_id := str(summary.get("run_id", ""))
	var history_saved := not summary_run_id.is_empty()
	if history_saved:
		var history_entry := _normalize_history_entry(summary)
		var existing_index := -1
		for index in range(expedition_history.size()):
			var old_entry_value: Variant = expedition_history[index]
			if typeof(old_entry_value) == TYPE_DICTIONARY and str(old_entry_value.get("run_id", "")) == summary_run_id:
				existing_index = index
				break
		if existing_index >= 0:
			expedition_history[existing_index] = history_entry
		else:
			expedition_history.append(history_entry)
		if expedition_history.size() > MAX_EXPEDITION_HISTORY:
			expedition_history = expedition_history.slice(expedition_history.size() - MAX_EXPEDITION_HISTORY)
	summary["history_saved"] = history_saved
	if not summary_run_id.is_empty() and not settled_expedition_ids.has(summary_run_id):
		settled_expedition_ids.append(summary_run_id)
	while settled_expedition_ids.size() > MAX_SETTLED_EXPEDITION_IDS:
		settled_expedition_ids.pop_front()
	last_summary = summary.duplicate(true)
	if not final_loadout.is_empty():
		loadout = final_loadout.duplicate(true)
	# Only gear that survived to settlement enters the permanent shelter armory.
	# Items ejected from the run backpack are intentionally absent; a later stage can
	# convert their ledger records into a dedicated resource without duplicating loot.
	var retained_ids: Dictionary = {}
	for old_item_value in armory:
		if typeof(old_item_value) == TYPE_DICTIONARY:
			var old_item: Dictionary = old_item_value
			retained_ids[str(old_item.get("id", ""))] = true
	var settlement_inventory = InventorySystemScript.new()
	for retained_value in retained_run_items:
		if typeof(retained_value) != TYPE_DICTIONARY:
			continue
		var retained_item: Dictionary = retained_value
		var retained_id := str(retained_item.get("id", ""))
		if retained_id.is_empty() or retained_ids.has(retained_id) or not settlement_inventory.can_equip_item(retained_item):
			continue
		armory.append(retained_item.duplicate(true))
		retained_ids[retained_id] = true
	while armory.size() > 80:
		armory.pop_front()

	if not save_now():
		scrap = old_scrap
		crystals = old_crystals
		echo_dust = old_echo_dust
		settled_expedition_ids = old_settled_expedition_ids
		bestiary_trophies = old_bestiary_trophies
		runs_completed = old_runs_completed
		best_loop = old_best_loop
		highest_unlocked_floor = old_highest_unlocked_floor
		total_events_resolved = old_total_events_resolved
		saved_expedition = old_saved_expedition
		last_summary = old_last_summary
		difficulty_records = old_difficulty_records
		expedition_history = old_expedition_history
		loadout = old_loadout
		armory = old_armory
		return {"_persistence_ok": false, "reason": "Не удалось надёжно сохранить итог экспедиции."}
	changed.emit()
	var result: Dictionary = last_summary.duplicate(true)
	result["_persistence_ok"] = true
	return result

func record_difficulty_result(preset_id: String, score: int, loops: int, outcome: String, bosses: int, elites: int) -> Dictionary:
	if preset_id.strip_edges().is_empty():
		return {}
	var old_records := difficulty_records.duplicate(true)
	var old_value: Variant = difficulty_records.get(preset_id, {})
	var record: Dictionary = old_value.duplicate(true) if typeof(old_value) == TYPE_DICTIONARY else {}
	record["runs"] = maxi(0, int(record.get("runs", 0))) + 1
	record["returns"] = maxi(0, int(record.get("returns", 0))) + (1 if outcome == "return" else 0)
	record["best_score"] = maxi(maxi(0, int(record.get("best_score", 0))), maxi(0, score))
	record["best_loops"] = maxi(maxi(0, int(record.get("best_loops", 0))), maxi(0, loops))
	record["bosses"] = maxi(0, int(record.get("bosses", 0))) + maxi(0, bosses)
	record["elites"] = maxi(0, int(record.get("elites", 0))) + maxi(0, elites)
	difficulty_records[preset_id] = record
	if not save_now():
		difficulty_records = old_records
		return {"saved": false, "record": {}}
	changed.emit()
	return {"saved": true, "record": record.duplicate(true)}

func _normalize_history_entry(source: Dictionary) -> Dictionary:
	var tiles_value: Variant = source.get("tiles", [])
	var tiles: Array = []
	if typeof(tiles_value) == TYPE_ARRAY:
		for tile_value in tiles_value:
			if typeof(tile_value) == TYPE_STRING and not tiles.has(str(tile_value)) and tiles.size() < 5:
				tiles.append(str(tile_value))
	var decisions_value: Variant = source.get("event_decisions", [])
	var decisions: Array = []
	if typeof(decisions_value) == TYPE_ARRAY:
		for decision_value in decisions_value:
			if typeof(decision_value) == TYPE_STRING and decisions.size() < 5:
				decisions.append(str(decision_value).substr(0, 120))
	var source_loadout_value: Variant = source.get("start_loadout_ids", {})
	var start_loadout_ids: Dictionary = {}
	if typeof(source_loadout_value) == TYPE_DICTIONARY:
		var source_loadout: Dictionary = source_loadout_value
		for slot_value in InventorySystemScript.EQUIPMENT_SLOTS:
			var slot := str(slot_value)
			var item_id_value: Variant = source_loadout.get(slot, "")
			if typeof(item_id_value) == TYPE_STRING:
				start_loadout_ids[slot] = str(item_id_value).substr(0, 100)
	return {
		"run_id": str(source.get("run_id", "")),
		"timestamp_unix": maxi(0, int(source.get("timestamp_unix", 0))),
		"date": str(source.get("date", "Дата неизвестна")).substr(0, 40),
		"game_version": str(source.get("game_version", "unknown")).substr(0, 24),
		"telemetry_schema": clampi(int(source.get("telemetry_schema", 0)), 0, 1),
		"measurement_quality": str(source.get("measurement_quality", "legacy_partial")).substr(0, 24),
		"run_elapsed_seconds": maxi(0, int(source.get("run_elapsed_seconds", 0))),
		"start_hp": maxi(0, int(source.get("start_hp", 0))),
		"start_max_hp": maxi(0, int(source.get("start_max_hp", 0))),
		"start_attack": maxi(0, int(source.get("start_attack", 0))),
		"start_defense": maxi(0, int(source.get("start_defense", 0))),
		"start_profile_scrap": maxi(0, int(source.get("start_profile_scrap", 0))),
		"start_profile_crystals": maxi(0, int(source.get("start_profile_crystals", 0))),
		"contract_scrap_cost": maxi(0, int(source.get("contract_scrap_cost", 0))),
		"contract_crystal_cost": maxi(0, int(source.get("contract_crystal_cost", 0))),
		"end_hp": maxi(0, int(source.get("end_hp", 0))),
		"end_max_hp": maxi(0, int(source.get("end_max_hp", 0))),
		"end_attack": maxi(0, int(source.get("end_attack", 0))),
		"end_defense": maxi(0, int(source.get("end_defense", 0))),
		"road_placements": maxi(0, int(source.get("road_placements", 0))),
		"world_placements": maxi(0, int(source.get("world_placements", 0))),
		"route_cells": maxi(0, int(source.get("route_cells", 0))),
		"processed_steps": maxi(0, int(source.get("processed_steps", 0))),
		"start_loadout_ids": start_loadout_ids,
		"seed": maxi(0, int(source.get("seed", 0))),
		"difficulty_id": str(source.get("difficulty_id", "standard")).substr(0, 32),
		"modifier_id": str(source.get("modifier_id", "standard")).substr(0, 32),
		"difficulty_name": str(source.get("difficulty_name", "Стандарт")).substr(0, 48),
		"modifier_name": str(source.get("modifier_name", "Обычная экспедиция")).substr(0, 64),
		"expedition_mode_id": str(source.get("expedition_mode_id", "standard")).substr(0, 32),
		"expedition_mode_name": str(source.get("expedition_mode_name", "Обычная экспедиция")).substr(0, 64),
		"endgame_completed": bool(source.get("endgame_completed", false)),
		"endgame_target_loops": clampi(int(source.get("endgame_target_loops", 0)), 0, 100),
		"endgame_target_bosses": clampi(int(source.get("endgame_target_bosses", 0)), 0, 100),
		"outcome": "return" if str(source.get("outcome", "defeat")) == "return" else "defeat",
		"loops": maxi(0, int(source.get("loops", 0))),
		"hero_level": maxi(1, int(source.get("hero_level", 1))),
		"challenge_score": maxi(0, int(source.get("challenge_score", 0))),
		"victories": maxi(0, int(source.get("victories", 0))),
		"bosses_defeated": maxi(0, int(source.get("bosses_defeated", 0))),
		"elites_defeated": maxi(0, int(source.get("elites_defeated", 0))),
		"events_resolved": maxi(0, int(source.get("events_resolved", 0))),
		"earned_scrap": maxi(0, int(source.get("earned_scrap", 0))),
		"earned_crystals": maxi(0, int(source.get("earned_crystals", 0))),
		"earned_trophies": _normalize_trophy_counts(source.get("earned_trophies", {})),
		"kept_trophies": _normalize_trophy_counts(source.get("kept_trophies", {})),
		"kept_scrap": maxi(0, int(source.get("kept_scrap", 0))),
		"kept_crystals": maxi(0, int(source.get("kept_crystals", 0))),
		"lost_scrap": maxi(0, int(source.get("lost_scrap", 0))),
		"lost_crystals": maxi(0, int(source.get("lost_crystals", 0))),
		"retention_percent": clampi(int(source.get("retention_percent", 40)), 0, 100),
		"danger": clampf(float(source.get("danger", 1.0)), 0.0, 100.0),
		"objective_name": str(source.get("objective_name", "")).substr(0, 80),
		"objective_completed": bool(source.get("objective_completed", false)),
		"contract_name": str(source.get("contract_name", "")).substr(0, 80),
		"contract_status": str(source.get("contract_status", "none")).substr(0, 24),
		"tiles": tiles,
		"event_decisions": decisions
	}

func record_expedition_history(summary: Dictionary) -> bool:
	# run_id is unique for the lifetime of a profile. Replaying the same summary
	# replaces its journal row rather than creating a duplicate entry.
	var run_id := str(summary.get("run_id", ""))
	if run_id.is_empty():
		return false
	var entry := _normalize_history_entry(summary)
	var previous := expedition_history.duplicate(true)
	var found := false
	for index in range(expedition_history.size()):
		var old_entry_value: Variant = expedition_history[index]
		if typeof(old_entry_value) == TYPE_DICTIONARY and str(old_entry_value.get("run_id", "")) == run_id:
			expedition_history[index] = entry
			found = true
			break
	if not found:
		expedition_history.append(entry)
	if expedition_history.size() > MAX_EXPEDITION_HISTORY:
		expedition_history = expedition_history.slice(expedition_history.size() - MAX_EXPEDITION_HISTORY)
	if not save_now():
		expedition_history = previous
		return false
	changed.emit()
	return true

func get_expedition_history(filter_id: String = "all", limit: int = MAX_EXPEDITION_HISTORY) -> Array:
	var rows: Array = []
	var safe_limit := clampi(limit, 1, MAX_EXPEDITION_HISTORY)
	for index in range(expedition_history.size() - 1, -1, -1):
		var entry_value: Variant = expedition_history[index]
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		var outcome := str(entry.get("outcome", "defeat"))
		if filter_id == "returns" and outcome != "return":
			continue
		if filter_id == "defeats" and outcome != "defeat":
			continue
		rows.append(entry.duplicate(true))
		if rows.size() >= safe_limit:
			break
	return rows

func export_save_data() -> Dictionary:
	return {
		"scrap": scrap,
		"crystals": crystals,
		"echo_dust": echo_dust,
		"settled_expedition_ids": settled_expedition_ids.duplicate(true),
		"bestiary_trophies": bestiary_trophies.duplicate(true),
		"buildings": buildings.duplicate(true),
		"loadout": loadout.duplicate(true),
		"armory": armory.duplicate(true),
		"runs_started": runs_started,
		"runs_completed": runs_completed,
		"highest_unlocked_floor": highest_unlocked_floor,
		"best_loop": best_loop,
		"total_victories": total_victories,
		"total_bosses_defeated": total_bosses_defeated,
		"total_elites_defeated": total_elites_defeated,
		"total_events_resolved": total_events_resolved,
		"unlocked_nodes": unlocked_nodes.duplicate(true),
		"research_investments": research_investments.duplicate(true),
		"saved_expedition": saved_expedition.duplicate(true),
		"tutorial_page": tutorial_page,
		"tutorial_completed": tutorial_completed,
		"settings": settings.duplicate(true),
		"last_summary": last_summary.duplicate(true),
		"difficulty_records": difficulty_records.duplicate(true),
		"expedition_history": expedition_history.duplicate(true)
	}

func save_now() -> bool:
	return SaveSystem.save_game(export_save_data())

func reset_progress() -> void:
	scrap = 60
	crystals = 14
	echo_dust = 0
	settled_expedition_ids.clear()
	bestiary_trophies = _empty_trophy_counts()
	buildings = DEFAULT_BUILDINGS.duplicate(true)
	loadout = {"weapon": {}, "helmet": {}, "armor": {}, "shield": {}, "amulet": {}, "core": {}}
	armory.clear()
	runs_started = 0
	runs_completed = 0
	highest_unlocked_floor = 1
	best_loop = 0
	total_victories = 0
	total_bosses_defeated = 0
	total_elites_defeated = 0
	total_events_resolved = 0
	unlocked_nodes.clear()
	research_investments.clear()
	saved_expedition.clear()
	tutorial_page = 0
	tutorial_completed = false
	load_notice = ""
	last_summary = {}
	difficulty_records.clear()
	expedition_history.clear()
	SaveSystem.reset_save()
	save_now()
	changed.emit()

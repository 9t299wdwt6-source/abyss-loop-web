extends Node

const SAVE_PATH := "user://loop_roguelite_save.json"
const SAVE_TEMP_PATH := "user://loop_roguelite_save.tmp.json"
const BACKUP_PATH := "user://loop_roguelite_save.backup.json"
const BACKUP_TEMP_PATH := "user://loop_roguelite_save.backup.tmp.json"
const CORRUPT_PATH := "user://loop_roguelite_save.corrupt.json"
const CORRUPT_TEMP_PATH := "user://loop_roguelite_save.corrupt.tmp.json"
const SAVE_VERSION := 3
const SAVE_ENVELOPE_VERSION := 2
const SAVE_INTEGRITY_ALGORITHM := "sha256"
const MIN_SUPPORTED_VERSION := 1
const SAVE_FILE_NAME := "loop_roguelite_save.json"
const BACKUP_FILE_NAME := "loop_roguelite_save.backup.json"
const LEGACY_PROFILE_PREFIXES := ["abyss loop", "looproguelite"]
const MAX_SNAPSHOT_ROUTE_CELLS := 128
const TileSystemScript = preload("res://scripts/systems/tile_system.gd")
const MAX_SNAPSHOT_LOG_LINES := 300

var last_load_status: String = "not_loaded"

func save_game(payload: Dictionary) -> bool:
	if not _validate_save_data(payload):
		push_warning("Сохранение отменено: данные не прошли проверку целостности.")
		return false

	var encoded := _encode_save(payload)
	if encoded.is_empty():
		push_warning("Сохранение отменено: не удалось сформировать контрольную сумму.")
		return false
	var previous_text := ""
	var previous_is_valid := false
	if FileAccess.file_exists(SAVE_PATH):
		previous_text = FileAccess.get_file_as_string(SAVE_PATH)
		previous_is_valid = not _decode_save(previous_text).is_empty()

	# Preserve the current valid save before replacing it. If backup creation fails,
	# leave the primary untouched instead of gambling with the only good copy.
	if previous_is_valid:
		if not _write_atomic_text(BACKUP_PATH, BACKUP_TEMP_PATH, previous_text):
			push_warning("Не удалось обновить резервную копию; основное сохранение оставлено без изменений.")
			return false
	elif FileAccess.file_exists(SAVE_PATH) and not previous_text.is_empty():
		# Keep the raw damaged file for diagnosis before a later valid save replaces it.
		if not _write_atomic_text(CORRUPT_PATH, CORRUPT_TEMP_PATH, previous_text):
			push_warning("Повреждённый файл не удалось архивировать; новое сохранение не записано.")
			return false

	if not _write_atomic_text(SAVE_PATH, SAVE_TEMP_PATH, encoded):
		push_warning("Не удалось безопасно записать новое сохранение.")
		return false
	last_load_status = "saved"
	return true

func load_game() -> Dictionary:
	_recover_interrupted_replacements()
	if not FileAccess.file_exists(SAVE_PATH):
		# A backup can survive when the primary file is deleted or lost. Restore it
		# atomically before considering a legacy profile or a new empty game.
		var backup_data := _load_backup()
		if not backup_data.is_empty():
			var recovered_text := _encode_save(backup_data)
			if _write_atomic_text(SAVE_PATH, SAVE_TEMP_PATH, recovered_text):
				last_load_status = "recovered_backup_missing_primary"
				push_warning("Основной файл отсутствовал; восстановлено последнее доступное резервное сохранение.")
				return backup_data
			last_load_status = "backup_recovery_failed"
			push_error("Резервная копия доступна, но её не удалось безопасно восстановить.")
			return {}
		var migrated_data := _try_migrate_legacy_profile()
		if not migrated_data.is_empty():
			return migrated_data
		if last_load_status == "legacy_profile_migration_failed":
			return {}
		last_load_status = "no_save"
		return {}

	var raw := FileAccess.get_file_as_string(SAVE_PATH)
	var normalized := _decode_save(raw)
	if not normalized.is_empty():
		last_load_status = "loaded_primary"
		return normalized.get("data", {})

	push_warning("Основное сохранение повреждено или несовместимо; пробуется резервная копия.")
	var backup := _load_backup()
	if not backup.is_empty():
		# Quarantine the damaged primary before replacing it. If quarantine fails,
		# keep the on-disk primary untouched and still return the validated backup
		# in memory for this session; never silently discard the only raw evidence.
		if not raw.is_empty() and not _write_atomic_text(CORRUPT_PATH, CORRUPT_TEMP_PATH, raw):
			last_load_status = "recovered_backup_quarantine_failed"
			push_warning("Резервная копия прочитана, но повреждённый основной файл не заменён: не удалось сохранить его диагностическую копию.")
			return backup
		var recovered_text := _encode_save(backup)
		if not recovered_text.is_empty() and _write_atomic_text(SAVE_PATH, SAVE_TEMP_PATH, recovered_text):
			last_load_status = "recovered_backup"
			push_warning("Прогресс восстановлен из проверенной резервной копии; основной файл сохранения восстановлен.")
			return backup
		last_load_status = "recovered_backup_primary_restore_failed"
		push_warning("Проверенная резервная копия загружена в память, но восстановить основной файл не удалось.")
		return backup

	last_load_status = "corrupt_no_backup"
	push_warning("Не удалось прочитать сохранение или резервную копию. Исходные файлы не удалены; новая игра начнётся с настройками по умолчанию.")
	return {}

func _try_migrate_legacy_profile() -> Dictionary:
	# The current project name is now stable ("Abyss Loop"). Earlier prototypes
	# used their version in config/name, so look for a valid save in those sibling
	# app_userdata folders only when the stable profile has no primary/backup.
	# The release gate sets this flag to keep QA runs isolated from real user data.
	if OS.get_environment("ABYSS_LOOP_DISABLE_LEGACY_PROFILE_IMPORT") == "1":
		return {}
	var current_user_dir := OS.get_user_data_dir()
	var profiles_root := current_user_dir.get_base_dir()
	var current_profile_name := current_user_dir.get_file()
	var candidate := _find_latest_legacy_profile_payload(profiles_root, current_profile_name)
	if candidate.is_empty():
		return {}
	var candidate_data: Variant = candidate.get("data", {})
	if typeof(candidate_data) != TYPE_DICTIONARY or candidate_data.is_empty():
		return {}
	if not _write_atomic_text(SAVE_PATH, SAVE_TEMP_PATH, _encode_save(candidate_data)):
		last_load_status = "legacy_profile_migration_failed"
		push_error("Найдено старое сохранение, но его не удалось безопасно перенести. Исходный профиль не изменён.")
		return {}
	last_load_status = "migrated_legacy_profile"
	push_warning("Прогресс перенесён из предыдущего профиля Abyss Loop. Исходное сохранение оставлено на месте.")
	return candidate_data.duplicate(true)

func _find_latest_legacy_profile_payload(profiles_root: String, current_profile_name: String) -> Dictionary:
	# Publicly callable for deterministic isolated regression tests; this function
	# only reads candidate files and never deletes or edits a legacy profile.
	var directory := DirAccess.open(profiles_root)
	if directory == null:
		return {}
	var selected: Dictionary = {}
	var selected_modified: int = -1
	directory.list_dir_begin()
	while true:
		var profile_name: String = directory.get_next()
		if profile_name.is_empty():
			break
		if not directory.current_is_dir() or profile_name == current_profile_name:
			continue
		if not _is_legacy_profile_name(profile_name):
			continue
		var profile_path := profiles_root.path_join(profile_name)
		var primary_path := profile_path.path_join(SAVE_FILE_NAME)
		var backup_path := profile_path.path_join(BACKUP_FILE_NAME)
		var source_path := ""
		var decoded: Dictionary = {}
		if FileAccess.file_exists(primary_path):
			decoded = _decode_save(FileAccess.get_file_as_string(primary_path))
			if not decoded.is_empty():
				source_path = primary_path
		if decoded.is_empty() and FileAccess.file_exists(backup_path):
			decoded = _decode_save(FileAccess.get_file_as_string(backup_path))
			if not decoded.is_empty():
				source_path = backup_path
		if decoded.is_empty() or source_path.is_empty():
			continue
		var modified := FileAccess.get_modified_time(source_path)
		if modified > selected_modified:
			selected_modified = modified
			selected = {
				"data": decoded.get("data", {}).duplicate(true),
				"source_profile": profile_name,
				"source_file": source_path.get_file(),
				"modified": modified
			}
	directory.list_dir_end()
	return selected

func _is_legacy_profile_name(profile_name: String) -> bool:
	var lowered := profile_name.to_lower()
	if lowered == OS.get_user_data_dir().get_file().to_lower():
		return false
	for prefix_value in LEGACY_PROFILE_PREFIXES:
		var prefix := str(prefix_value)
		if prefix == "abyss loop":
			if lowered.begins_with(prefix) and lowered.contains("prototype"):
				return true
		elif lowered.begins_with(prefix):
			return true
	return false

func _recover_interrupted_replacements() -> void:
	_recover_one_replacement(SAVE_PATH, SAVE_TEMP_PATH)
	_recover_one_replacement(BACKUP_PATH, BACKUP_TEMP_PATH)

func _recover_one_replacement(target_path: String, temporary_path: String) -> void:
	var target_exists := FileAccess.file_exists(target_path)
	var temporary_exists := FileAccess.file_exists(temporary_path)
	var rollback_path := target_path + ".previous.tmp"
	var rollback_exists := FileAccess.file_exists(rollback_path)
	var target_valid := target_exists and not _decode_save(FileAccess.get_file_as_string(target_path)).is_empty()
	var temporary_valid := temporary_exists and not _decode_save(FileAccess.get_file_as_string(temporary_path)).is_empty()
	var rollback_valid := rollback_exists and not _decode_save(FileAccess.get_file_as_string(rollback_path)).is_empty()

	# A completed temporary file represents a fully flushed transaction. Recover it
	# if a process stopped between the write and the final rename.
	if not target_valid and temporary_valid:
		if target_exists:
			var raw_target := FileAccess.get_file_as_string(target_path)
			if target_path == SAVE_PATH and not raw_target.is_empty():
				_write_atomic_text(CORRUPT_PATH, CORRUPT_TEMP_PATH, raw_target)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(target_path))
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(target_path)) == OK:
			if rollback_exists:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(rollback_path))
			push_warning("Восстановлен завершённый временный файл сохранения после прерванной записи.")
			return

	if not target_valid and rollback_valid:
		if target_exists:
			var raw_invalid := FileAccess.get_file_as_string(target_path)
			if target_path == SAVE_PATH and not raw_invalid.is_empty():
				_write_atomic_text(CORRUPT_PATH, CORRUPT_TEMP_PATH, raw_invalid)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(target_path))
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(rollback_path), ProjectSettings.globalize_path(target_path)) == OK:
			if temporary_exists:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
			push_warning("Восстановлена предыдущая версия файла сохранения после прерванной замены.")
			return

	if target_valid:
		if temporary_exists:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		if rollback_exists:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(rollback_path))

func _decode_save(raw: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	if typeof(parsed.get("version", null)) != TYPE_INT:
		return {}
	var version: int = int(parsed.get("version", -1))
	var data_value: Variant = parsed.get("data", null)
	if version < MIN_SUPPORTED_VERSION or version > SAVE_VERSION or typeof(data_value) != TYPE_DICTIONARY:
		return {}
	# Keep the payload schema version independent from the file envelope version.
	# Legacy files omit envelope_version (equivalent to envelope v1) and remain
	# loadable; envelope v2 is integrity-aware and cannot omit its checksum.
	var envelope_version_value: Variant = parsed.get("envelope_version", 1)
	if typeof(envelope_version_value) != TYPE_INT:
		return {}
	var envelope_version: int = int(envelope_version_value)
	if envelope_version < 1 or envelope_version > SAVE_ENVELOPE_VERSION:
		return {}
	if envelope_version >= 2 and not parsed.has("integrity"):
		return {}

	# New saves include a checksum of canonical JSON. Legacy envelopes without an
	# integrity object remain supported for backward compatibility; malformed or
	# mismatched checksums are rejected before schema migration or gameplay use.
	if parsed.has("integrity"):
		var integrity_value: Variant = parsed.get("integrity", null)
		if typeof(integrity_value) != TYPE_DICTIONARY:
			return {}
		var integrity: Dictionary = integrity_value
		var algorithm_value: Variant = integrity.get("algorithm", null)
		var checksum_value: Variant = integrity.get("checksum", null)
		if typeof(algorithm_value) != TYPE_STRING or str(algorithm_value) != SAVE_INTEGRITY_ALGORITHM:
			return {}
		if typeof(checksum_value) != TYPE_STRING or not str(checksum_value).is_valid_hex_number(false) or str(checksum_value).length() != 64:
			return {}
		var checksum_data: Dictionary = data_value
		if str(checksum_value).to_lower() != _payload_checksum(checksum_data):
			return {}

	var data: Dictionary = data_value.duplicate(true)
	# Version 1 stores permanent progress only. Version 2 added research and
	# expedition checkpoints. Version 3 adds tutorial progress.
	if version < 2:
		data["unlocked_nodes"] = []
		data["saved_expedition"] = {}
	if version < 3:
		data["tutorial_page"] = 0
		data["tutorial_completed"] = false

	if not _validate_save_data(data):
		return {}
	return {"version": SAVE_VERSION, "data": data}


func _encode_save(payload: Dictionary) -> String:
	var copied: Dictionary = payload.duplicate(true)
	var checksum := _payload_checksum(copied)
	if checksum.length() != 64:
		return ""
	var packed := {
		"version": SAVE_VERSION,
		"envelope_version": SAVE_ENVELOPE_VERSION,
		"data": copied,
		"integrity": {
			"algorithm": SAVE_INTEGRITY_ALGORITHM,
			"checksum": checksum
		}
	}
	return JSON.stringify(packed, "\t")

func _payload_checksum(payload: Dictionary) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(_canonical_json(payload).to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()

func _canonical_json(value: Variant) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary: Dictionary = value
		var keys: Array = dictionary.keys()
		keys.sort()
		var entries: Array[String] = []
		for key in keys:
			entries.append(JSON.stringify(str(key)) + ":" + _canonical_json(dictionary[key]))
		return "{" + ",".join(entries) + "}"
	if typeof(value) == TYPE_ARRAY:
		var values: Array[String] = []
		for entry in value:
			values.append(_canonical_json(entry))
		return "[" + ",".join(values) + "]"
	return JSON.stringify(value)

func _validate_save_data(data: Dictionary) -> bool:
	for key in ["scrap", "crystals", "runs_started", "runs_completed", "best_loop", "total_victories", "total_bosses_defeated", "total_elites_defeated", "total_events_resolved"]:
		if data.has(key) and not _is_non_negative_integer(data[key]):
			return false

	var buildings_value: Variant = data.get("buildings", {})
	if typeof(buildings_value) != TYPE_DICTIONARY:
		return false
	for building_id_value in buildings_value.keys():
		var building_id := str(building_id_value)
		if not ContentRegistry.BUILDINGS.has(building_id):
			return false
		var level_value: Variant = buildings_value[building_id]
		if not _is_non_negative_integer(level_value):
			return false
		if int(level_value) > int(ContentRegistry.BUILDINGS[building_id].get("max_level", 5)):
			return false

	var loadout_value: Variant = data.get("loadout", {"weapon": {}, "armor": {}, "core": {}})
	if typeof(loadout_value) != TYPE_DICTIONARY:
		return false
	for slot in ["weapon", "armor", "core"]:
		var item_value: Variant = loadout_value.get(slot, {})
		if typeof(item_value) != TYPE_DICTIONARY or not _validate_item(item_value, slot):
			return false

	var armory_value: Variant = data.get("armory", [])
	if typeof(armory_value) != TYPE_ARRAY or armory_value.size() > 80:
		return false
	for item_value in armory_value:
		if typeof(item_value) != TYPE_DICTIONARY or not _validate_item(item_value):
			return false

	var unlocks_value: Variant = data.get("unlocked_nodes", [])
	if typeof(unlocks_value) != TYPE_ARRAY or unlocks_value.size() > 256:
		return false
	for unlock_value in unlocks_value:
		if typeof(unlock_value) != TYPE_STRING or str(unlock_value).is_empty():
			return false

	# Optional for legacy saves. Unknown stable IDs are allowed so temporary content
	# removal doesn't erase the purchase history needed by a later respec.
	var investments_value: Variant = data.get("research_investments", {})
	if typeof(investments_value) != TYPE_DICTIONARY or investments_value.size() > 256:
		return false
	for research_id_value in investments_value.keys():
		var research_id := str(research_id_value)
		var investment_value: Variant = investments_value[research_id_value]
		if research_id.is_empty() or typeof(investment_value) != TYPE_DICTIONARY:
			return false
		for cost_key in ["scrap", "crystals"]:
			var cost_value: Variant = investment_value.get(cost_key, 0)
			if not _is_non_negative_integer(cost_value) or int(cost_value) > 1000000:
				return false

	var settings_value: Variant = data.get("settings", {"master_volume": 0.8, "music_volume": 0.7, "effects_volume": 0.85})
	if typeof(settings_value) != TYPE_DICTIONARY:
		return false
	for setting_key in ["master_volume", "music_volume", "effects_volume"]:
		if settings_value.has(setting_key):
			var setting_value: Variant = settings_value[setting_key]
			if not _is_number(setting_value) or float(setting_value) < 0.0 or float(setting_value) > 1.0:
				return false
	for setting_key in ["ui_scale", "animation_speed"]:
		if settings_value.has(setting_key):
			var setting_value: Variant = settings_value[setting_key]
			if not _is_number(setting_value):
				return false
			var minimum := 0.85 if setting_key == "ui_scale" else 0.5
			var maximum := 1.10 if setting_key == "ui_scale" else 1.5
			if float(setting_value) < minimum or float(setting_value) > maximum:
				return false
	if settings_value.has("window_mode") and not ["windowed", "fullscreen"].has(str(settings_value["window_mode"])):
		return false
	for setting_key in ["reduced_motion", "reduce_flashes", "high_contrast", "status_symbols"]:
		if settings_value.has(setting_key) and typeof(settings_value[setting_key]) != TYPE_BOOL:
			return false

	var summary_value: Variant = data.get("last_summary", {})
	if typeof(summary_value) != TYPE_DICTIONARY:
		return false
	# Recent expedition history is optional for legacy saves and capped to keep the
	# profile small. Validate rows before accepting a hand-edited/corrupt payload.
	var history_value: Variant = data.get("expedition_history", [])
	if typeof(history_value) != TYPE_ARRAY or history_value.size() > 50:
		return false
	var history_ids := {}
	for history_entry_value in history_value:
		if typeof(history_entry_value) != TYPE_DICTIONARY:
			return false
		var history_entry: Dictionary = history_entry_value
		var run_id := str(history_entry.get("run_id", ""))
		if run_id.is_empty() or run_id.length() > 100 or history_ids.has(run_id):
			return false
		history_ids[run_id] = true
		if not _is_non_negative_integer(history_entry.get("timestamp_unix", 0)) or not _is_non_negative_integer(history_entry.get("seed", 0)):
			return false
		if not _is_non_negative_integer(history_entry.get("loops", 0)) or not _is_non_negative_integer(history_entry.get("hero_level", 1)):
			return false
		if str(history_entry.get("outcome", "defeat")) not in ["return", "defeat"]:
			return false
		for metric_key in ["challenge_score", "victories", "bosses_defeated", "elites_defeated", "events_resolved", "earned_scrap", "earned_crystals", "kept_scrap", "kept_crystals", "lost_scrap", "lost_crystals", "retention_percent", "telemetry_schema", "run_elapsed_seconds", "start_hp", "start_max_hp", "start_attack", "start_defense", "start_profile_scrap", "start_profile_crystals", "contract_scrap_cost", "contract_crystal_cost", "end_hp", "end_max_hp", "end_attack", "end_defense", "road_placements", "world_placements", "route_cells", "processed_steps"]:
			if not _is_non_negative_integer(history_entry.get(metric_key, 0)):
				return false
		if int(history_entry.get("telemetry_schema", 0)) > 1:
			return false
		var loadout_ids_value: Variant = history_entry.get("start_loadout_ids", {})
		if typeof(loadout_ids_value) != TYPE_DICTIONARY:
			return false
		if loadout_ids_value.size() > 3:
			return false
		for slot_value in loadout_ids_value.keys():
			if str(slot_value) not in ["weapon", "armor", "core"] or typeof(loadout_ids_value[slot_value]) != TYPE_STRING or str(loadout_ids_value[slot_value]).length() > 100:
				return false
	var tutorial_page_value: Variant = data.get("tutorial_page", 0)
	if not _is_non_negative_integer(tutorial_page_value) or int(tutorial_page_value) > 5:
		return false
	if data.has("tutorial_completed") and typeof(data["tutorial_completed"]) != TYPE_BOOL:
		return false

	var snapshot_value: Variant = data.get("saved_expedition", {})
	if typeof(snapshot_value) != TYPE_DICTIONARY:
		return false
	if not snapshot_value.is_empty() and bool(snapshot_value.get("active", false)) and not _validate_expedition_snapshot(snapshot_value):
		return false
	return true


func _validate_item(item: Dictionary, expected_slot: String = "") -> bool:
	if item.is_empty():
		return true
	if str(item.get("id", "")).is_empty():
		return false
	var slot := str(item.get("slot", expected_slot))
	if not ["weapon", "armor", "core"].has(slot):
		return false
	if not expected_slot.is_empty() and slot != expected_slot:
		return false
	for stat_key in ["attack", "defense", "hp", "rank", "upgrade_level", "kill_heal", "tile_scrap", "event_heal", "bleed_damage", "barrier_on_encounter"]:
		if item.has(stat_key) and (not _is_non_negative_integer(item[stat_key]) or int(item[stat_key]) > 10000):
			return false
	if item.has("upgrade_level") and int(item.get("upgrade_level", 0)) > 10:
		return false
	for stat_key in ["speed", "crit", "reward_bonus", "tile_spawn_bonus", "power", "bleed_chance"]:
		if not item.has(stat_key):
			continue
		if not _is_number(item[stat_key]):
			return false
		var numeric_value := float(item[stat_key])
		if not is_finite(numeric_value):
			return false
		match stat_key:
			"speed":
				if numeric_value < 0.0 or numeric_value > 1.5:
					return false
			"crit":
				if numeric_value < 0.0 or numeric_value > 0.75:
					return false
			"bleed_chance":
				if numeric_value < 0.0 or numeric_value > 0.5:
					return false
			"reward_bonus":
				if numeric_value < 0.0 or numeric_value > 2.0:
					return false
			"tile_spawn_bonus":
				if numeric_value < -0.5 or numeric_value > 0.5:
					return false
			"power":
				if numeric_value < 0.0 or numeric_value > 1000000.0:
					return false
	return true

func migrate_expedition_snapshot(snapshot: Dictionary) -> Dictionary:
	# Snapshot schema is independent from the permanent-save envelope.
	# V1: route-attached tiles; V2: separate field; V3: contracts; V4: generic combat statuses.
	var version := int(snapshot.get("snapshot_version", -1))
	if version == 1:
		var migrated_v1 := snapshot.duplicate(true)
		migrated_v1["snapshot_version"] = 2
		migrated_v1["world_tiles"] = {}
		migrated_v1["field_schema"] = 1
		return migrate_expedition_snapshot(migrated_v1)
	if version == 2:
		var migrated_v2 := snapshot.duplicate(true)
		var old_field_schema := int(migrated_v2.get("field_schema", 1))
		if typeof(migrated_v2.get("world_tiles", null)) != TYPE_DICTIONARY or old_field_schema < 2:
			migrated_v2["world_tiles"] = {}
		migrated_v2["field_schema"] = 2
		migrated_v2["run_contract"] = {}
		migrated_v2["snapshot_version"] = 3
		return migrate_expedition_snapshot(migrated_v2)
	if version == 3:
		var migrated_v3 := snapshot.duplicate(true)
		if typeof(migrated_v3.get("world_tiles", null)) != TYPE_DICTIONARY:
			migrated_v3["world_tiles"] = {}
		if int(migrated_v3.get("field_schema", 1)) < 2:
			migrated_v3["world_tiles"] = {}
		migrated_v3["field_schema"] = 2
		if typeof(migrated_v3.get("run_contract", null)) != TYPE_DICTIONARY:
			migrated_v3["run_contract"] = {}
		_normalize_snapshot_entity_statuses(migrated_v3, "hero")
		_normalize_snapshot_entity_statuses(migrated_v3, "enemy")
		var encounter_value: Variant = migrated_v3.get("encounter_enemies", [])
		if typeof(encounter_value) == TYPE_ARRAY:
			var migrated_encounters: Array = encounter_value.duplicate(true)
			for index in range(migrated_encounters.size()):
				if typeof(migrated_encounters[index]) == TYPE_DICTIONARY:
					migrated_encounters[index] = _normalize_status_entity(migrated_encounters[index])
			migrated_v3["encounter_enemies"] = migrated_encounters
		migrated_v3["status_schema"] = 1
		migrated_v3["snapshot_version"] = 4
		_normalize_boss_phase_snapshot(migrated_v3)
		return migrated_v3 if _validate_expedition_snapshot(migrated_v3) else {}
	if version == 4:
		var current := snapshot.duplicate(true)
		_normalize_boss_phase_snapshot(current)
		return current if _validate_expedition_snapshot(current) else {}
	return {}

func _normalize_snapshot_entity_statuses(snapshot: Dictionary, key: String) -> void:
	var entity_value: Variant = snapshot.get(key, {})
	if typeof(entity_value) == TYPE_DICTIONARY:
		snapshot[key] = _normalize_status_entity(entity_value)

func _normalize_status_entity(entity_value: Dictionary) -> Dictionary:
	var entity := entity_value.duplicate(true)
	var effects_value: Variant = entity.get("status_effects", [])
	var effects: Array = effects_value.duplicate(true) if typeof(effects_value) == TYPE_ARRAY else []
	var has_distortion := false
	for effect_value in effects:
		if typeof(effect_value) == TYPE_DICTIONARY and str(effect_value.get("id", "")) == "distortion":
			has_distortion = true
			break
	var legacy_value: Variant = entity.get("combat_debuff", {})
	if not has_distortion and typeof(legacy_value) == TYPE_DICTIONARY:
		var legacy: Dictionary = legacy_value
		var duration := clampf(float(legacy.get("time_remaining", 0.0)), 0.0, 600.0)
		var penalty := clampf(float(legacy.get("speed_penalty", 0.0)), 0.0, 0.65)
		if duration > 0.0 and penalty > 0.0:
			effects.append({"id": "distortion", "duration": duration, "tick_accumulator": 0.0, "stacks": 1, "magnitude": penalty, "source_id": "legacy_caster"})
	entity["status_effects"] = effects.slice(maxi(0, effects.size() - 8), effects.size())
	entity["combat_debuff"] = {"speed_penalty": 0.0, "time_remaining": 0.0}
	return entity

func _validate_expedition_snapshot(snapshot: Dictionary) -> bool:
	var snapshot_version := int(snapshot.get("snapshot_version", -1))
	if not [1, 2, 3, 4].has(snapshot_version):
		return false
	# Stage68B telemetry is additive and optional for legacy snapshots. Validate it
	# strictly when present so malformed measurements cannot poison profile history.
	if snapshot.has("telemetry_schema"):
		var telemetry_schema_value: Variant = snapshot.get("telemetry_schema", null)
		if not _is_non_negative_integer(telemetry_schema_value) or int(telemetry_schema_value) not in [0, 1]:
			return false
	if snapshot.has("run_elapsed_seconds"):
		var elapsed_value: Variant = snapshot.get("run_elapsed_seconds", null)
		if not _is_number(elapsed_value) or not is_finite(float(elapsed_value)) or float(elapsed_value) < 0.0 or float(elapsed_value) > 1000000000.0:
			return false
	var baseline_value: Variant = snapshot.get("run_baseline", {})
	if typeof(baseline_value) != TYPE_DICTIONARY:
		return false
	if int(snapshot.get("telemetry_schema", 0)) == 1 and (baseline_value.is_empty() or not snapshot.has("run_elapsed_seconds")):
		return false
	if int(snapshot.get("telemetry_schema", 0)) == 0 and not baseline_value.is_empty():
		return false
	if typeof(baseline_value) == TYPE_DICTIONARY and not baseline_value.is_empty():
		var baseline: Dictionary = baseline_value
		for baseline_key in ["start_hp", "start_max_hp", "start_attack", "start_defense", "start_profile_scrap", "start_profile_crystals"]:
			if not _is_non_negative_integer(baseline.get(baseline_key, null)):
				return false
		if int(baseline.get("start_max_hp", 0)) < int(baseline.get("start_hp", 0)):
			return false
		var baseline_loadout_value: Variant = baseline.get("loadout_ids", {})
		if typeof(baseline_loadout_value) != TYPE_DICTIONARY or baseline_loadout_value.size() > 3:
			return false
		for slot_value in baseline_loadout_value.keys():
			if str(slot_value) not in ["weapon", "armor", "core"] or typeof(baseline_loadout_value[slot_value]) != TYPE_STRING or str(baseline_loadout_value[slot_value]).length() > 100:
				return false
	if snapshot_version >= 2:
		var world_tiles_value: Variant = snapshot.get("world_tiles", null)
		if typeof(world_tiles_value) != TYPE_DICTIONARY or world_tiles_value.size() > 80:
			return false
		if not [1, 2].has(int(snapshot.get("field_schema", 1))):
			return false
		for world_tile_value in world_tiles_value.values():
			if typeof(world_tile_value) != TYPE_DICTIONARY:
				return false
	var route_value: Variant = snapshot.get("route", null)
	var hero_value: Variant = snapshot.get("hero", null)
	var ledger_value: Variant = snapshot.get("run_ledger", null)
	if typeof(route_value) != TYPE_ARRAY or typeof(hero_value) != TYPE_DICTIONARY or typeof(ledger_value) != TYPE_DICTIONARY:
		return false
	var route: Array = route_value
	if route.is_empty() or route.size() > MAX_SNAPSHOT_ROUTE_CELLS:
		return false
	for cell_value in route:
		if typeof(cell_value) != TYPE_DICTIONARY:
			return false
	if snapshot_version >= 2 and int(snapshot.get("field_schema", 1)) >= 2:
		var checked_world_tiles: Dictionary = snapshot.get("world_tiles", {})
		for world_key_value in checked_world_tiles.keys():
			var world_key := str(world_key_value)
			if not TileSystemScript.is_world_cell_valid(world_key):
				return false
			var tile_value: Variant = checked_world_tiles[world_key_value]
			if typeof(tile_value) != TYPE_DICTIONARY:
				return false
			var world_tile: Dictionary = tile_value
			var parts := world_key.split(":")
			if parts.size() != 2 or int(world_tile.get("field_x", -1)) != int(parts[0]) or int(world_tile.get("field_y", -1)) != int(parts[1]):
				return false
			var route_index := int(world_tile.get("route_index", -1))
			if route_index < 0 or route_index >= route.size():
				return false
			if not ContentRegistry.TILE_DEFS.has(str(world_tile.get("id", ""))):
				return false
	if snapshot_version >= 3:
		var contract_value: Variant = snapshot.get("run_contract", {})
		if typeof(contract_value) != TYPE_DICTIONARY:
			return false
		var run_contract: Dictionary = contract_value
		if not run_contract.is_empty():
			var contract_id := str(run_contract.get("id", ""))
			if not ContentRegistry.EXPEDITION_CONTRACTS.has(contract_id) or contract_id == "none":
				return false
			if int(run_contract.get("progress", -1)) < 0 or int(run_contract.get("target", 0)) < 1:
				return false
			if int(run_contract.get("deadline_loops", -1)) < 1:
				return false
			for flag in ["completed", "rewarded", "failed", "cost_paid"]:
				if typeof(run_contract.get(flag, null)) != TYPE_BOOL:
					return false
	if snapshot_version >= 4:
		if int(snapshot.get("status_schema", 0)) != 1:
			return false
		if not _validate_entity_statuses(hero_value):
			return false
		var saved_enemy: Variant = snapshot.get("enemy", {})
		if typeof(saved_enemy) == TYPE_DICTIONARY and (not _validate_entity_statuses(saved_enemy) or not _validate_boss_phase_state(saved_enemy)):
			return false
		for encounter_status_value in snapshot.get("encounter_enemies", []):
			if typeof(encounter_status_value) != TYPE_DICTIONARY or not _validate_entity_statuses(encounter_status_value) or not _validate_boss_phase_state(encounter_status_value):
				return false
	var hero: Dictionary = hero_value
	for key in ["hp", "max_hp", "attack", "defense", "level", "xp", "xp_next"]:
		if not hero.has(key) or not _is_number(hero[key]):
			return false
	if float(hero.get("max_hp", 0)) <= 0.0 or float(hero.get("hp", -1)) < 0.0 or float(hero.get("hp", 0)) > float(hero.get("max_hp", 0)):
		return false
	if float(hero.get("level", 0)) < 1.0 or float(hero.get("xp", -1)) < 0.0 or float(hero.get("xp_next", 0)) <= 0.0:
		return false
	var ledger: Dictionary = ledger_value
	for key in ["scrap", "crystals", "victories", "bosses_defeated", "events_resolved"]:
		if ledger.has(key) and not _is_non_negative_integer(ledger[key]):
			return false
	for key in ["placed_tiles", "equipment", "enemy", "combat_timers", "pending_event"]:
		var expected_type := TYPE_DICTIONARY
		if typeof(snapshot.get(key, {})) != expected_type:
			return false
	for key in ["tile_hand", "bag", "encounter_enemies", "pending_perk_choices", "event_log"]:
		if typeof(snapshot.get(key, [])) != TYPE_ARRAY:
			return false
	if snapshot.get("event_log", []).size() > MAX_SNAPSHOT_LOG_LINES:
		return false
	for enemy_value in snapshot.get("encounter_enemies", []):
		if typeof(enemy_value) != TYPE_DICTIONARY:
			return false
	var pending_event_value: Variant = snapshot.get("pending_event", {})
	if typeof(pending_event_value) == TYPE_DICTIONARY and not pending_event_value.is_empty():
		if typeof(pending_event_value.get("choices", [])) != TYPE_ARRAY or pending_event_value.get("choices", []).is_empty():
			return false
	return true

func _normalize_boss_phase_snapshot(snapshot: Dictionary) -> void:
	var saved_enemy: Variant = snapshot.get("enemy", {})
	if typeof(saved_enemy) == TYPE_DICTIONARY:
		snapshot["enemy"] = _normalize_boss_phase_entity(saved_enemy)
	var encounter_value: Variant = snapshot.get("encounter_enemies", [])
	if typeof(encounter_value) == TYPE_ARRAY:
		var normalized_encounters: Array = encounter_value.duplicate(true)
		for index in range(normalized_encounters.size()):
			if typeof(normalized_encounters[index]) == TYPE_DICTIONARY:
				normalized_encounters[index] = _normalize_boss_phase_entity(normalized_encounters[index])
		snapshot["encounter_enemies"] = normalized_encounters

func _normalize_boss_phase_entity(entity_value: Dictionary) -> Dictionary:
	var entity := entity_value.duplicate(true)
	if not bool(entity.get("is_boss", false)):
		return entity
	var phases_value: Variant = entity.get("phases", [])
	if typeof(phases_value) != TYPE_ARRAY or phases_value.is_empty():
		return entity
	var phases: Array = phases_value
	var phase_index := clampi(int(entity.get("phase_index", 0)), 0, phases.size() - 1)
	var phase: Dictionary = phases[phase_index] if typeof(phases[phase_index]) == TYPE_DICTIONARY else {}
	entity["phase_index"] = phase_index
	entity["phase_name"] = str(entity.get("phase_name", phase.get("name", "Фаза %d" % (phase_index + 1))))
	entity["phase_telegraph"] = str(entity.get("phase_telegraph", phase.get("telegraph", "Босс готовит особую атаку.")))
	entity["special_every"] = clampi(int(entity.get("special_every", phase.get("special_every", 3))), 2, 10)
	entity["attack_count"] = maxi(0, int(entity.get("attack_count", 0)))
	entity["telegraph_pending"] = bool(entity.get("telegraph_pending", false))
	return entity

func _validate_boss_phase_state(entity: Dictionary) -> bool:
	if not bool(entity.get("is_boss", false)):
		return true
	var phases_value: Variant = entity.get("phases", null)
	if typeof(phases_value) != TYPE_ARRAY or phases_value.is_empty() or phases_value.size() > 8:
		return false
	var phases: Array = phases_value
	var phase_index := int(entity.get("phase_index", -1))
	if phase_index < 0 or phase_index >= phases.size() or str(entity.get("phase_name", "")).strip_edges().is_empty() or str(entity.get("phase_telegraph", "")).strip_edges().is_empty():
		return false
	if not _is_non_negative_integer(entity.get("attack_count", null)) or int(entity.get("special_every", 0)) < 2 or int(entity.get("special_every", 0)) > 10 or typeof(entity.get("telegraph_pending", null)) != TYPE_BOOL:
		return false
	var previous_threshold := 1.0001
	for phase_value in phases:
		if typeof(phase_value) != TYPE_DICTIONARY:
			return false
		var phase: Dictionary = phase_value
		for required_field in ["name", "threshold", "attack_multiplier", "defense_bonus", "attack_interval", "special_every", "telegraph"]:
			if not phase.has(required_field):
				return false
		var threshold := float(phase.get("threshold", -1.0))
		var attack_multiplier := float(phase.get("attack_multiplier", 0.0))
		var defense_bonus := int(phase.get("defense_bonus", -1))
		var attack_interval := float(phase.get("attack_interval", 0.0))
		var phase_special_every := int(phase.get("special_every", 0))
		if threshold < 0.0 or threshold > 1.0 or threshold >= previous_threshold or attack_multiplier <= 0.0 or attack_multiplier > 5.0 or defense_bonus < 0 or defense_bonus > 20 or attack_interval < 0.35 or attack_interval > 5.0 or phase_special_every < 2 or phase_special_every > 10:
			return false
		if str(phase.get("name", "")).strip_edges().is_empty() or str(phase.get("telegraph", "")).strip_edges().is_empty():
			return false
		previous_threshold = threshold
		var status_on_enter_value: Variant = phase.get("status_on_enter", {})
		if typeof(status_on_enter_value) != TYPE_DICTIONARY:
			return false
		if not status_on_enter_value.is_empty():
			var phase_effect: Dictionary = status_on_enter_value
			if not ContentRegistry.STATUS_EFFECTS.has(str(phase_effect.get("id", ""))) or str(phase_effect.get("target", "boss")) not in ["boss", "hero"] or float(phase_effect.get("duration", 0.0)) <= 0.0 or float(phase_effect.get("magnitude", -1.0)) < 0.0:
				return false
	return true

func _validate_entity_statuses(entity: Dictionary) -> bool:
	var effects_value: Variant = entity.get("status_effects", [])
	if typeof(effects_value) != TYPE_ARRAY or effects_value.size() > 8:
		return false
	var seen: Dictionary = {}
	for effect_value in effects_value:
		if typeof(effect_value) != TYPE_DICTIONARY:
			return false
		var effect: Dictionary = effect_value
		var effect_id := str(effect.get("id", ""))
		if not ContentRegistry.STATUS_EFFECTS.has(effect_id) or seen.has(effect_id):
			return false
		seen[effect_id] = true
		var definition: Dictionary = ContentRegistry.STATUS_EFFECTS[effect_id]
		var duration := float(effect.get("duration", -1.0))
		var accumulator := float(effect.get("tick_accumulator", -1.0))
		var magnitude := float(effect.get("magnitude", -1.0))
		var stacks := int(effect.get("stacks", 0))
		var interval := maxf(0.1, float(definition.get("tick_interval", 0.0)))
		if not is_finite(duration) or duration < 0.0 or duration > 600.0:
			return false
		if not is_finite(accumulator) or accumulator < 0.0 or accumulator > interval + 0.001:
			return false
		if not is_finite(magnitude) or magnitude < 0.0 or magnitude > 1000.0:
			return false
		if stacks < 1 or stacks > int(definition.get("max_stacks", 1)):
			return false
	return true

func _is_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))

func _is_non_negative_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0

func _write_atomic_text(target_path: String, temporary_path: String, text_value: String) -> bool:
	var target_absolute := ProjectSettings.globalize_path(target_path)
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var rollback_path := target_path + ".previous.tmp"
	var rollback_absolute := ProjectSettings.globalize_path(rollback_path)

	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_absolute)
	var temporary_file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if temporary_file == null:
		return false
	temporary_file.store_string(text_value)
	temporary_file.flush()
	temporary_file.close()
	if not FileAccess.file_exists(temporary_path) or FileAccess.get_file_as_string(temporary_path) != text_value:
		if FileAccess.file_exists(temporary_path):
			DirAccess.remove_absolute(temporary_absolute)
		return false

	var had_target := FileAccess.file_exists(target_path)
	if had_target:
		if FileAccess.file_exists(rollback_path):
			DirAccess.remove_absolute(rollback_absolute)
		if DirAccess.rename_absolute(target_absolute, rollback_absolute) != OK:
			DirAccess.remove_absolute(temporary_absolute)
			return false

	if DirAccess.rename_absolute(temporary_absolute, target_absolute) != OK:
		if had_target and FileAccess.file_exists(rollback_path):
			DirAccess.rename_absolute(rollback_absolute, target_absolute)
		if FileAccess.file_exists(temporary_path):
			DirAccess.remove_absolute(temporary_absolute)
		return false

	if had_target and FileAccess.file_exists(rollback_path):
		DirAccess.remove_absolute(rollback_absolute)
	return true

func _load_backup() -> Dictionary:
	if not FileAccess.file_exists(BACKUP_PATH):
		return {}
	var normalized := _decode_save(FileAccess.get_file_as_string(BACKUP_PATH))
	return normalized.get("data", {}) if not normalized.is_empty() else {}

func export_save_file(destination_path: String, payload: Dictionary) -> bool:
	if destination_path.strip_edges().is_empty() or not _validate_save_data(payload):
		return false
	var encoded := _encode_save(payload)
	var temporary_path := destination_path + ".abyssloop.tmp"
	var temporary_file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if temporary_file == null:
		return false
	temporary_file.store_string(encoded)
	temporary_file.flush()
	temporary_file.close()
	if not FileAccess.file_exists(temporary_path) or FileAccess.get_file_as_string(temporary_path) != encoded:
		if FileAccess.file_exists(temporary_path):
			DirAccess.remove_absolute(temporary_path)
		return false
	# Export is an independent user-chosen copy; never rename or delete the internal save.
	if FileAccess.file_exists(destination_path):
		var old_path := destination_path + ".previous.tmp"
		if FileAccess.file_exists(old_path):
			DirAccess.remove_absolute(old_path)
		if DirAccess.rename_absolute(destination_path, old_path) != OK:
			DirAccess.remove_absolute(temporary_path)
			return false
		if DirAccess.rename_absolute(temporary_path, destination_path) != OK:
			DirAccess.rename_absolute(old_path, destination_path)
			if FileAccess.file_exists(temporary_path):
				DirAccess.remove_absolute(temporary_path)
			return false
		if FileAccess.file_exists(old_path):
			DirAccess.remove_absolute(old_path)
	else:
		if DirAccess.rename_absolute(temporary_path, destination_path) != OK:
			if FileAccess.file_exists(temporary_path):
				DirAccess.remove_absolute(temporary_path)
			return false
	return FileAccess.file_exists(destination_path) and FileAccess.get_file_as_string(destination_path) == encoded

func import_save_file(source_path: String) -> bool:
	if source_path.strip_edges().is_empty() or not FileAccess.file_exists(source_path):
		return false
	var normalized := _decode_save(FileAccess.get_file_as_string(source_path))
	if normalized.is_empty():
		return false
	var data_value: Variant = normalized.get("data", {})
	if typeof(data_value) != TYPE_DICTIONARY or not _validate_save_data(data_value):
		return false
	# save_game validates and atomically commits the imported payload while preserving the previous profile backup.
	return save_game(data_value)

func reset_save() -> void:
	for path in [SAVE_PATH, SAVE_TEMP_PATH, BACKUP_PATH, BACKUP_TEMP_PATH, CORRUPT_PATH, CORRUPT_TEMP_PATH, SAVE_PATH + ".previous.tmp", BACKUP_PATH + ".previous.tmp", CORRUPT_PATH + ".previous.tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	last_load_status = "reset"

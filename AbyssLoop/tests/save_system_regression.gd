extends Node

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

func _ready() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var originals: Dictionary = {}
	for path in TARGET_PATHS:
		originals[path] = {"exists": FileAccess.file_exists(path), "text": FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""}
	var save_system = get_tree().root.get_node_or_null("SaveSystem")
	if save_system == null:
		push_error("SaveSystem autoload was not created. Run this test with the project loaded in Godot.")
		_quit_with_restore(originals, 1)
		return

	var persisted_affix_weapon := {
		"id": "save_affix_weapon", "slot": "weapon", "name": "Оружие · Точная грань · Резец глубин · Редкий",
		"rarity": "Редкий", "rank": 2, "upgrade_level": 0, "archetype": "wound",
		"archetype_name": "Резец глубин", "archetype_description": "Кровотечение", "set_id": "vanguard",
		"set_name": "Авангард", "attack": 4, "defense": 0, "hp": 0, "speed": 0.0, "crit": 0.015,
		"kill_heal": 0, "tile_scrap": 0, "event_heal": 0, "reward_bonus": 0.0,
		"tile_spawn_bonus": 0.0, "bleed_chance": 0.2, "bleed_damage": 2, "barrier_on_encounter": 0,
		"power": 24.0, "affix_ids": ["keen_edge"], "affix_names": ["Точная грань"],
		"affix_description": "+1 атака и +1,5% к критическому шансу."
	}
	assert(save_system._validate_item(persisted_affix_weapon, "weapon"), "valid rare affixed weapon should pass save validation")
	var wrong_slot_affix := persisted_affix_weapon.duplicate(true)
	wrong_slot_affix["affix_ids"] = ["reinforced_plate"]
	wrong_slot_affix["affix_names"] = ["Усиленная пластина"]
	assert(not save_system._validate_item(wrong_slot_affix, "weapon"), "save validation must reject an armor affix attached to a weapon")
	var duplicate_position_affixes := persisted_affix_weapon.duplicate(true)
	duplicate_position_affixes["rarity"] = "Эпический"
	duplicate_position_affixes["affix_ids"] = ["keen_edge", "barbed_edge"]
	duplicate_position_affixes["affix_names"] = ["Точная грань", "Зубчатая кромка"]
	duplicate_position_affixes["affix_description"] = "Повторяющиеся префиксы"
	assert(not save_system._validate_item(duplicate_position_affixes, "weapon"), "epic items must not persist two prefixes instead of prefix/suffix")
	var legacy_item := {"id": "legacy_plain_weapon", "slot": "weapon", "rarity": "Редкий", "rank": 2, "upgrade_level": 0, "attack": 3, "power": 12.0}
	assert(save_system._validate_item(legacy_item, "weapon"), "legacy gear without affix metadata must remain loadable")
	var baseline := {
		"scrap": 40, "crystals": 3,
		"buildings": {"forge": 0, "infirmary": 0, "salvage": 0},
		"loadout": {"weapon": {}, "armor": {}, "core": {}},
		"armory": [persisted_affix_weapon.duplicate(true)], "unlocked_nodes": [], "saved_expedition": {},
		"settings": {"master_volume": 0.8, "music_volume": 0.7, "effects_volume": 0.85},
		"tutorial_page": 0, "tutorial_completed": false, "last_summary": {}
	}
	assert(save_system.save_game(baseline), "first valid save should succeed")
	baseline["scrap"] = 41
	assert(save_system.save_game(baseline), "second valid save should succeed")
	assert(FileAccess.file_exists("user://loop_roguelite_save.backup.json"), "second save should preserve a backup")
	var primary: Dictionary = save_system.load_game()
	assert(int(primary.get("scrap", -1)) == 41, "primary should contain latest progress")
	var loaded_armory_value: Variant = primary.get("armory", [])
	assert(typeof(loaded_armory_value) == TYPE_ARRAY and not loaded_armory_value.is_empty(), "affixed item should survive a real save/load roundtrip")
	var loaded_affix_item: Dictionary = loaded_armory_value[0]
	assert(str(loaded_affix_item.get("id", "")) == "save_affix_weapon" and loaded_affix_item.get("affix_ids", []) == ["keen_edge"] and loaded_affix_item.get("affix_names", []) == ["Точная грань"], "affix IDs and names must survive checksum-protected save/load")
	assert(str(loaded_affix_item.get("affix_description", "")).contains("критическому шансу"), "affix description must survive save/load")

	# New envelope integrity is deterministic regardless of dictionary insertion order.
	var saved_envelope: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://loop_roguelite_save.json"))
	assert(typeof(saved_envelope) == TYPE_DICTIONARY, "saved envelope should be valid JSON")
	assert(typeof(saved_envelope.get("integrity", null)) == TYPE_DICTIONARY, "new saves should include integrity metadata")
	assert(int(saved_envelope.get("version", -1)) == 3, "payload schema version should remain unchanged")
	assert(int(saved_envelope.get("envelope_version", -1)) == 2, "new saves should use integrity-aware envelope version 2")
	assert(str(saved_envelope.get("integrity", {}).get("algorithm", "")) == "sha256", "save envelope should declare SHA-256")
	var downgraded_envelope := {"version": 3, "envelope_version": 2, "data": baseline.duplicate(true)}
	assert(save_system._decode_save(JSON.stringify(downgraded_envelope)).is_empty(), "envelope v2 without checksum must be rejected")
	assert(str(saved_envelope.get("integrity", {}).get("checksum", "")).length() == 64, "save checksum should be 64 hex characters")
	assert(save_system._payload_checksum({"a": 1, "b": 2}) == save_system._payload_checksum({"b": 2, "a": 1}), "canonical checksum must ignore dictionary key insertion order")
	var typed_roundtrip_payload := {"nested": {"decimal": 0.7, "whole": 1.0}, "items": [{"value": 0.85}]}
	var parsed_roundtrip_payload: Variant = JSON.parse_string(JSON.stringify(typed_roundtrip_payload))
	assert(typeof(parsed_roundtrip_payload) == TYPE_DICTIONARY, "JSON roundtrip fixture must parse as a dictionary")
	assert(save_system._payload_checksum(typed_roundtrip_payload) == save_system._payload_checksum(parsed_roundtrip_payload), "payload checksum must hash the same persisted JSON representation before and after load")
	assert(save_system._canonical_json({"scrap": 41, "settings": {"ui_scale": 1.0}}) == save_system._canonical_json({"scrap": 41.0, "settings": {"ui_scale": 1.0}}), "canonical JSON must normalize whole numbers to tolerate Web/WASM integer-to-float parsing")
	assert(save_system._payload_checksum({"scrap": 41, "settings": {"ui_scale": 1.0}}) == save_system._payload_checksum({"scrap": 41.0, "settings": {"ui_scale": 1.0}}), "save checksum must remain stable when a JSON integer is parsed as a float")
	assert(save_system._canonical_json({"settings": {"music": 0.7, "effects": 0.85}}) == save_system._canonical_json({"settings": {"music": 0.699999988079071, "effects": 0.8500000238418579}}), "canonical JSON must stabilize fractional numbers across Web/WASM precision conversion")
	assert(save_system._payload_checksum({"settings": {"music": 0.7, "effects": 0.85}}) == save_system._payload_checksum({"settings": {"music": 0.699999988079071, "effects": 0.8500000238418579}}), "save checksum must remain stable across Web/WASM single-precision fraction conversion")
	assert(save_system._canonical_json({"fraction": 1.00000001}) == save_system._canonical_json({"fraction": 1.0}), "canonical JSON must normalize double values that collapse to the same Web float32 value")
	var encoded_roundtrip: String = save_system._encode_save(baseline)
	assert(not encoded_roundtrip.is_empty() and not save_system._decode_save(encoded_roundtrip).is_empty(), "integrity envelope should survive an ordinary encode/decode roundtrip")
	var web_like_envelope: Variant = JSON.parse_string(encoded_roundtrip)
	assert(typeof(web_like_envelope) == TYPE_DICTIONARY, "roundtrip fixture should be an envelope dictionary")
	var web_like_text := JSON.stringify(_make_integral_numbers_float(web_like_envelope), "\t")
	var web_like_decoded: Dictionary = save_system._decode_save(web_like_text)
	assert(not web_like_decoded.is_empty(), "valid checksum must survive Web/WASM integer-to-float JSON parsing")
	assert(typeof(web_like_decoded.get("data", {}).get("scrap", null)) == TYPE_INT and int(web_like_decoded["data"]["scrap"]) == 41, "decoded integer resource values must be normalized before schema validation")

	# Change data without updating its checksum. It must be rejected and fall back to the previous valid backup.
	var tampered_envelope: Dictionary = saved_envelope.duplicate(true)
	tampered_envelope["data"]["scrap"] = 999
	var tampered_file := FileAccess.open("user://loop_roguelite_save.json", FileAccess.WRITE)
	assert(tampered_file != null, "tampered test save should open")
	tampered_file.store_string(JSON.stringify(tampered_envelope, "\t"))
	tampered_file.flush()
	tampered_file.close()
	var integrity_recovered: Dictionary = save_system.load_game()
	assert(str(save_system.last_load_status) == "recovered_backup", "checksum mismatch should trigger validated backup recovery")
	assert(int(integrity_recovered.get("scrap", -1)) == 40, "tampered primary progress must not be accepted")
	assert(not save_system._decode_save(FileAccess.get_file_as_string("user://loop_roguelite_save.json")).is_empty(), "successful backup recovery should rewrite a valid primary envelope")

	var corrupt_file := FileAccess.open("user://loop_roguelite_save.json", FileAccess.WRITE)
	corrupt_file.store_string("{ definitely not valid json")
	corrupt_file.close()
	var recovered: Dictionary = save_system.load_game()
	assert(str(save_system.last_load_status) == "recovered_backup", "corrupt primary should select backup")
	assert(int(recovered.get("scrap", -1)) == 40, "backup should contain previous valid progress")

	var v1 := {"version": 1, "data": {"scrap": 8, "crystals": 2}}
	var v1_file := FileAccess.open("user://loop_roguelite_save.json", FileAccess.WRITE)
	v1_file.store_string(JSON.stringify(v1))
	v1_file.close()
	var migrated: Dictionary = save_system.load_game()
	assert(int(migrated.get("scrap", -1)) == 8, "version 1 resources must migrate")
	assert(typeof(migrated.get("saved_expedition", null)) == TYPE_DICTIONARY, "version 1 must receive an empty checkpoint")
	assert(int(migrated.get("tutorial_page", -1)) == 0, "pre-tutorial saves must migrate to tutorial page zero")

	# A missing primary must restore the backup and write the restored primary.
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://loop_roguelite_save.json"))
	var recovered_missing_primary: Dictionary = save_system.load_game()
	assert(str(save_system.last_load_status) == "recovered_backup_missing_primary", "missing primary should surface an explicit backup recovery status")
	assert(int(recovered_missing_primary.get("scrap", -1)) == 40, "missing primary should restore previous valid backup progress")
	assert(FileAccess.file_exists("user://loop_roguelite_save.json"), "backup recovery should recreate the primary save atomically")

	# Legacy profile selection reads only known project-profile prefixes and never
	# edits the source. The actual import is disabled in the release QA sandbox.
	var profiles_root := ProjectSettings.globalize_path("user://legacy_profile_migration_test")
	_remove_test_tree(profiles_root)
	DirAccess.make_dir_recursive_absolute(profiles_root)
	var older_profile := profiles_root.path_join("Abyss Loop — Prototype 26 · Эхо глубин")
	var newer_profile := profiles_root.path_join("Abyss Loop — Prototype 27 · Испытания глубин")
	DirAccess.make_dir_recursive_absolute(older_profile)
	DirAccess.make_dir_recursive_absolute(newer_profile)
	_write_profile_save(older_profile.path_join("loop_roguelite_save.json"), 26)
	OS.delay_msec(2200)
	_write_profile_save(newer_profile.path_join("loop_roguelite_save.json"), 27)
	var legacy_candidate: Dictionary = save_system._find_latest_legacy_profile_payload(profiles_root, "Abyss Loop")
	assert(str(legacy_candidate.get("source_profile", "")) == "Abyss Loop — Prototype 27 · Испытания глубин", "migration should select the newest valid earlier profile")
	assert(int(legacy_candidate.get("data", {}).get("scrap", -1)) == 27, "migration should preserve the selected profile's resources")
	assert(FileAccess.file_exists(older_profile.path_join("loop_roguelite_save.json")) and FileAccess.file_exists(newer_profile.path_join("loop_roguelite_save.json")), "profile discovery must never delete source files")
	_remove_test_tree(profiles_root)

	var interrupted_candidate := baseline.duplicate(true)
	interrupted_candidate["scrap"] = 27
	var interrupted_file := FileAccess.open("user://loop_roguelite_save.tmp.json", FileAccess.WRITE)
	interrupted_file.store_string(JSON.stringify({"version": 3, "data": interrupted_candidate}))
	interrupted_file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://loop_roguelite_save.json"))
	var recovered_temporary: Dictionary = save_system.load_game()
	assert(int(recovered_temporary.get("scrap", -1)) == 27, "valid temporary transaction should be recovered after interrupted replacement")

	var stable_text := FileAccess.get_file_as_string("user://loop_roguelite_save.json")
	var invalid := {"scrap": -1, "crystals": 2, "buildings": {}, "loadout": {}, "armory": [], "unlocked_nodes": [], "saved_expedition": {}, "settings": {}, "tutorial_page": 0, "tutorial_completed": false, "last_summary": {}}
	assert(not save_system.save_game(invalid), "negative permanent resources must be rejected")
	assert(FileAccess.get_file_as_string("user://loop_roguelite_save.json") == stable_text, "rejected save must not overwrite the last valid file")

	# Legacy saves without the purchase-cost ledger remain valid, and future/unknown
	# research IDs are retained rather than silently pruned by save validation.
	var legacy_research_payload := baseline.duplicate(true)
	legacy_research_payload.erase("research_investments")
	legacy_research_payload["unlocked_nodes"] = ["route_archive", "future_missing_research"]
	assert(save_system.save_game(legacy_research_payload), "legacy research save without a purchase ledger should remain valid")
	var loaded_legacy_research: Dictionary = save_system.load_game()
	assert(loaded_legacy_research.get("unlocked_nodes", []).has("future_missing_research"), "unknown stable research IDs must survive roundtrip")
	assert(not loaded_legacy_research.has("research_investments"), "legacy save schema should not require a newly introduced research ledger")

	var ledger_payload := legacy_research_payload.duplicate(true)
	ledger_payload["research_investments"] = {
		"route_archive": {"scrap": 30, "crystals": 2},
		"future_missing_research": {"scrap": 15, "crystals": 1}
	}
	assert(save_system.save_game(ledger_payload), "valid actual research purchase history should save")
	var loaded_ledger: Dictionary = save_system.load_game()
	assert(int(loaded_ledger.get("research_investments", {}).get("route_archive", {}).get("scrap", -1)) == 30, "actual purchase costs must survive save roundtrip")
	assert(loaded_ledger.get("research_investments", {}).has("future_missing_research"), "unknown IDs should keep their stored investment history")
	var malformed_ledger := ledger_payload.duplicate(true)
	malformed_ledger["research_investments"]["route_archive"]["scrap"] = -1
	var ledger_stable_text := FileAccess.get_file_as_string("user://loop_roguelite_save.json")
	assert(not save_system.save_game(malformed_ledger), "negative research investment cost must be rejected")
	assert(FileAccess.get_file_as_string("user://loop_roguelite_save.json") == ledger_stable_text, "invalid research ledger must not replace last valid save")

	print("SAVE SYSTEM REGRESSION TESTS PASSED")
	_quit_with_restore(originals, 0)

func _make_integral_numbers_float(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary_copy: Dictionary = {}
		for key in value.keys():
			dictionary_copy[key] = _make_integral_numbers_float(value[key])
		return dictionary_copy
	if typeof(value) == TYPE_ARRAY:
		var array_copy: Array = []
		for entry in value:
			array_copy.append(_make_integral_numbers_float(entry))
		return array_copy
	if typeof(value) == TYPE_INT:
		return float(value)
	return value

func _write_profile_save(path: String, scrap_value: int) -> void:
	var payload := {
		"scrap": scrap_value,
		"crystals": 2,
		"buildings": {},
		"loadout": {},
		"armory": [],
		"unlocked_nodes": [],
		"saved_expedition": {},
		"settings": {},
		"tutorial_page": 0,
		"tutorial_completed": false,
		"last_summary": {}
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "legacy profile test save should open")
	file.store_string(JSON.stringify({"version": 3, "data": payload}))
	file.flush()
	file.close()

func _remove_test_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory != null:
		directory.list_dir_begin()
		while true:
			var entry: String = directory.get_next()
			if entry.is_empty():
				break
			var child_path := path.path_join(entry)
			if directory.current_is_dir():
				_remove_test_tree(child_path)
			else:
				DirAccess.remove_absolute(child_path)
		directory.list_dir_end()
	DirAccess.remove_absolute(path)

func _quit_with_restore(originals: Dictionary, exit_code: int) -> void:
	for path in TARGET_PATHS:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		var previous: Dictionary = originals.get(path, {})
		if bool(previous.get("exists", false)):
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null:
				file.store_string(str(previous.get("text", "")))
				file.close()
	get_tree().quit(exit_code)

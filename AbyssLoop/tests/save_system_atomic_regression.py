"""Source-level regression guard for the save format; run the .gd runtime test in Godot too."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")

checks = {
    "current save format is versioned": "const SAVE_VERSION := 3" in save,
    "stable project data profile name is used": 'config/name="Abyss Loop"' in (ROOT / "project.godot").read_text(encoding="utf-8"),
    "profile migration only runs when the current profile is empty": "func _try_migrate_legacy_profile()" in save and "not FileAccess.file_exists(SAVE_PATH)" in save,
    "legacy import can be disabled for isolated QA": 'ABYSS_LOOP_DISABLE_LEGACY_PROFILE_IMPORT' in save,
    "only known previous project profiles are considered": "LEGACY_PROFILE_PREFIXES" in save and "_is_legacy_profile_name" in save,
    "missing primary restores backup": "recovered_backup_missing_primary" in save and "var backup_data := _load_backup()" in save,
    "temporary save file is used": 'const SAVE_TEMP_PATH := "user://loop_roguelite_save.tmp.json"' in save,
    "backup replacement is atomic": "_write_atomic_text(BACKUP_PATH, BACKUP_TEMP_PATH, previous_text)" in save,
    "primary replacement is atomic": "_write_atomic_text(SAVE_PATH, SAVE_TEMP_PATH, encoded)" in save,
    "file content is verified before replacement": "FileAccess.get_file_as_string(temporary_path) != text_value" in save,
    "rollback restores old file when rename fails": "DirAccess.rename_absolute(rollback_absolute, target_absolute)" in save,
    "interrupted replacements are recovered": "func _recover_interrupted_replacements()" in save and "_recover_one_replacement(SAVE_PATH, SAVE_TEMP_PATH)" in save,
    "damaged primary is quarantined": "CORRUPT_PATH" in save and "Повреждённый файл" in save,
    "backup fallback is explicit": 'last_load_status = "recovered_backup"' in save,
    "missing primary recovery is explicit": 'last_load_status = "recovered_backup_missing_primary"' in save,
    "legacy profile import is atomic": "_try_migrate_legacy_profile" in save and "_write_atomic_text(SAVE_PATH, SAVE_TEMP_PATH" in save,
    "invalid resource counts are rejected": "_is_non_negative_integer" in save,
    "snapshot shape is validated": "func _validate_expedition_snapshot" in save,
    "tutorial state is part of save data": '"tutorial_page": tutorial_page' in state and '"tutorial_completed": tutorial_completed' in state,
    "migration v1 to v2 exists": 'if version < 2:' in save and 'data["saved_expedition"] = {}' in save,
    "migration v2 to v3 exists": 'if version < 3:' in save and 'data["tutorial_completed"] = false' in save,
    "stable version title does not fragment user profile": 'config/name="Abyss Loop"' in (ROOT / "project.godot").read_text(encoding="utf-8"),
}
failed = [name for name, ok in checks.items() if not ok]
assert not failed, "Save regression checks failed: " + ", ".join(failed)
print("SAVE SYSTEM ATOMIC REGRESSION CHECK PASSED:")
for name in checks:
    print("- " + name)
print("Note: source-level check only; also run tests/save_system_regression.gd in Godot.")

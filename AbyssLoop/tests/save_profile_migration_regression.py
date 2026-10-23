"""Source-level guards for stable save profile continuity; runtime counterpart lives in save_system_regression.gd."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
project = (ROOT / "project.godot").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
runtime_test = (ROOT / "tests/save_system_regression.gd").read_text(encoding="utf-8")

checks = {
    "application config name is stable across prototype builds": 'config/name="Abyss Loop"' in project,
    "build version is separate from application profile name": 'config/version="0.61.0"' in project,
    "legacy profile selection prefers newest valid save": "_find_latest_legacy_profile_payload" in save and "FileAccess.get_modified_time(source_path)" in save,
    "legacy primary is preferred before its own backup": save.index('if FileAccess.file_exists(primary_path)') < save.index('if decoded.is_empty() and FileAccess.file_exists(backup_path)'),
    "legacy source profile uses a narrow prefix allowlist": '"abyss loop"' in save and '"looproguelite"' in save and "_is_legacy_profile_name" in save,
    "source profile is never modified by migration": "source_path" in save and "_write_atomic_text(SAVE_PATH, SAVE_TEMP_PATH" in save,
    "QA can disable profile import": 'ABYSS_LOOP_DISABLE_LEGACY_PROFILE_IMPORT' in save,
    "missing-primary recovery is surfaced in UI": '"recovered_backup_missing_primary"' in state and "резервной копии" in state,
    "migration and missing-primary behavior have runtime regression coverage": "_find_latest_legacy_profile_payload" in runtime_test and "recovered_backup_missing_primary" in runtime_test,
}
failed = [name for name, ok in checks.items() if not ok]
assert not failed, "Save-profile migration regression failed: " + ", ".join(failed)
print("SAVE PROFILE MIGRATION REGRESSION PASSED: " + str(len(checks)) + " checks")
for name in checks:
    print("- " + name)
print("GDScript execution is still required for the end-to-end profile restore test.")

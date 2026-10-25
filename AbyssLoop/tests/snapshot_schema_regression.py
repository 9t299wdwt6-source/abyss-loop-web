"""Source-level guards for explicit expedition snapshot schema migration and save transfer."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
checks = {
    "snapshot v1/v2/v3 migrate to current status-aware v4 snapshot": "func migrate_expedition_snapshot(snapshot: Dictionary) -> Dictionary:" in save and 'migrated_v1["snapshot_version"] = 2' in save and 'migrated_v3["snapshot_version"] = 4' in save,
    "v4 adds status state while preserving contract and world field schema": '"world_tiles": world_tiles.duplicate(true)' in manager and '"field_schema": 3' in manager and '"run_contract": run_contract.duplicate(true)' in manager,
    "v1, v2, v3, and v4 snapshots can be restored": 'not [1, 2, 3, 4].has(int(snapshot.get("snapshot_version", 1)))' in manager,
    "snapshot validator checks status durations, stacks, known IDs and duplicates": '_validate_entity_statuses(hero_value)' in save and 'seen.has(effect_id)' in save and 'STATUS_EFFECTS.has(effect_id)' in save,
    "snapshot validator bounds world tile count": 'world_tiles_value.size() > 232' in save,
    "Stage68B snapshot telemetry fields are optional for legacy snapshots and bounded when present": all(token in save for token in ['snapshot.has("telemetry_schema")', 'not _is_non_negative_integer(telemetry_schema_value)', 'float(elapsed_value) > 1000000000.0', 'int(snapshot.get("telemetry_schema", 0)) == 1 and (baseline_value.is_empty()', 'int(snapshot.get("telemetry_schema", 0)) == 0 and not baseline_value.is_empty()']),
    "legacy snapshots without run baseline are captured as schema zero instead of guessed": '"telemetry_schema": 1 if not run_baseline.is_empty() else 0' in manager and '"measurement_quality": "complete" if not run_baseline.is_empty() else "legacy_partial"' in manager,
    "field schema v3 validates coordinates and rejects modern cells occupied by the active road": 'TileSystemScript.is_world_cell_valid(world_key)' in save and 'world_tile.get("route_index", -1)' in save and 'ContentRegistry.TILE_DEFS.has(str(world_tile.get("id", "")))' in save and 'modern_road_coordinates.has(expected_coord)' in save and 'ContentRegistry.RUN_MODIFIERS.get(str(snapshot.get("run_modifier_id", "standard")), {})' in save,
    "prototype 32 empty field schema is safely migrated": 'migrated_v2["world_tiles"] = {}' in save or 'migrated_v3["world_tiles"] = {}' in save and 'current["field_schema"] = 2' in save,
    "legacy current profile snapshots migrate old combat debuffs to status effects": 'SaveSystem.migrate_expedition_snapshot(saved_run_value)' in state and 'migrated_v2["run_contract"] = {}' in save or 'migrated_v3["run_contract"] = {}' in save and '_normalize_status_entity' in save and 'status_schema' in save,
    "save export validates and writes an independent file": "func export_save_file(destination_path: String, payload: Dictionary) -> bool:" in save and "_validate_save_data(payload)" in save,
    "save import rejects invalid payloads before atomic commit": "func import_save_file(source_path: String) -> bool:" in save and "return save_game(data_value)" in save,
    "UI offers export only from the base settings": 'Callable(self, "_open_save_export_dialog")' in ui and 'if screen_mode == "base":' in ui,
    "import warns that profile replacement is destructive and requires restart": "Перед заменой создаётся резервная копия" in ui and "Перезапустите игру" in ui,
}
failed = [k for k,v in checks.items() if not v]
assert not failed, "Snapshot schema regression failed: " + ", ".join(failed)
print("SNAPSHOT SCHEMA REGRESSION PASSED: %d checks" % len(checks))
for name in checks: print("- " + name)
print("Source-level guards only; file-dialog and GDScript runtime paths need Godot testing.")

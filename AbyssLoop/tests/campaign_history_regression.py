"""Static guards for bounded, local, idempotent expedition history."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
game_state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
save_system = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
project = (ROOT / "project.godot").read_text(encoding="utf-8")
checks = {
    "history is explicitly bounded to 50 summaries": "const MAX_EXPEDITION_HISTORY := 50" in game_state and 'expedition_history.size() > MAX_EXPEDITION_HISTORY' in game_state,
    "legacy saves default to empty history without schema break": 'saved.get("expedition_history", [])' in game_state and 'const SAVE_VERSION := 3' in save_system,
    "records are normalized and do not store full snapshots": 'func _normalize_history_entry(source: Dictionary)' in game_state and '"run_id": str(source.get("run_id", ""))' in game_state and '"event_decisions": decisions' in game_state,
    "duplicate run IDs replace rather than duplicate": 'func record_expedition_history(summary: Dictionary) -> bool:' in game_state and 'if not found:' in game_state and 'expedition_history[index] = entry' in game_state,
    "oldest rows are trimmed after reaching capacity": 'expedition_history = expedition_history.slice(expedition_history.size() - MAX_EXPEDITION_HISTORY)' in game_state,
    "history transaction rolls back in memory when save fails": 'if not save_now():\n\t\texpedition_history = previous\n\t\treturn false' in game_state,
    "history is included in permanent save and new-game reset": '"expedition_history": expedition_history.duplicate(true)' in game_state and 'expedition_history.clear()' in game_state,
    "save validation rejects oversized and duplicate records": 'history_value.size() > 50' in save_system and 'history_ids.has(run_id)' in save_system,
    "summary carries replay identity, seed, version, timestamp and run metrics": all(term in manager for term in ['"run_id": "%d-%d-%s"', '"timestamp_unix": int(Time.get_unix_time_from_system())', '"game_version": str(ProjectSettings.get_setting', '"challenge_score": challenge_score', '"tiles": recent_tile_names']),
    "Stage68B history keeps local measurement schema, elapsed time, baseline and end state": all(term in game_state for term in ['"telemetry_schema": clampi(int(source.get("telemetry_schema", 0)), 0, 1)', '"run_elapsed_seconds": maxi(0, int(source.get', '"start_profile_scrap"', '"start_loadout_ids": start_loadout_ids']) and all(term in manager for term in ['"end_hp": maxi(0, int(hero.get', '"road_placements": placed_tiles.size()', '"world_placements": world_tiles.size()', '"run_elapsed_seconds": maxi(0, int(round(run_elapsed_seconds)))']),
    "run settlement commits history and the rich summary in one atomic GameState transaction": 'GameState.settle_expedition(' in manager and 'summary_metadata, record_key, challenge_score' in manager and 'summary["history_saved"] = history_saved' in game_state and 'GameState.record_expedition_history(summary)' not in manager,
    "settlement transaction includes difficulty record, history and loadout rollback": all(term in game_state for term in ['var old_difficulty_records: Dictionary', 'var old_expedition_history: Array', 'var old_loadout: Dictionary', 'difficulty_records = old_difficulty_records', 'expedition_history = old_expedition_history', 'loadout = old_loadout']),
    "journal UI exposes all, returns, and defeats filters": all(term in ui for term in ['Callable(self, "_open_expedition_history").bind("all")', 'bind("returns")', 'bind("defeats")', 'GameState.get_expedition_history(filter_id']),
    "journal UI displays score, seed, difficulty, outcomes and resources": all(term in ui for term in ['ЖУРНАЛ КАМПАНИИ', 'seed %d', 'challenge_score', 'kept_scrap', 'lost_scrap']),
    "journal entries show expedition mode and endgame completion": all(term in ui for term in ['expedition_mode_name', 'endgame_completed', 'ФИНАЛ ЭНДГЕЙМА']),
    "project version advanced to 0.61.0": 'config/version="0.61.0"' in project,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"[{ 'PASS' if ok else 'FAIL' }] {name}")
if failed:
    raise SystemExit(f"CAMPAIGN HISTORY REGRESSION FAILED: {len(failed)} checks: {failed}")
print(f"CAMPAIGN HISTORY REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Static source guards only; verify serialization, duplicate completion, and UI in Godot 4.7.2.")

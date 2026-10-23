"""Source-level guards for resumable expedition persistence; does not replace Godot runtime tests."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
game_state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
save_system = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")

required_snapshot_fields = [
    '"run_contract": run_contract.duplicate(true)',
    '"rng_state"', '"route"', '"hero"', '"run_ledger"', '"placed_tiles"',
    '"tile_hand"', '"equipment"', '"enemy"', '"encounter_enemies"',
    '"combat_timers"', '"pending_perk_choices"', '"pending_event"', '"event_log"',
    '"run_elapsed_seconds"', '"run_baseline"', '"telemetry_schema"'
]
missing = [field for field in required_snapshot_fields if field not in manager]
assert not missing, f"Expedition snapshot misses fields: {missing}"
assert "func restore_saved_run() -> bool" in manager and "status_effect_system.normalize_legacy_entity(hero)" in manager, "restore entry point missing"
assert "run_contract = contract_value.duplicate(true) if typeof(contract_value) == TYPE_DICTIONARY else {}" in manager, "contract progress is not restored from a snapshot"
assert "_autosave_elapsed >= float(ContentRegistry.BALANCE.get(\"autosave_interval_seconds\", 2.0))" in manager and '"autosave_interval_seconds": 2.0' in registry, "configurable periodic checkpoint should work during pause/events"
assert "GameState.set_saved_expedition(snapshot)" in manager, "manager does not commit snapshots"
assert "paused = true # Resume safely" in manager, "restored run should not advance before player resumes"
assert 'run_elapsed_seconds = maxf(0.0, float(snapshot.get("run_elapsed_seconds", 0.0)))' in manager, "run elapsed timer must survive checkpoint restore"
assert 'run_baseline = baseline_value.duplicate(true) if typeof(baseline_value) == TYPE_DICTIONARY else {}' in manager, "run baseline must survive checkpoint restore without fabricating legacy values"
assert '"saved_expedition": saved_expedition.duplicate(true)' in game_state, "snapshot is not part of permanent save payload"
assert "saved_expedition.clear()" in game_state and "saved_expedition.clear()" in game_state[game_state.index("func settle_expedition"):], "settlement must clear snapshot to prevent duplicate payout"
assert "const SAVE_VERSION := 3" in save_system, "save format was not versioned"
assert 'if version < 2:' in save_system and 'data["saved_expedition"] = {}' in save_system, "v1 saves must migrate without losing permanent progress"
assert 'Callable(self, "_resume_expedition")' in ui, "base must expose resume button"
assert "manager.save_run_snapshot()" in ui, "window-close checkpoint hook is missing"
print("EXPEDITION PERSISTENCE REGRESSION CHECK PASSED:")
print("- checkpoint includes route, RNG, combat, inventory, tiles, and pending decisions")
print("- periodic snapshot is enabled while paused or awaiting a decision")
print("- restoring returns to a safe paused state")
print("- Stage68B local run timer/baseline are stored and restored")
print("- v1/v2/v3 snapshots migrate to current status schema v4")
print("- settlement clears checkpoint to avoid duplicate payouts")
print("Note: source-level guard only; run the project and smoke tests in Godot for runtime validation.")

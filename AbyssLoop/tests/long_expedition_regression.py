"""Regression guards for replacing the selectable 12-loop mode with eight-floor progression."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
workflow = (ROOT.parent / ".github/workflows/abyssloop-engine-qa.yml").read_text(encoding="utf-8")
checks = {
    "the campaign terminates through the eighth floor rather than a 12-loop mode": 'const FLOOR_COUNT: int = 8' in registry and 'ContentRegistry.FLOOR_COUNT' in manager and 'Все 8 этажей пройдены' in manager,
    "the guardian loop schedule is provided by floor content": 'floor_config.get("boss_loop"' in manager and 'boss_loop_interval' in registry,
    "a floor returns safely after its guardian is defeated and the next floor unlocks": 'func _maybe_finish_floor_after_boss()' in manager and 'run_ledger["floor_cleared"] = true' in manager and 'summary_metadata.get("floor_cleared", false)' in state,
    "the base UI launches a selected floor without mode/difficulty selectors": 'func _on_floor_selected(index: int)' in ui and 'selected_floor_number' in ui and 'selected_difficulty_id' not in ui and 'selected_expedition_mode_id' not in ui,
    "the Godot-only pipeline runs floor progression acceptance instead of 12-loop acceptance": 'floor_progression_runtime_acceptance_runner.tscn' in workflow and 'long_expedition_runtime_acceptance_runner.tscn' not in workflow,
    "floor unlock persistence clamps old or malformed save values": 'clampi(int(saved.get("highest_unlocked_floor", 1)), 1, ContentRegistry.FLOOR_COUNT)' in state,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"[{'PASS' if ok else 'FAIL'}] {name}")
if failed:
    raise SystemExit("CAMPAIGN PROGRESSION REGRESSION FAILED: " + ", ".join(failed))
print(f"CAMPAIGN PROGRESSION REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Legacy fields may remain for old saves, but selectable difficulty and 12-loop mode are not part of the player flow.")

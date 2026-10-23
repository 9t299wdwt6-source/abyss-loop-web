"""Checks that objectives can be previewed before a run and filter invalid definitions."""
from pathlib import Path
import re
import sys
ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "each objective has a supported real progress kind": 'supported_objective_kinds := ["loops", "bosses", "victories", "events", "scrap"]' in registry and 'objective:%s uses unsupported progress kind' in registry,
    "objective target and text are validated": 'objective:%s requires readable condition text' in registry and 'int(objective.get("target", 0)) > 1000' in registry,
    "all run modifiers are checked for objective reachability": 'func _objective_is_feasible_for_run' in manager and 'ContentRegistry.RUN_MODIFIERS.has(requested_modifier_id)' in manager,
    "run creation and preview share deterministic selection": '_choose_objective_for_seed(run_seed, run_modifier_id)' in manager and 'preview_objective_for_seed(_get_preview_seed(), selected_modifier_id)' in ui,
    "random seed preview is the seed actually passed to start": 'requested_seed = _get_preview_seed()' in ui and 'pending_preview_seed = _make_preview_seed()' in ui,
    "condition and reward are visible before the expedition starts": 'АВТОЦЕЛЬ ЭКСПЕДИЦИИ (по seed):' in ui and 'Условие:' in ui and 'Награда:' in ui,
    "seed edits immediately refresh objective preview": 'seed_input.text_changed.connect(_on_seed_input_changed)' in ui,
    "objective preview is exercised by the Godot smoke test": 'objective_manager.preview_objective_for_seed' in smoke and 'selected objective must be reachable' in smoke,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    print("OBJECTIVE AVAILABILITY REGRESSION FAILED: " + ", ".join(failed)); sys.exit(1)
print(f"OBJECTIVE AVAILABILITY REGRESSION PASSED: {len(checks)} static checks. Runtime remains separate.")

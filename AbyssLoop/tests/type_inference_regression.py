"""Regression guard for GDScript type inference failures in diagnostic UI declarations."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
reporter = (ROOT / "scripts/ui/developer_diagnostics_report.gd").read_text(encoding="utf-8")
expected = "var current_is_boss: bool = not manager.enemy.is_empty() and bool(manager.enemy.get(\"is_boss\", false))"
if expected not in source:
    print("TYPE INFERENCE REGRESSION CHECK FAILED: current_is_boss must have explicit bool type")
    sys.exit(1)
if "var current_is_boss := not manager.enemy.is_empty() and bool(manager.enemy.get(\"is_boss\", false))" in source:
    print("TYPE INFERENCE REGRESSION CHECK FAILED: problematic inferred declaration is still present")
    sys.exit(1)
for expected in (
    "var route_count: int = int(manager.route.size())",
    "var closed_loop_ok: bool = bool(manager.route_system.is_closed_loop(manager.route))",
):
    if expected not in reporter:
        print(f"TYPE INFERENCE REGRESSION CHECK FAILED: missing explicit type declaration: {expected}")
        sys.exit(1)
for problematic in (
    "var route_count := manager.route.size()",
    "var closed_loop_ok := manager.route_system.is_closed_loop(manager.route)",
):
    if problematic in reporter:
        print(f"TYPE INFERENCE REGRESSION CHECK FAILED: unsafe inferred declaration remains: {problematic}")
        sys.exit(1)
print("TYPE INFERENCE REGRESSION CHECK PASSED: boss, route count, and loop status have explicit types.")
print("Note: this source guard does not replace Godot runtime compilation.")

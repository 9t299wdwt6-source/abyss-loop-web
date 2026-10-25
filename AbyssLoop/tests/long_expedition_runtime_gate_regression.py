"""Static regression guard that the full long-expedition runtime gate stays wired into CI."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
runner = (ROOT / "tests/long_expedition_runtime_acceptance.gd").read_text(encoding="utf-8")
scene = (ROOT / "tests/long_expedition_runtime_acceptance_runner.tscn").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/abyssloop-web.yml").read_text(encoding="utf-8")

checks = {
    "runtime gate starts the actual long-expedition mode": 'manager.start_run("standard", LONG_SEED, "standard", "none", "long_expedition")' in runner,
    "runtime gate asserts 12 loops and four required bosses": '"target_loops", 0)) == 12' in runner and '"target_bosses", 0)) == 4' in runner,
    "runtime gate verifies the four configured boss loops": '_boss_loops_seen == [3, 6, 9, 12]' in runner,
    "runtime gate verifies the four durable checkpoints and endgame result": 'checkpoint_loops == [3, 6, 9, 12]' in runner and 'final_summary.get("endgame_completed", false)' in runner,
    "runtime gate exercises production route and encounter methods": 'manager._tick_route(0.0)' in runner and 'manager._tick_combat(0.01)' in runner and 'manager.resolve_event_choice(choice_id)' in runner,
    "runtime scene points at the actual acceptance script": 'path="res://tests/long_expedition_runtime_acceptance.gd"' in scene,
    "CI runs the long expedition runtime scene with a bounded timeout": 'Run 12-loop long expedition runtime acceptance' in workflow and 'res://tests/long_expedition_runtime_acceptance_runner.tscn' in workflow and 'timeout 90s' in workflow,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + name)
if failed:
    print("LONG EXPEDITION RUNTIME GATE REGRESSION FAILED: " + ", ".join(failed))
    sys.exit(1)
print(f"LONG EXPEDITION RUNTIME GATE REGRESSION PASSED: {len(checks)}/{len(checks)} checks")

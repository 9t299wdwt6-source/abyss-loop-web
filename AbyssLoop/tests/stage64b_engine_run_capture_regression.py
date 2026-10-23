"""Regression guards for Stage64B automated in-engine capture.

The companion GDScript runs the real ExpeditionManager and combat/route processing.
These source checks make its evidence boundaries explicit; they are not balance data.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAPTURE_PATH = ROOT / "tests" / "stage64b_engine_run_capture.gd"
SCENE_PATH = ROOT / "tests" / "stage64b_engine_run_capture_runner.tscn"
CAPTURE = CAPTURE_PATH.read_text(encoding="utf-8")
SCENE = SCENE_PATH.read_text(encoding="utf-8")
ANALYZER = (ROOT / "tools" / "real_run_balance.py").read_text(encoding="utf-8")

checks = {
    "capture uses the real ExpeditionManager class and start_run": 'preload("res://scripts/systems/expedition_manager.gd")' in CAPTURE and 'manager.start_run("standard", seed_value, "standard", "none", "standard")' in CAPTURE,
    "five fixed unique seeds meet the minimum sample design": "RUN_SEEDS: Array[int] = [8675309, 8675311, 8675313, 8675317, 8675323]" in CAPTURE,
    "capture uses real route/combat processing rather than directly ticking internals": "await get_tree().process_frame" in CAPTURE and "manager._tick_route(" not in CAPTURE and "manager._tick_combat(" not in CAPTURE,
    "capture requires a real road and landscape placement in each run": "_place_one_legal_road_tile(manager)" in CAPTURE and "_place_one_legal_landscape_tile(manager)" in CAPTURE and 'manager.placed_tiles.is_empty() or manager.world_tiles.is_empty()' in CAPTURE,
    "capture never forces player/enemy health, loot, or damage": all(token not in CAPTURE for token in ['manager.enemy["hp"] =', 'manager.hero["hp"] =', 'fighter["hp"] =', 'fighter["defense"] =', 'manager.run_ledger["scrap"] =']),
    "capture stores the actual completed summary with telemetry schema 1": 'completed_summary.get("telemetry_schema", 0)' in CAPTURE and 'completed_summary.get("run_id", "")' in CAPTURE and 'completed_summary["capture_kind"] = "automated_engine_run"' in CAPTURE,
    "capture labels the data as scripted and not a human-playtest or balance verdict": '"not_human_playtest": true' in CAPTURE and '"not_a_balance_verdict": true' in CAPTURE,
    "capture has a bounded frame ceiling and explicit failure exit": "MAX_PROCESS_FRAMES_PER_RUN" in CAPTURE and "get_tree().quit(1)" in CAPTURE,
    "scene launches the scripted Node with project autoloads": 'path="res://tests/stage64b_engine_run_capture.gd"' in SCENE,
    "analysis separates automated engine QA from profile-history rows": 'capture_kind' in ANALYZER and 'automated_engine_run' in ANALYZER and 'manual_playtest' in ANALYZER,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    raise SystemExit(f"STAGE64B ENGINE CAPTURE REGRESSION FAILED: {failed}")
print(f"STAGE64B ENGINE CAPTURE REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("These source checks do not claim that the Godot capture has run or that balance was measured.")

"""Source regression guards for the eight-floor Stage64B real-engine baseline capture."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
CAPTURE = (ROOT / "tests" / "stage64b_engine_run_capture.gd").read_text(encoding="utf-8")
SCENE = (ROOT / "tests" / "stage64b_engine_run_capture_runner.tscn").read_text(encoding="utf-8")
ANALYZER = (ROOT / "tools" / "real_run_balance.py").read_text(encoding="utf-8")

checks = {
    "capture uses production ExpeditionManager and explicit floor selection": 'preload("res://scripts/systems/expedition_manager.gd")' in CAPTURE and 'manager.start_run("standard", seed_value, modifier_id, contract_id, "standard", floor_number)' in CAPTURE,
    "matrix has exactly eight floors and five repeatable seeds per floor": 'FLOOR_NUMBERS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]' in CAPTURE and 'BASE_SEEDS: Array[int] = [8675309, 8675311, 8675313, 8675317, 8675323]' in CAPTURE and '"capture_group": "floor_baseline"' in CAPTURE,
    "old selectable difficulty and 12-loop mode are absent from the Stage64B matrix": 'DIFFICULTY_IDS' not in CAPTURE and 'MODE_IDS' not in CAPTURE and 'LONG_TARGET_LOOPS' not in CAPTURE and 'long_expedition' not in CAPTURE,
    "all scenarios use deterministic production route and combat steps": 'manager._tick_route(ROUTE_SCALED_DELTA)' in CAPTURE and 'manager._tick_combat(COMBAT_SCALED_DELTA)' in CAPTURE and 'const COMBAT_SCALED_DELTA: float = 0.05' in CAPTURE,
    "capture never forces player/enemy stats, loot, damage, or rewards": all(token not in CAPTURE for token in ['manager.enemy["hp"] =', 'manager.hero["hp"] =', 'manager.hero["attack"] =', 'fighter["hp"] =', 'manager.run_ledger["scrap"] =']),
    "road and landscape placement use production legality checks": 'manager.tile_system.can_place(manager.route, manager.placed_tiles, route_index, tile)' in CAPTURE and 'manager.tile_system.can_place_world(manager.route, manager.world_tiles, cell_id, tile' in CAPTURE and 'TileSystemScript.map_world_cell_id(x, y)' in CAPTURE,
    "supplemental placement draws are bounded and use explicit types": CAPTURE.count('supplemental_draws < 12') >= 2 and CAPTURE.count('var unlock_rare: bool =') >= 2 and CAPTURE.count('var supplemental_index: int =') >= 2,
    "run outputs are floor tagged with unique Stage64B IDs": 'user://STAGE64B_AUTOMATED_ENGINE_RUNS.json' in CAPTURE and '"capture_floor_number"] = floor_number' in CAPTURE and '"run_id"] = "qa-stage64b-' in CAPTURE,
    "result rows preserve floor and telemetry fields": 'completed_summary.get("floor_number", 0)' in CAPTURE and 'completed_summary.get("telemetry_schema", 0)' in CAPTURE and 'completed_summary.get("road_placements", 0)' in CAPTURE and 'completed_summary.get("world_placements", 0)' in CAPTURE,
    "capture is explicitly labelled automated QA, not a human test or balance verdict": '"not_human_playtest": true' in CAPTURE and '"not_a_balance_verdict": true' in CAPTURE,
    "runner invokes this capture and analyzer groups results by floor": 'path="res://tests/stage64b_engine_run_capture.gd"' in SCENE and 'row["floor_number"] = floor_number' in ANALYZER and 'row["floor_name"] = floor_name' in ANALYZER,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"[{'PASS' if passed else 'FAIL'}] {name}")
if failed:
    raise SystemExit("STAGE64B FLOOR BASELINE CAPTURE REGRESSION FAILED: " + ", ".join(failed))
print(f"STAGE64B FLOOR BASELINE CAPTURE REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Static guards only; actual Godot observations are reported separately and are not human playtest data.")

"""Source and CI guards for the Stage92 eight-floor engine capture."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
capture = (ROOT / "tests/stage92_floor_progression_capture.gd").read_text(encoding="utf-8")
scene = (ROOT / "tests/stage92_floor_progression_capture_runner.tscn").read_text(encoding="utf-8")
workflow = (ROOT.parent / ".github/workflows/abyssloop-web.yml").read_text(encoding="utf-8")
reporter = (ROOT / "tools/floor_progression_report.py").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")

checks = {
    "capture contains eight floors and three deterministic seeds": "FLOOR_IDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]" in capture and "FIXED_SEEDS: Array[int] = [91001, 91003, 91007]" in capture,
    "cases unlock their target floor through the production profile API": "GameState.unlock_abyss_floor(unlock_id)" in capture and 'manager.start_run("standard", seed_value, "standard", "none", "standard", floor_id)' in capture,
    "capture drives real route, combat, event, perk and settlement methods": "manager._tick_route(ROUTE_DELTA)" in capture and "manager._tick_combat(COMBAT_DELTA)" in capture and "manager.resolve_event_choice(choice_id)" in capture and "manager.choose_perk(perk_id)" in capture,
    "floor card samples invoke production TileSystem with a separate deterministic RNG": "manager.tile_system.draw_tile(sample_rng, false, [], floor_id)" in capture and "floor_card_pool_hits" in capture,
    "capture never forces hero or enemy stats": all(token not in capture for token in ['manager.hero["hp"] =', 'manager.enemy["hp"] =', 'fighter["hp"] =', 'fighter["attack"] =']),
    "rows retain floor identity and automated source label": 'summary["floor_id"] = floor_id' in capture and 'summary["floor_name"]' in capture and 'summary["capture_kind"] = "automated_engine_run"' in capture,
    "all 24 cases must produce valid summaries or fail": "FLOOR_IDS.size() * FIXED_SEEDS.size()" in capture and "MAX_SIMULATION_STEPS" in capture and "get_tree().quit(1)" in capture,
    "runner scene launches the Stage92 capture script": 'path="res://tests/stage92_floor_progression_capture.gd"' in scene,
    "CI runs the Stage92 matrix and writes the floor report": "Capture Stage92 eight-floor progression engine matrix" in workflow and "stage92_floor_progression_capture_runner.tscn" in workflow and "floor_progression_report.py" in workflow and "STAGE92_FLOOR_PROGRESSION.json" in workflow,
    "legacy difficulty/contract matrix capture steps are no longer used": "Capture Stage71 difficulty/mode balance matrix and contract coverage" not in workflow and "Capture Stage71 real-engine balance matrix" not in workflow,
    "report groups floors 1..8 and warns against balance verdicts": '"## Поэтажная сводка"' in reporter and '"automated_engine_run"' in reporter and "не статистически достаточная выборка" in reporter and "range(1, 9)" in reporter,
    "production manager does not read live pressure from legacy difficulty presets": "DIFFICULTY_PRESETS.get(difficulty_id" not in manager and "func get_floor_config() -> Dictionary:" in manager,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + name)
if failed:
    raise SystemExit("STAGE92 FLOOR CAPTURE REGRESSION FAILED: " + ", ".join(failed))
print(f"STAGE92 FLOOR CAPTURE REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Source checks only; the Godot CI job must complete the in-engine matrix before runtime acceptance is claimed.")

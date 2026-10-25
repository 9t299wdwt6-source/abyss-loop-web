"""Source regression guards for the Stage71 real-engine balance matrix."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
capture = (ROOT / "tests/stage71_balance_matrix_capture.gd").read_text(encoding="utf-8")
scene = (ROOT / "tests/stage71_balance_matrix_runner.tscn").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/abyssloop-web.yml").read_text(encoding="utf-8")
analyzer = (ROOT / "tools/real_run_balance.py").read_text(encoding="utf-8")

checks = {
    "matrix covers all four registered difficulty presets": all(f'"{difficulty}"' in capture for difficulty in ["standard", "volatile", "attrition", "abyssal"]),
    "matrix includes three same-seed-count repeats per difficulty in the ordinary mode": 'BASE_SEEDS: Array[int] = [8675309, 8675311, 8675313]' in capture and '"difficulty_standard_one_loop"' in capture,
    "matrix includes the long mode at three loops across all difficulties": '"difficulty_long_mode_three_loops"' in capture and '"long_expedition", 3, 1, LONG_MODE_SEEDS' in capture,
    "matrix has repeat groups for the three non-standard modifiers": all(f'"modifier_{modifier}"' in capture for modifier in ["resonance", "scarce", "unstable"]),
    "matrix has repeat groups for three separately identified contracts": all(f'"contract_{contract}"' in capture for contract in ["bounty_hunter", "event_archive", "landscape_survey"]),
    "landscape survey really attempts three legal landscape placements": '"landscape_survey", "standard", 3, 3, LANDSCAPE_SEEDS' in capture and "func _place_landscape_tiles(manager: Variant, target_count: int) -> int:" in capture,
    "placement capture passes each real candidate tile into road and modern-grid previews": "can_place(manager.route, manager.placed_tiles, route_index, tile)" in capture and "manager.route, manager.world_tiles, cell_id, tile," in capture and "TileSystemScript.map_world_cell_id(x, y)" in capture and "for hand_index in range(manager.tile_hand.size()):" in capture,
    "placement coverage uses bounded production draws rather than bypassing placement rules": "manager.tile_system.draw_tile(manager._rng_for_draw(), unlock_rare)" in capture and "supplemental_draws >= 12" in capture and "_try_place_landscape_from_hand_slot(manager, supplemental_index)" in capture and "manager.tile_hand.remove_at(supplemental_index)" in capture,
    "each case uses the actual ExpeditionManager with a deterministic seed": 'manager.start_run(difficulty_id, seed_value, modifier_id, contract_id, mode_id)' in capture and 'GameState.reset_progress()' in capture,
    "test leaves game combat and reward formulas unmodified": 'manager.hero["hp"] =' not in capture and 'fighter["hp"] =' not in capture and 'manager.enemy["hp"]' not in capture,
    "matrix captures contract and modifier challenge IDs separately": '"capture_contract_id"' in capture and '"capture_challenge_id"' in capture,
    "scene runs the Stage71 capture node": 'path="res://tests/stage71_balance_matrix_capture.gd"' in scene,
    "CI executes the matrix with a bounded timeout and preserves output": 'Capture Stage71 real-engine balance matrix' in workflow and 'timeout 900s' in workflow and 'STAGE71_BALANCE_MATRIX.json' in workflow and 'STAGE71_BALANCE_MATRIX_REPORT.md' in workflow,
    "analysis separates contracts and challenges into comparison groups": 'row["contract_id"]' in analyzer and 'row["challenge_id"]' in analyzer and '"contract_id"]' in analyzer and '"challenge_id"]' in analyzer,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + name)
if failed:
    raise SystemExit("STAGE71 BALANCE MATRIX REGRESSION FAILED: " + ", ".join(failed))
print(f"STAGE71 BALANCE MATRIX REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("These are source guards; Stage71 result data still requires the actual Godot runtime capture.")

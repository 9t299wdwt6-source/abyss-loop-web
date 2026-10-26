"""Source guards for the eight-floor real-engine balance matrix."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
capture = (ROOT / "tests/stage71_balance_matrix_capture.gd").read_text(encoding="utf-8")
scene = (ROOT / "tests/stage71_balance_matrix_runner.tscn").read_text(encoding="utf-8")
workflow = (ROOT.parent / ".github/workflows/abyssloop-engine-qa.yml").read_text(encoding="utf-8")
analyzer = (ROOT / "tools/real_run_balance.py").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")

checks = {
    "matrix covers every floor from one through eight": 'FLOOR_NUMBERS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]' in capture and 'ContentRegistry.FLOOR_COUNT' in manager,
    "base observations repeat three fixed seeds on every floor": 'BASE_SEEDS: Array[int] = [8675309, 8675311, 8675313]' in capture and 'for floor_number in FLOOR_NUMBERS:' in capture and 'for seed_value in BASE_SEEDS:' in capture,
    "route modifier comparisons use repeatable floors one, four, and eight": 'MODIFIER_FLOORS: Array[int] = [1, 4, 8]' in capture and all(f'"{modifier}"' in capture for modifier in ['resonance', 'scarce', 'unstable']),
    "case creation builds baseline runs for all floors and modifier cross-samples": '"capture_group": "floor_baseline"' in capture and '"modifier_id": modifier_id' in capture and '"capture_group": "modifier_%s" % modifier_id' in capture,
    "every case uses the production manager with selected floor and deterministic seed": 'manager.start_run("standard", seed_value, modifier_id, contract_id, "standard", floor_number)' in capture and 'GameState.reset_progress()' in capture and 'GameState.highest_unlocked_floor = floor_number' in capture,
    "route and combat are stepped through production handlers": 'manager._tick_route(ROUTE_SCALED_DELTA)' in capture and 'manager._tick_combat(COMBAT_SCALED_DELTA)' in capture and 'const ROUTE_SCALED_DELTA: float = 1.24' in capture and 'const COMBAT_SCALED_DELTA: float = 0.05' in capture,
    "test uses production stats without forcing hero/enemy health or reward values": all(token not in capture for token in ['manager.hero["hp"] =', 'manager.hero["attack"] =', 'fighter["hp"] =', 'manager.enemy["hp"] =', 'manager.run_ledger["scrap"] =']),
    "placement test searches candidate tiles and enforces production road/landscape rules": 'manager.tile_system.can_place(manager.route, manager.placed_tiles, route_index, tile)' in capture and 'manager.tile_system.can_place_world(manager.route, manager.world_tiles, cell_id, tile' in capture and 'TileSystemScript.map_world_cell_id(x, y)' in capture,
    "tile draw fallback is bounded and uses explicit local types": capture.count('supplemental_draws < 12') >= 2 and capture.count('var unlock_rare: bool =') >= 2 and capture.count('var supplemental_index: int =') >= 2 and 'manager.tile_system.draw_tile(manager._rng_for_draw(), unlock_rare)' in capture,
    "capture models equipment choices using production item power and equip methods": 'func _equip_better_bag_items(manager: Variant) -> int:' in capture and 'manager.inventory_system.item_power(candidate)' in capture and 'manager.equip_bag_item(item_id)' in capture and '"capture_auto_equips"] = auto_equips' in capture,
    "capture models tactical tile play using legal candidates and health-aware utility": 'func _place_best_legal_tile(manager: Variant) -> bool:' in capture and 'func _tile_utility_score(tile: Dictionary, manager: Variant) -> float:' in capture and 'manager.place_tile(best_hand_index, best_route_index)' in capture and 'manager.place_world_tile(best_hand_index, best_world_cell)' in capture and '"capture_strategic_placements"] = strategic_placements' in capture,
    "summary records floor, modifier, seed, durable identity and placement telemetry": all(token in capture for token in ['"capture_kind"] = "automated_engine_run"', '"capture_floor_number"] = floor_number', '"capture_modifier_id"] = modifier_id', '"floor_number", 0', '"run_id"] = "qa-stage71-', '"road_placements"', '"world_placements"']),
    "scene runs the Stage71 floor capture": 'path="res://tests/stage71_balance_matrix_capture.gd"' in scene,
    "Godot-only CI captures and stores the floor matrix and report without web export": 'res://tests/stage71_balance_matrix_runner.tscn' in workflow and 'timeout 900s' in workflow and 'STAGE71_BALANCE_MATRIX.json' in workflow and 'STAGE71_BALANCE_MATRIX_REPORT.md' in workflow and 'Export Godot Web build' not in workflow,
    "analyzer groups comparisons by floor and scenario and does not use selectable difficulty/mode columns": 'int(row.get("floor_number", 1))' in analyzer and 'row["floor_number"] = floor_number' in analyzer and 'row["capture_group"] = capture_group' in analyzer and 'key[1], key[2], key[3]' in analyzer,
    "road placement failure rolls back the hand, board, and log": 'var previous_placed_tiles: Dictionary = placed_tiles.duplicate(true)' in manager and 'if not save_run_snapshot():' in manager and 'Карта возвращена в руку, поле восстановлено.' in manager,
    "landscape rollback restores discovery as well as tile hand": 'var previous_world_tiles: Dictionary = world_tiles.duplicate(true)' in manager and 'var previous_discovered_cells: Dictionary = discovered_world_cells.duplicate(true)' in manager and 'Карта возвращена в руку, ландшафт восстановлен.' in manager,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"[{'PASS' if ok else 'FAIL'}] {name}")
if failed:
    raise SystemExit("STAGE71 FLOOR BALANCE MATRIX REGRESSION FAILED: " + ", ".join(failed))
print(f"STAGE71 FLOOR BALANCE MATRIX REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Static guards only; the captured JSON and Godot runtime results must be inspected before tuning balance.")

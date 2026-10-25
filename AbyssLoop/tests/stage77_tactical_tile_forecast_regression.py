"""Stage 77 regressions for actionable route and landscape placement forecasts."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
tile = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")

checks = {
    "route forecast discovers pair synergies created when the selected tile is only the neighbour": "func get_new_route_synergy_matches" in tile and "_get_route_pair_synergy_matches(after_tiles, trigger_index, route_size)" in tile,
    "route pair match identity keeps trigger and neighbour positions separate": '"%s|%d|%d" % [str(match_data.get("id", "")), int(match_data.get("trigger_index", -1)), int(match_data.get("neighbor_index", -1))]' in tile,
    "forecast evaluates changed node and adjacent trigger nodes on the closed route": "posmod(changed_index - 1, route_size)" in tile and "posmod(changed_index + 1, route_size)" in tile,
    "immutable start node is excluded from route synergy trigger and placement targets": "if route_size <= 1 or trigger_index <= 0 or trigger_index >= route_size" in tile and "if candidate_index > 0 and candidate_index < route_size" in tile,
    "route forecast shows the target node that will activate neighbour-triggered synergy": "Новая связка «%s» сработает при посещении узла %d" in tile,
    "route forecast distinguishes aggregate new synergy effects from node-level caps": "до общих лимитов узла" in tile and '"new_synergy_effects": newly_created_effects.duplicate(true)' in tile,
    "route preview returns new pair-synergy instances for downstream UI and tests": '"new_route_synergy_matches": newly_activated_route_synergies.duplicate(true)' in tile,
    "world forecast reports enemy pool for landscape-only threats": 'definition.get("enemy_pool", [])' in tile and "Угроза участка:" in tile,
    "world forecast uses actually equipped landscape affinity effects": "inventory_system.get_landscape_affinity_effects(equipment, tile_id)" in tile and '"equipment_affinity": affinity_effects.duplicate(true)' in tile,
    "world forecast shows affinity resource and visit-modifier effects": "Эффект надетой экипировки на этом ландшафте" in tile and 'for affinity_key in ["spawn_bonus", "enemy_bonus", "reward_bonus"]' in tile,
    "world forecast previews a newly prepared secret recipe before placement": "func get_new_landscape_secret_recipes" in tile and "Тайна подготовлена:" in tile,
    "secret recipe matching respects physical adjacency and same route sector": 'int(neighbor.get("route_index", -1)) != route_index' in tile and "world_cell_neighbors(changed_cell)" in tile,
    "landscape forecast includes affinity data without mutating equipment or tiles": 'var simulated := world_tiles.duplicate(true)' in tile and 'var affinity_effects := inventory_system.get_landscape_affinity_effects(equipment, tile_id)' in tile,
    "road preview still relies on the shared route placement validator": "var placement: Dictionary = can_place(route, placed_tiles, index, tile)" in tile,
    "landscape preview still relies on the shared landscape placement validator": "var placement := can_place_world(route, world_tiles, cell_id, tile, route_shape_id, route_geometry_seed)" in tile,
    "UI routes hovered road and landscape cells through the shared preview functions": "get_placement_preview(manager.route, manager.placed_tiles, cell_index, selected_tile, manager.equipment)" in ui and "get_world_placement_preview(manager.route, manager.world_tiles, cell_id, selected_tile, manager.equipment, manager.get_route_shape_id(), manager.get_route_geometry_seed())" in ui,
    "Godot smoke covers reverse-order road synergy and land-affinity forecasts": "reverse_route_preview" in smoke and "equipped_affinity_preview" in smoke and "new_secret_recipes" in smoke,
    "Godot smoke validates that route forecast leaves the live map unchanged": "route_tiles_before_preview" in smoke and "placement forecasts must not mutate route tiles" in smoke,
}
failed = [label for label, passed in checks.items() if not passed]
for label, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {label}")
if failed:
    print("STAGE 77 TILE FORECAST REGRESSION FAILED: " + "; ".join(failed))
    sys.exit(1)
print(f"STAGE 77 TILE FORECAST REGRESSION PASSED: {len(checks)}/{len(checks)} source guards")
print("Source-level only; Godot parsing/runtime and visual acceptance remain separate gates.")

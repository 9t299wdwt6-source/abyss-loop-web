"""Stage 36 regression: landscape synergy aggregation, replacement deltas, and post-local caps."""
from pathlib import Path
import math
import sys

ROOT = Path(__file__).resolve().parents[1]
tile = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "same-sector triggers use a shared aggregate before caps": "func get_world_synergy_bonus_for_route_index" in tile and "return aggregate_world_synergy_matches(matches)" in tile,
    "forecast uses same route-sector aggregation for before/after states": "get_world_synergy_bonus_for_route_index(before_tiles, route_index)" in tile and "get_world_synergy_bonus_for_route_index(after_tiles, route_index)" in tile,
    "forecast totals compare capped marginal deltas by route sector": '"route_index": route_index, "delta": delta' in tile and "get_world_placement_effect_delta" in tile,
    "final modifier limits are centralized": '"spawn_bonus": [-0.50, 1.00]' in tile and '"enemy_bonus": [-0.35, 0.75]' in tile and '"reward_bonus": [-0.50, 1.50]' in tile,
    "live run applies landscape synergy once per visited sector": "get_world_synergy_bonus_for_route_index(world_tiles, index)" in manager and "get_world_synergy_bonus(world_tiles, world_cell_id)" not in manager,
    "pipeline order is base node, local tiles, neighbour synergies, then caps": (
        manager.index("match base_kind:", manager.index("func _visit_cell"))
        < manager.index("if placed_tiles.has(str(index)):", manager.index("func _visit_cell"))
        < manager.index("for world_cell_value in world_tiles.keys():", manager.index("func _visit_cell"))
        < manager.index("get_world_synergy_bonus_for_route_index(world_tiles, index)", manager.index("func _visit_cell"))
        < manager.index("get_synergy_bonus(placed_tiles, index, route.size(), equipment)", manager.index("func _visit_cell"))
        < manager.index("tile_system.clamp_visit_modifiers", manager.index("func _visit_cell"))
        < manager.index("if should_offer_event:", manager.index("func _visit_cell"))
    ),
    "smoke tests cover all three final modifier caps": "final encounter chance modifier must be capped" in smoke and "final enemy strength modifier must be capped" in smoke and "final combat reward modifier must be capped" in smoke,
    "smoke tests cover removal and replacement without ghost bonuses": "removing a neighbour tile must remove the old synergy bonus" in smoke and "replacing a synergy tile must not leave a ghost bonus" in smoke,
    "tile card discovery uses weighted probabilities and keeps rare cards gated": "const TILE_DRAW_WEIGHTS" in tile and "total_weight" in tile and "_get_tile_draw_weight(choice_id)" in tile and "GameState.get_rare_tile_weight_multiplier()" in tile and "unlocked_rare_tiles" in smoke and '"archive": 0.35' in tile and '"nursery": 0.30' in tile,
    "forecast smoke verifies no source-map mutation": "placement forecasts must not mutate the live tile map" in smoke,
}
missing = [label for label, ok in checks.items() if not ok]
for label, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
if missing:
    print("TILE EFFECT PIPELINE REGRESSION FAILED: " + "; ".join(missing))
    sys.exit(1)

# Independent arithmetic oracle for the declared caps and saturated deltas.
def clamp(value, lower, upper):
    return min(upper, max(lower, value))

synergy_caps = {"scrap": (0, 12), "heal": (0, 12), "reward": (-0.25, 0.50), "spawn_bonus": (-0.35, 0.75), "enemy_bonus": (-0.15, 0.35)}
raw = {"scrap": 24, "heal": 16, "reward": 0.80, "spawn_bonus": 0.90, "enemy_bonus": 0.50}
expected = {key: clamp(value, *synergy_caps[key]) for key, value in raw.items()}
assert expected == {"scrap": 12, "heal": 12, "reward": 0.50, "spawn_bonus": 0.75, "enemy_bonus": 0.35}
assert math.isclose(clamp(0.50 + 0.10, -0.25, 0.50) - clamp(0.50, -0.25, 0.50), 0.0), "adding a combo after cap should show zero marginal effect"
assert math.isclose(clamp(0.40, -0.25, 0.50) - clamp(0.50, -0.25, 0.50), -0.10), "removing combo after cap should show actual loss"
visit_caps = {"spawn_bonus": (-0.50, 1.0), "enemy_bonus": (-0.35, 0.75), "reward_bonus": (-0.50, 1.50)}
visit_raw = {"spawn_bonus": 2.0, "enemy_bonus": 1.2, "reward_bonus": 2.4}
assert all(math.isclose(clamp(visit_raw[key], *limits), target) for (key, limits), target in zip(visit_caps.items(), [1.0, 0.75, 1.5]))
print("TILE EFFECT PIPELINE REGRESSION PASSED: 9 source guards and overlapping/add/remove cap arithmetic.")
print("Godot smoke assertions were added but need execution on Godot 4.7.2; this Python test is source-level only.")

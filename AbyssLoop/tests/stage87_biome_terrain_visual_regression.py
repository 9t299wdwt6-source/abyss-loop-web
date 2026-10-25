"""Stage 87 source and reference-model guards for deterministic terrain biomes.

This test checks the visualization contract and a separate grid model. It does not
compile/execute the GDScript renderer; Godot runtime acceptance remains separate.
"""
from __future__ import annotations
from collections import Counter
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
tile = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")

checks = {
    "terrain rendering uses route geometry's real road cells": 'var road_cells: Array = route_geometry.get("road_cells", [])' in view and 'road_lookup["%d:%d" % [road_coord.x, road_coord.y]] = true' in view,
    "roadside cells are computed by four-neighbour adjacency, not diagonals": 'for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:' in view and 'roadside_lookup[adjacent_id] = true' in view,
    "terrain biomes are visual-only and do not change gameplay placement": "Cosmetic biome regions only" in view and "func _visual_biome_for_cell(col: int, row: int) -> int:" in view,
    "all four palettes are defined": all(color in view for color in ["#314b39", "#2f4850", "#4a493b", "#38384d"]),
    "four biome-specific terrain detail families are drawn": all(token in view for token in ['Color("#a0bd76"', 'Color("#85c6ca"', 'Color("#d5c8a4"', 'Color("#8983bd"']),
    "terrain variation remains deterministic from grid coordinate and route seed": 'posmod(col * 17 + row * 29 + candidate_index * 13 + small_seed * 7, 11)' in view and 'var seed_shift := Vector2(' in view and 'posmod(col * 17 + row * 31 + posmod(route_geometry_seed, 97) * 7, 16)' in view,
    "roadside rim highlights only the edge facing the road": 'func _draw_roadside_edge(cell_rect: Rect2, coord: Vector2i, road_lookup: Dictionary, cell_size: float) -> void:' in view and all(token in view for token in ['road_lookup.has(left_id)', 'road_lookup.has(right_id)', 'road_lookup.has(up_id)', 'road_lookup.has(down_id)']),
    "road rendering stays a separate pass after the terrain layer": view.index('_draw_map_grid(route_geometry)') < view.index('_draw_road_tiles(route_geometry)'),
    "legacy placement zone rules stay unchanged": 'static func world_cell_is_roadside_for_seed' in tile and 'placement_zone == "roadside"' in tile and 'placement_zone == "landscape"' in tile,
}
failed = [label for label, ok in checks.items() if not ok]
for label, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
if failed:
    print("STAGE 87 SOURCE CHECK FAILED: " + "; ".join(failed))
    sys.exit(1)

COLUMNS, ROWS = 19, 14
CENTERS = [(2.5, 2.3), (15.7, 2.6), (15.8, 10.7), (2.8, 10.4)]

def visual_biome(col: int, row: int, route_seed: int) -> int:
    small_seed = route_seed % 97
    best_index, best_score = 0, float("inf")
    for index, (center_x, center_y) in enumerate(CENTERS):
        shift_x = ((small_seed + index * 3) % 5 - 2) * 0.45
        shift_y = ((small_seed * 3 + index * 7) % 5 - 2) * 0.32
        center_x += shift_x
        center_y += shift_y
        jitter = ((col * 17 + row * 29 + index * 13 + small_seed * 7) % 11) * 0.055
        score = (col - center_x) ** 2 + (row - center_y) ** 2 + jitter
        if score < best_score:
            best_index, best_score = index, score
    return best_index

seed_signatures = {}
for seed in (0, 1, 42, 123456, 987654321):
    grid = [[visual_biome(col, row, seed) for col in range(COLUMNS)] for row in range(ROWS)]
    counts = Counter(value for row in grid for value in row)
    assert sum(counts.values()) == COLUMNS * ROWS, "terrain grid does not cover all 266 cells"
    assert set(counts) == {0, 1, 2, 3}, f"seed {seed} does not show all four terrain regions: {counts}"
    assert min(counts.values()) >= 20, f"seed {seed} leaves a biome too small to read: {counts}"
    seed_signatures[seed] = tuple(value for row in grid for value in row)
assert seed_signatures[0] == tuple(visual_biome(c, r, 0) for r in range(ROWS) for c in range(COLUMNS)), "same seed should draw the same biome layout"
assert any(seed_signatures[0] != signature for seed, signature in seed_signatures.items() if seed != 0), "seed should be able to vary region boundaries"
print("PASS: 5 deterministic seed layouts cover all 266 cells with all four readable biome palettes")
print("STAGE 87 BIOME TERRAIN VISUAL REGRESSION PASSED: 9 source checks + 5 reference-grid scenarios")

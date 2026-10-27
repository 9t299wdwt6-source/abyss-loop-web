"""Stage 86 guards for deterministic seeded orthogonal road contours and legacy-save geometry.

This test independently stress-checks the contour construction rules and verifies that the
GDScript source wires one persisted geometry seed into drawing, placement and save validation.
It does not execute Godot; the matching engine smoke assertions remain in smoke_test.gd.
"""
from __future__ import annotations
from itertools import combinations
from pathlib import Path
import random
import sys

ROOT = Path(__file__).resolve().parents[1]
tile = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")

source_checks = {
    "seeded geometry API preserves exact fixed geometry for zero seed": 'static func get_road_grid_coordinates_for_seed(route_shape_id: String = "classic_ring", route_geometry_seed: int = 0)' in tile and 'if route_geometry_seed <= 0:' in tile and 'return get_road_grid_coordinates(route_shape_id)' in tile,
    "procedural contour uses four profile families and seed-derived variation modes": '"narrow_ring"' in tile and '"deep_descent"' in tile and '"fractured_loop"' in tile and 'var shape_mode := posmod(route_geometry_seed, 4)' in tile,
    "all procedural modes account for exactly 34 road cells via bounded detours": 'bump_depths = [1, 1]' in tile and 'bump_depths = [2]' in tile and 'bump_depths = [1]' in tile and 'bump_depths = [1, 1, 1]' in tile and 'const ROAD_CELL_COUNT := 34' in tile,
    "detours remove their midpoint to avoid a side-connected shortcut": 'skipped_midpoints[(bump_edge + 1) % base.size()] = true' in tile and 'if skipped_midpoints.has(edge_index):' in tile,
    "generated contours validate bounds, uniqueness, adjacency and accidental chords": 'static func is_valid_procedural_road_grid_coordinates(cells: Array[Vector2i]) -> bool:' in tile and 'if other_index == index + 1 or (index == 0 and other_index == cells.size() - 1):' in tile,
    "new runs persist a dedicated geometry seed": 'route_geometry_seed = floor_seed' in manager and '"route_geometry_seed": route_geometry_seed' in manager,
    "legacy saved runs without the geometry seed preserve fixed contours": 'snapshot.get("route_geometry_seed", 0)' in manager,
    "map drawing and hit testing query the shared TileSystem contour": 'TileSystemScript.get_road_grid_coordinates_for_seed(route_shape_id, route_geometry_seed)' in view,
    "build-grid contours appear only while a selected tile can be placed":
        'placement_enabled = allow_placement and not tile_id.is_empty()' in view and
        'placement_overlay_enabled = placement_enabled and placement_action_allowed' in view and
        'if placement_overlay_enabled and roadside_lookup.has(coord_id):' in view and
        'if placement_overlay_enabled:\\n\\t\\t\\t\\tdraw_rect(cell_rect, Color("#9bb59a", 0.10 + tone) if not high_contrast else Color("#e3f1dc", 0.36), false, 1.0)' in view and
        'var variation_strength := 0.018 if not placement_overlay_enabled else 0.055' in view and
        'var inset := maxf(2.0, cell_size * 0.08) if placement_overlay_enabled else 0.0' in view and
        'if cell_id == hovered_world_cell_id and placement_overlay_enabled:' in view,
    "map cache key changes when geometry seed changes": 'var signature_parts: Array[String] = [route_shape_id, str(route_geometry_seed)]' in view,
    "live placement validation uses the same seeded contour as the renderer": 'can_place_world(route_cells, world_tiles, cell_id, placement_probe, route_shape_id, route_geometry_seed)' in view and 'get_route_geometry_seed())' in manager,
    "placement forecast receives the same geometry seed": 'get_world_placement_preview(manager.route, manager.world_tiles, cell_id, selected_tile, manager.equipment, manager.get_route_shape_id(), manager.get_route_geometry_seed())' in ui,
    "save validator rejects modern field cells occupying this run's procedural road": 'get_road_grid_coordinates_for_seed(modern_route_shape, maxi(0, int(snapshot.get("route_geometry_seed", 0))))' in save,
    "engine smoke covers seed determinism, contour variation, bounds and legacy compatibility": 'is_valid_procedural_road_grid_coordinates(contour)' in smoke and 'shape_signatures.size() >= 8' in smoke and 'seed 0 must preserve legacy rectangular geometry' in smoke,
}
failed = [label for label, ok in source_checks.items() if not ok]
for label, ok in source_checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
if failed:
    print("STAGE 86 SOURCE REGRESSION FAILED: " + "; ".join(failed))
    sys.exit(1)

MAP_COLUMNS, MAP_ROWS, ROAD_CELL_COUNT = 19, 14, 34
FAMILIES = {
    "classic_ring": {0: (9, 6), 1: (9, 6), 2: (10, 6), 3: (8, 6)},
    "narrow_ring": {0: (7, 8), 1: (7, 8), 2: (7, 9), 3: (6, 8)},
    "deep_descent": {0: (8, 7), 1: (8, 7), 2: (8, 8), 3: (7, 7)},
    "fractured_loop": {0: (10, 5), 1: (10, 5), 2: (11, 5), 3: (9, 5)},
}
DEPTHS = {0: (1, 1), 1: (2,), 2: (1,), 3: (1, 1, 1)}
SALTS = {"classic_ring": 104729, "narrow_ring": 130363, "deep_descent": 155921, "fractured_loop": 196613}

def base_contour(left: int, top: int, horizontal_span: int, vertical_span: int) -> list[tuple[int, int]]:
    right, bottom = left + horizontal_span, top + vertical_span
    result = [(x, top) for x in range(left, right + 1)]
    result.extend((right, y) for y in range(top + 1, bottom + 1))
    result.extend((x, bottom) for x in range(right - 1, left - 1, -1))
    result.extend((left, y) for y in range(bottom - 1, top, -1))
    return result

def internal_edge(i: int, horizontal_span: int, vertical_span: int, size: int) -> bool:
    if 0 <= i < horizontal_span:
        offset = i
        return 2 <= offset <= horizontal_span - 3
    if horizontal_span <= i < horizontal_span + vertical_span:
        offset = i - horizontal_span
        return 2 <= offset <= vertical_span - 3
    bottom_start = horizontal_span + vertical_span
    if bottom_start <= i < bottom_start + horizontal_span:
        offset = i - bottom_start
        return 2 <= offset <= horizontal_span - 3
    left_start = 2 * horizontal_span + vertical_span
    if left_start <= i < size:
        offset = i - left_start
        return 2 <= offset <= vertical_span - 3
    return False

def bump_points(base: list[tuple[int, int]], edge: int, depth: int) -> list[tuple[int, int]]:
    point = base[edge]
    direction = (base[(edge + 1) % len(base)][0] - point[0], base[(edge + 1) % len(base)][1] - point[1])
    end_point = base[(edge + 2) % len(base)]
    outward = (direction[1], -direction[0])
    pts: list[tuple[int, int]] = []
    for step in range(1, depth + 1):
        pts.extend(((point[0] + outward[0] * step, point[1] + outward[1] * step),
                    (end_point[0] + outward[0] * step, end_point[1] + outward[1] * step)))
    pts.append((point[0] + direction[0] + outward[0] * depth,
                point[1] + direction[1] + outward[1] * depth))
    return pts

def fits_margin(base: list[tuple[int, int]], edge: int, depth: int) -> bool:
    return all(1 <= x < MAP_COLUMNS - 1 and 1 <= y < MAP_ROWS - 1 for x, y in bump_points(base, edge, depth))

def generate_reference(shape: str, seed: int) -> list[tuple[int, int]]:
    mode = seed % 4
    hspan, vspan = FAMILIES[shape][mode]
    depths = DEPTHS[mode]
    left = (MAP_COLUMNS - (hspan + 1)) // 2
    top = (MAP_ROWS - (vspan + 1)) // 2
    base = base_contour(left, top, hspan, vspan)
    rng = random.Random(seed ^ SALTS[shape])
    candidates = [i for i in range(len(base)) if internal_edge(i, hspan, vspan, len(base)) and fits_margin(base, i, depths[0])]
    selected: list[int] = []
    while candidates and len(selected) < len(depths):
        pick = rng.randrange(len(candidates))
        edge = candidates.pop(pick)
        if all(min(abs(edge - old), len(base) - abs(edge - old)) >= 4 for old in selected):
            selected.append(edge)
    if len(selected) != len(depths):
        raise AssertionError(f"could not place all contour detours: {shape=} {seed=} {selected=}")
    edge_depths = dict(zip(selected, depths))
    skipped = {(edge + 1) % len(base) for edge in selected}
    result: list[tuple[int, int]] = []
    for i, point in enumerate(base):
        if i in skipped:
            continue
        result.append(point)
        depth = edge_depths.get(i, 0)
        if not depth:
            continue
        direction = (base[(i + 1) % len(base)][0] - point[0], base[(i + 1) % len(base)][1] - point[1])
        end = base[(i + 2) % len(base)]
        outward = (direction[1], -direction[0])
        result.extend((point[0] + outward[0] * step, point[1] + outward[1] * step) for step in range(1, depth + 1))
        result.extend((point[0] + direction[0] * step + outward[0] * depth,
                       point[1] + direction[1] * step + outward[1] * depth) for step in range(1, 3))
        result.extend((end[0] + outward[0] * step, end[1] + outward[1] * step) for step in range(depth - 1, 0, -1))
    return result

def assert_valid(cells: list[tuple[int, int]]) -> None:
    assert len(cells) == ROAD_CELL_COUNT, f"wrong road cell count: {len(cells)}"
    assert len(set(cells)) == ROAD_CELL_COUNT, "contour repeats a coordinate"
    for i, point in enumerate(cells):
        assert 1 <= point[0] < MAP_COLUMNS - 1 and 1 <= point[1] < MAP_ROWS - 1, f"route has no 1-cell outer margin: {point}"
        nxt = cells[(i + 1) % ROAD_CELL_COUNT]
        assert abs(nxt[0] - point[0]) + abs(nxt[1] - point[1]) == 1, f"non-orthogonal/disconnected edge: {point}->{nxt}"
    for i, j in combinations(range(ROAD_CELL_COUNT), 2):
        a, b = cells[i], cells[j]
        if abs(a[0] - b[0]) + abs(a[1] - b[1]) == 1:
            assert j == i + 1 or (i == 0 and j == ROAD_CELL_COUNT - 1), f"non-consecutive road cells touch: {i}/{j}"

scenario_count = 0
unique_by_family: dict[str, set[tuple[tuple[int, int], ...]]] = {}
for family in FAMILIES:
    unique_by_family[family] = set()
    for seed in range(1, 513):
        cells = generate_reference(family, seed)
        assert_valid(cells)
        unique_by_family[family].add(tuple(cells))
        scenario_count += 1
    assert len(unique_by_family[family]) >= 30, f"too few contour variants for {family}: {len(unique_by_family[family])}"

# The same seed must give distinct shapes for the profile families and old geometry must remain unchanged at seed 0.
for seed in (1, 2, 3, 4, 42, 123456):
    assert len({tuple(generate_reference(family, seed)) for family in FAMILIES}) == 4, f"profile families should remain distinguishable at {seed=}"

legacy_profiles = {
    "classic_ring": (4, 3, 11, 8),
    "narrow_ring": (5, 2, 9, 10),
    "deep_descent": (4, 2, 10, 9),
    "fractured_loop": (3, 4, 13, 6),
}
for family, (left, top, width, height) in legacy_profiles.items():
    cells = base_contour(left, top, width - 1, height - 1)
    assert len(cells) == ROAD_CELL_COUNT and len(set(cells)) == ROAD_CELL_COUNT
print(f"PASS: {len(source_checks)} source guards")
print(f"PASS: {scenario_count} seeded contour scenarios across four route families")
print("PASS: every contour is a unique 34-cell orthogonal cycle with no extra road-to-road side connections and a one-cell margin")
print("PASS: each route family exposes many distinct deterministic variants; legacy fixed contours remain available for seed 0")
print(f"STAGE 86 PROCEDURAL CONTOUR REGRESSION: {len(source_checks) + 4}/{len(source_checks) + 4} PASS")
print("Scope: source and Python reference/numerical checks only; the GDScript runtime smoke is separate.")

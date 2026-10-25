"""Regression guards for distinct landscape placement. Static only."""
from pathlib import Path
import re
import sys
import math
ROOT = Path(__file__).resolve().parents[1]
tile = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
checks = {
    "separate 10x8 field and allowed cells exist": "WORLD_FIELD_COLUMNS := 10" in tile and "WORLD_FIELD_ROWS := 8" in tile and len(re.findall(r"\"\d+:\d+\"", tile)) >= 30,
    "placement validates cell and limits tiles per route sector": "func can_place_world" in tile and "MAX_WORLD_TILES_PER_ROUTE_SECTOR := 2" in tile,
    "field view has separate click/hover channels": "signal world_cell_clicked(cell_id: String)" in view and "signal world_cell_hovered(cell_id: String)" in view,
    "draw and hit test resolve same projected field geometry": "_field_cell_rect_from_geometry(cell_id, geometry)" in view and "world_display_cells" in view and "_find_world_cell" in view,
    "road segment takes hit-test priority over landscape cells": "_find_closest_cell(position) >= 0 or _is_near_route_line(position)" in view and "Geometry2D.get_closest_point_to_segment" in view,
    "route hit testing takes priority over landscape clicks": "_find_closest_cell(position) >= 0 or _is_near_route_line(position)" in view and "Geometry2D.get_closest_point_to_segment" in view,
    "landscape targets use square-map cells and remain inset": "tile_rect := cell_rect.grow(-inset)" in view and "Vector2.ONE * cell_size" in view,
    "runtime smoke covers route/field separation at multiple sizes": "road segments must never be treated as landscape placement cells" in (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8"),
    "route node clicks can place a selected card through the road-tile model": "func _on_route_cell_clicked" in ui and "manager.place_tile(selected_tile_hand_index, cell_index)" in ui,
    "road and field preview targets use separate placement calculators": "get_placement_preview(manager.route, manager.placed_tiles, cell_index, selected_tile, manager.equipment)" in ui and "get_world_placement_preview(manager.route, manager.world_tiles, cell_id, selected_tile, manager.equipment, manager.get_route_shape_id(), manager.get_route_geometry_seed())" in ui,
    "field placement spends hand card and saves snapshot": "func place_world_tile" in manager and "tile_hand.remove_at(hand_index)" in manager and "save_run_snapshot()" in manager,
    "field tiles apply on route sector visits": 'int(world_tile.get(\"route_index\", -1)) != index' in manager and "apply_tile_visit(world_tile" in manager,
    "adjacent field tiles have real gameplay synergy": "get_world_synergy_bonus" in tile and "ContentRegistry.TILE_SYNERGIES" in tile,
    "preview shows route sector before placement": "get_world_placement_preview" in tile and 'Localization.text("tile.forecast.world_sector")' in tile,
    "preview detects newly completed synergies from either placement order": "get_new_world_synergy_matches(world_tiles, simulated, cell_id)" in tile and "trigger_cell" in tile and "neighbor_cell" in tile,
    "snapshot field schema v3 validates legacy/map IDs, cell and route index": '"field_schema": 3' in manager and 'TileSystemScript.is_world_cell_valid(world_key)' in save and 'world_tile.get("route_index", -1)' in save,
    "official project version is 0.61.0": 'config/version="0.61.0"' in (ROOT / "project.godot").read_text(encoding="utf-8"),
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    print("WORLD FIELD REGRESSION FAILED: " + ", ".join(failed)); sys.exit(1)
# Numerical guard mirrors the current square-grid projection, not the retired ellipse.
# Persistent IDs remain 10x8, while the display map is 19x14 with an orthogonal road.
MAP_COLUMNS, MAP_ROWS = 19, 14
SHAPES = {
    "classic_ring": (4, 3, 11, 8),
    "narrow_ring": (5, 2, 9, 10),
    "deep_descent": (4, 2, 10, 9),
    "fractured_loop": (3, 4, 13, 6),
}

def road_cells(shape):
    x, y, w, h = SHAPES[shape]
    right, bottom = x + w - 1, y + h - 1
    out = []
    for col in range(x, right + 1): out.append((col, y))
    for row in range(y + 1, bottom + 1): out.append((right, row))
    for col in range(right - 1, x - 1, -1): out.append((col, bottom))
    for row in range(bottom - 1, y, -1): out.append((x, row))
    return out

def projected_world_cells(road, valid_keys):
    blocked, used, result = set(road), set(), {}
    for key in valid_keys:
        col, row = map(int, key.split(':'))
        preferred = ((col + 0.5) * MAP_COLUMNS / 10.0 - 0.5,
                     (row + 0.5) * MAP_ROWS / 8.0 - 0.5)
        best, best_cost = None, math.inf
        for y in range(MAP_ROWS):
            for x in range(MAP_COLUMNS):
                if (x, y) in blocked or (x, y) in used:
                    continue
                cost = (x - preferred[0]) ** 2 + (y - preferred[1]) ** 2 + ((y * MAP_COLUMNS + x) % 7) * 0.0001
                if cost < best_cost:
                    best, best_cost = (x, y), cost
        if best is not None:
            result[key] = best
            used.add(best)
    return result

valid_keys = re.findall(r'"(\d+:\d+)"', tile.split("const MAX_WORLD_TILES_PER_ROUTE_SECTOR")[0])
scenarios = 0
for width, height in ((300,350),(620,420),(900,600),(1280,720),(1440,900),(1920,1080)):
    cell_size = min((width - 28.0) / MAP_COLUMNS, (height - 64.0) / MAP_ROWS)
    map_width, map_height = MAP_COLUMNS * cell_size, MAP_ROWS * cell_size
    left, top = (width - map_width) / 2.0, (height - map_height) / 2.0
    assert cell_size > 0 and abs(map_width / MAP_COLUMNS - map_height / MAP_ROWS) < 1e-7
    for shape in SHAPES:
        road = road_cells(shape)
        assert len(road) == 34 and len(set(road)) == 34
        for i, (x, y) in enumerate(road):
            nx, ny = road[(i + 1) % len(road)]
            assert abs(nx - x) + abs(ny - y) == 1, f"{shape}: road is not orthogonally closed at {i}"
        mapping = projected_world_cells(road, valid_keys)
        assert len(mapping) == len(valid_keys) and len(set(mapping.values())) == len(mapping)
        assert not (set(mapping.values()) & set(road)), f"{shape}: landscape target projects onto road"
        for x, y in mapping.values():
            cx, cy = left + (x + 0.5) * cell_size, top + (y + 0.5) * cell_size
            assert left < cx < left + map_width and top < cy < top + map_height
        scenarios += 1
assert "const MAP_COLUMNS := 19" in view and "const MAP_ROWS := 14" in view
assert "const ROAD_CELL_COUNT := 34" in view
assert "func _get_road_grid_coordinates() -> Array[Vector2i]:" in view
print(f"PASS: legacy world keys project to unique off-road grid cells across {scenarios} viewport/profile cases")
print(f"WORLD FIELD REGRESSION PASSED: {len(checks) + 1} source checks plus square-grid numerical geometry. Runtime requires Godot.")

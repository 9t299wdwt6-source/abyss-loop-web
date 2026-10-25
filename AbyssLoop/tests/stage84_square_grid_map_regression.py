"""Stage 84 map geometry guard: square cells, orthogonal loop, scalable terrain map."""
from __future__ import annotations
from pathlib import Path
import math
import re
import sys
ROOT = Path(__file__).resolve().parents[1]
view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
tile = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks: dict[str, bool] = {
    "19x14 tactical display grid is explicit": "const MAP_COLUMNS := 19" in view and "const MAP_ROWS := 14" in view,
    "new expeditions use a 34-cell route": '"route_cells": 34' in registry and "const ROAD_CELL_COUNT := 34" in view,
    "the display cell derives from both available dimensions": "minf(usable.x / float(MAP_COLUMNS), usable.y / float(MAP_ROWS))" in view,
    "road geometry is centralised in TileSystem and keyed by the persisted seed": "func _get_road_grid_coordinates() -> Array[Vector2i]:" in view and "TileSystemScript.get_road_grid_coordinates_for_seed(route_shape_id, route_geometry_seed)" in view and "get_road_grid_coordinates_for_seed(route_shape_id, route_geometry_seed)" in tile,
    "terrain grid and road tiles use full square cells": "func _draw_map_grid(route_geometry: Dictionary)" in view and "func _draw_road_tiles(route_geometry: Dictionary)" in view and "Vector2.ONE * cell_size" in view,
    "world-field IDs retain the old 10x8 save schema": "const FIELD_COLUMNS := 10" in view and "const FIELD_ROWS := 8" in view and "const WORLD_FIELD_COLUMNS := 10" in tile and "const WORLD_FIELD_ROWS := 8" in tile,
    "all 80 logical landscape cells are now placeable": len(re.findall(r'"\d+:\d+"', tile.split("const MAX_WORLD_TILES_PER_ROUTE_SECTOR")[0])) == 80,
    "legacy landscape keys remain in the same stable list order": re.findall(r'"(\d+:\d+)"', tile.split("const MAX_WORLD_TILES_PER_ROUTE_SECTOR")[0])[:33] == ["0:0", "1:0", "2:0", "7:0", "8:0", "9:0", "0:1", "9:1", "0:2", "4:2", "5:2", "3:3", "4:3", "5:3", "6:3", "2:4", "3:4", "4:4", "5:4", "6:4", "7:4", "3:5", "4:5", "5:5", "6:5", "0:6", "9:6", "0:7", "1:7", "2:7", "7:7", "8:7", "9:7"],
    "landscape projection avoids occupied road cells": "func _get_world_display_cell_map(road_cells: Array) -> Dictionary" in view and "if blocked.has(candidate_id) or used.has(candidate_id):" in view,
    "route and landscape hit testing share road geometry": "var slot := road_cells.find(coord)" in view and "_find_closest_cell(position) >= 0 or _is_near_route_line(position)" in view,
    "old route snapshots still sample the new physical road": "float(i) * float(road_cells.size()) / float(count)" in view and "func _get_hero_grid_position(progress: float, geometry: Dictionary) -> Vector2" in view,
    "mobile and desktop canvases retain explicit minimum dimensions": "Vector2(300, 350) if compact else Vector2(620, 420)" in view,
    "the runtime smoke test states legacy route compatibility": "legacy 18-node route geometry remains loadable" in smoke,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    print("STAGE 84 MAP REGRESSION FAILED: " + ", ".join(failed))
    sys.exit(1)

profiles = {
    "classic_ring": (4, 3, 11, 8),
    "narrow_ring": (5, 2, 9, 10),
    "deep_descent": (4, 2, 10, 9),
    "fractured_loop": (3, 4, 13, 6),
}
def perimeter(profile: tuple[int, int, int, int]) -> list[tuple[int, int]]:
    x, y, w, h = profile
    right, bottom = x + w - 1, y + h - 1
    points: list[tuple[int, int]] = []
    points.extend((col, y) for col in range(x, right + 1))
    points.extend((right, row) for row in range(y + 1, bottom + 1))
    points.extend((col, bottom) for col in range(right - 1, x - 1, -1))
    points.extend((x, row) for row in range(bottom - 1, y, -1))
    return points
scenarios = 0
minimum_cell, maximum_cell = math.inf, 0.0
for width, height in ((300, 350), (620, 420), (900, 600), (1280, 720), (1440, 900), (1920, 1080)):
    cell = min((width - 28.0) / 19.0, (height - 64.0) / 14.0)
    minimum_cell, maximum_cell = min(minimum_cell, cell), max(maximum_cell, cell)
    map_w, map_h = cell * 19, cell * 14
    assert math.isclose(map_w / 19.0, map_h / 14.0, abs_tol=1e-9)
    assert map_w <= width - 27.999 and map_h <= height - 63.999
    for name, profile in profiles.items():
        cells = perimeter(profile)
        assert len(cells) == 34, f"{name}: expected 34 road cells, got {len(cells)}"
        assert len(set(cells)) == 34, f"{name}: repeated grid coordinate"
        assert all(0 <= x < 19 and 0 <= y < 14 for x, y in cells), f"{name}: off-board road cell"
        for i, (x, y) in enumerate(cells):
            nx, ny = cells[(i + 1) % len(cells)]
            assert abs(nx - x) + abs(ny - y) == 1, f"{name}: diagonal or disconnected road edge {i}"
        scenarios += 1
assert profiles["classic_ring"] == (4, 3, 11, 8)
assert len(perimeter(profiles["classic_ring"])) == 34
print(f"PASS: {scenarios} closed orthogonal road profiles across four layouts")
print(f"PASS: square-cell size adapts from {minimum_cell:.2f}px to {maximum_cell:.2f}px across six viewports")
print(f"STAGE 84 SQUARE-GRID MAP REGRESSION: {len(checks) + 2}/{len(checks) + 2} PASS")
print("Source/numerical only; Godot rendering and input still require in-engine acceptance.")

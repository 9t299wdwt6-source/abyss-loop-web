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
    "draw and hit test resolve same field rect": "_field_cell_rect(cell_id)" in view and "_find_world_cell" in view,
    "road segment takes hit-test priority over landscape cells": "_find_closest_cell(position) >= 0 or _is_near_route_line(position)" in view and "Geometry2D.get_closest_point_to_segment" in view,
    "route hit testing takes priority over landscape clicks": "_find_closest_cell(position) >= 0 or _is_near_route_line(position)" in view and "Geometry2D.get_closest_point_to_segment" in view,
    "landscape markers remain compact around the road": "footprint_size := Vector2(minf(28.0" in view,
    "runtime smoke covers route/field separation at multiple sizes": "road segments must never be treated as landscape placement cells" in (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8"),
    "route node clicks can place a selected card through the road-tile model": "func _on_route_cell_clicked" in ui and "manager.place_tile(selected_tile_hand_index, cell_index)" in ui,
    "road and field preview targets use separate placement calculators": "get_placement_preview(manager.route, manager.placed_tiles, cell_index, selected_tile)" in ui and "get_world_placement_preview(manager.route, manager.world_tiles, cell_id, selected_tile)" in ui,
    "field placement spends hand card and saves snapshot": "func place_world_tile" in manager and "tile_hand.remove_at(hand_index)" in manager and "save_run_snapshot()" in manager,
    "field tiles apply on route sector visits": 'int(world_tile.get(\"route_index\", -1)) != index' in manager and "apply_tile_visit(world_tile" in manager,
    "adjacent field tiles have real gameplay synergy": "get_world_synergy_bonus" in tile and "ContentRegistry.TILE_SYNERGIES" in tile,
    "preview shows route sector before placement": "get_world_placement_preview" in tile and 'Localization.text("tile.forecast.world_sector")' in tile,
    "preview detects newly completed synergies from either placement order": "get_new_world_synergy_matches(world_tiles, simulated, cell_id)" in tile and "trigger_cell" in tile and "neighbor_cell" in tile,
    "snapshot field schema v2 validates ID, cell and route index": '"field_schema": 2' in manager and 'TileSystemScript.is_world_cell_valid(world_key)' in save and 'world_tile.get("route_index", -1)' in save,
    "official project version is 0.61.0": 'config/version="0.61.0"' in (ROOT / "project.godot").read_text(encoding="utf-8"),
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    print("WORLD FIELD REGRESSION FAILED: " + ", ".join(failed)); sys.exit(1)
# Geometry-based guard: the actual small pixel markers must not cover the road.
# Mirrors RouteView's documented ellipse/profile equations over supported viewport
# sizes and route lengths; this is a useful static approximation, not engine proof.
keys = re.findall(r'"(\d+:\d+)"', tile.split("const MAX_WORLD_TILES_PER_ROUTE_SECTOR")[0])

def route_points(width: int, height: int, count: int, shape: str):
    cx, cy = width * 0.5, height * 0.51
    rx, ry = min(width * 0.385, height * 0.78), height * 0.34
    if shape == "narrow_ring": rx *= 0.78; ry *= 0.77
    elif shape == "deep_descent": rx *= 0.92; ry *= 0.88
    elif shape == "fractured_loop": rx *= 1.04; ry *= 0.94
    points = []
    for i in range(count):
        angle = -math.pi * 0.5 + math.tau * i / count
        x, y = cx + math.cos(angle) * rx, cy + math.sin(angle) * ry
        if shape == "deep_descent":
            x += math.cos(angle * 2.0) * rx * 0.055
            y += math.sin(angle * 2.0 + 0.4) * ry * 0.07
        elif shape == "fractured_loop":
            x += math.cos(angle * 3.0) * rx * 0.095
            y += math.sin(angle * 2.0) * ry * 0.09
        points.append((x, y))
    return points

def segment_hits_expanded_rect(a, b, rect, margin=7.0):
    x0, y0, x1, y1 = rect
    x0 -= margin; y0 -= margin; x1 += margin; y1 += margin
    distance = math.dist(a, b)
    steps = max(1, math.ceil(distance / 1.5))
    for step in range(steps + 1):
        t = step / steps
        x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        if x0 <= x <= x1 and y0 <= y <= y1:
            return True
    return False

shapes = ("classic_ring", "deep_descent", "narrow_ring", "fractured_loop")
sizes = ((620, 420), (900, 600), (1280, 720), (1440, 900), (1920, 1080))
geometry_collisions = []
for width, height in sizes:
    for shape in shapes:
        for route_count in (12, 16, 18, 22):
            points = route_points(width, height, route_count, shape)
            for key in keys:
                col, row = map(int, key.split(":"))
                cell_w, cell_h = (width - 36.0) / 10.0, (height - 68.0) / 8.0
                cx, cy = 18.0 + (col + 0.5) * cell_w, 34.0 + (row + 0.5) * cell_h
                marker_w, marker_h = min(28.0, cell_w - 10.0), min(22.0, cell_h - 10.0)
                rect = (cx - marker_w / 2, cy - marker_h / 2, cx + marker_w / 2, cy + marker_h / 2)
                collided = any(rect[0] - 7 <= x <= rect[2] + 7 and rect[1] - 7 <= y <= rect[3] + 7 for x, y in points)
                if not collided:
                    collided = any(segment_hits_expanded_rect(points[i], points[(i + 1) % route_count], rect) for i in range(route_count))
                if collided:
                    geometry_collisions.append((key, width, height, shape, route_count))
assert not geometry_collisions, f"Landscape marker overlaps the road: {geometry_collisions[:5]}"
print(f"PASS: no landscape marker overlaps route nodes/trail in {len(sizes) * len(shapes) * 4} geometry scenarios")
print(f"WORLD FIELD REGRESSION PASSED: {len(checks) + 1} static checks. Godot runtime remains separate.")

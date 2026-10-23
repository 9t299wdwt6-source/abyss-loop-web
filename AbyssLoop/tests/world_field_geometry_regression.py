"""Numerical geometry regression for the separate landscape field. No Godot runtime implied."""
from __future__ import annotations
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
TILE = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
CELLS = [
    "0:0", "1:0", "2:0", "7:0", "8:0", "9:0", "0:1", "9:1",
    "0:2", "4:2", "5:2", "3:3", "4:3", "5:3", "6:3", "2:4",
    "3:4", "4:4", "5:4", "6:4", "7:4", "3:5", "4:5", "5:5",
    "6:5", "0:6", "9:6", "0:7", "1:7", "2:7", "7:7", "8:7", "9:7",
]
SIZES = [(620, 420), (900, 600), (1280, 720), (1440, 900), (1920, 1080)]
SHAPES = ("classic_ring", "deep_descent", "narrow_ring", "fractured_loop")

def route_points(width: float, height: float, shape: str, count: int = 18):
    center = (width * 0.5, height * 0.51)
    rx, ry = min(width * 0.385, height * 0.78), height * 0.34
    if shape == "narrow_ring":
        rx, ry = rx * 0.78, ry * 0.77
    elif shape == "deep_descent":
        rx, ry = rx * 0.92, ry * 0.88
    elif shape == "fractured_loop":
        rx, ry = rx * 1.04, ry * 0.94
    result = []
    for i in range(count):
        angle = -math.pi / 2 + math.tau * i / count
        x = center[0] + math.cos(angle) * rx
        y = center[1] + math.sin(angle) * ry
        if shape == "deep_descent":
            x += math.cos(angle * 2) * rx * 0.055
            y += math.sin(angle * 2 + 0.4) * ry * 0.07
        elif shape == "fractured_loop":
            x += math.cos(angle * 3) * rx * 0.095
            y += math.sin(angle * 2) * ry * 0.09
        result.append((x, y))
    return result

def distance_to_segment(point, start, end):
    vx, vy = end[0] - start[0], end[1] - start[1]
    denom = vx * vx + vy * vy
    t = 0.0 if denom <= 1e-9 else max(0.0, min(1.0, ((point[0] - start[0]) * vx + (point[1] - start[1]) * vy) / denom))
    return math.hypot(point[0] - (start[0] + vx * t), point[1] - (start[1] + vy * t))

checks = 0
min_path_clearance = float("inf")
for width, height in SIZES:
    field_x, field_y = 18.0, 34.0
    field_width, field_height = width - 36.0, height - 68.0
    for shape in SHAPES:
        points = route_points(width, height, shape)
        for cell in CELLS:
            col, row = map(int, cell.split(":"))
            center = (field_x + (col + 0.5) * field_width / 10.0, field_y + (row + 0.5) * field_height / 8.0)
            clearance = min(distance_to_segment(center, points[i], points[(i + 1) % len(points)]) for i in range(len(points)))
            min_path_clearance = min(min_path_clearance, clearance)
            # _find_closest_cell uses 27 px; the visible trail extends at most 7.5 px.
            assert clearance > 27.0, f"field cell center conflicts with route selection: {width}x{height} {shape} {cell}: {clearance:.2f}px"
            assert clearance > math.hypot(14.0, 11.0) + 7.5, f"compact landscape badge overlaps route trail: {width}x{height} {shape} {cell}: {clearance:.2f}px"
            checks += 1

assert "_find_closest_cell(position) >= 0 or _is_near_route_line(position)" in VIEW
assert "Geometry2D.get_closest_point_to_segment" in VIEW
assert "footprint_size := Vector2(minf(28.0" in VIEW
assert "WORLD_FIELD_COLUMNS := 10" in TILE and "WORLD_FIELD_ROWS := 8" in TILE
print(f"WORLD FIELD GEOMETRY REGRESSION PASSED: {checks} center/route clearance cases across {len(SIZES)} viewport sizes and {len(SHAPES)} route profiles.")
print(f"Minimum tested center-to-route clearance: {min_path_clearance:.2f}px.")
print("This numerical model is an offline guard; final pixels and input must still be inspected in Godot.")

"""Offline geometry screening for route self-crossing and crowded hit areas."""
from pathlib import Path
import math
import re

ROOT = Path(__file__).resolve().parents[1]
VIEW = ROOT / "scripts/ui/route_view.gd"
SMOKE = ROOT / "tests/smoke_test.gd"
source = VIEW.read_text(encoding="utf-8")
smoke = SMOKE.read_text(encoding="utf-8")
assert "func _route_marker_size() -> float:" in source
assert "func _route_hit_radius() -> float:" in source
assert "return closest_index if closest_distance <= _route_hit_radius() else -1" in source
assert "Geometry2D.segment_intersects_segment" in smoke
assert "stress_route_counts" in smoke

SHAPES = ("classic_ring", "deep_descent", "narrow_ring", "fractured_loop")
SIZES = ((620, 420), (900, 600), (1280, 720), (1440, 900), (1920, 1080))
COUNTS = (12, 14, 16, 18, 20, 22)

def route_points(width: int, height: int, count: int, shape: str):
    center_x, center_y = width * 0.5, height * 0.51
    radius_x, radius_y = min(width * 0.385, height * 0.78), height * 0.34
    if shape == "narrow_ring":
        radius_x *= 0.78; radius_y *= 0.77
    elif shape == "deep_descent":
        radius_x *= 0.92; radius_y *= 0.88
    elif shape == "fractured_loop":
        radius_x *= 1.04; radius_y *= 0.94
    points = []
    for i in range(count):
        angle = -math.pi * 0.5 + math.tau * i / count
        x, y = center_x + math.cos(angle) * radius_x, center_y + math.sin(angle) * radius_y
        if shape == "deep_descent":
            x += math.cos(angle * 2.0) * radius_x * 0.055
            y += math.sin(angle * 2.0 + 0.4) * radius_y * 0.07
        elif shape == "fractured_loop":
            x += math.cos(angle * 3.0) * radius_x * 0.095
            y += math.sin(angle * 2.0) * radius_y * 0.09
        points.append((x, y))
    return points

def proper_intersection(a, b, c, d):
    def orient(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
    o1, o2, o3, o4 = orient(a, b, c), orient(a, b, d), orient(c, d, a), orient(c, d, b)
    return o1 * o2 < -1e-6 and o3 * o4 < -1e-6

scenarios = 0
min_clearance = float("inf")
for width, height in SIZES:
    for shape in SHAPES:
        for count in COUNTS:
            points = route_points(width, height, count, shape)
            marker_size = max(22.0, min(30.0, 30.0 - max(0, count - 16) * 1.2))
            hit_radius = marker_size * 0.5 + 3.0
            # All route nodes should be safely separated enough that hit areas do not overlap.
            for i in range(count):
                distance = math.dist(points[i], points[(i + 1) % count])
                min_clearance = min(min_clearance, distance - 2 * hit_radius)
                assert distance > 2 * hit_radius, f"overlapping route hits: {width}x{height} {shape} n={count} segment={i} distance={distance:.2f} required>{2*hit_radius:.2f}"
                # Every point must retain room for its marker and remain on the visible map.
                x, y = points[i]
                assert marker_size / 2 + 1 < x < width - marker_size / 2 - 1, f"route point clips horizontally: {shape} n={count}"
                assert marker_size / 2 + 1 < y < height - marker_size / 2 - 1, f"route point clips vertically: {shape} n={count}"
            # The polygon may join sequential edges, but non-adjacent segments must not cross.
            for i in range(count):
                a, b = points[i], points[(i + 1) % count]
                for j in range(i + 1, count):
                    if j == i or j == (i + 1) % count or (j + 1) % count == i:
                        continue
                    c, d = points[j], points[(j + 1) % count]
                    assert not proper_intersection(a, b, c, d), f"self-intersection: {width}x{height} {shape} n={count} segments={i}/{j}"
            scenarios += 1
print(f"ROUTE TOPOLOGY STRESS REGRESSION PASSED: {scenarios} geometry scenarios across viewport sizes, profiles and node counts.")
print(f"Minimum gap between neighboring hit areas: {min_clearance:.2f}px. This remains a numerical model; Godot runtime is separate.")

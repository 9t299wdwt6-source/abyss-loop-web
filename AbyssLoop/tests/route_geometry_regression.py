"""Guard against route drawing and pointer hit-testing drifting apart."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
route_view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")

start_draw = route_view.index("func _draw() -> void:")
end_draw = route_view.index("func _draw_route_chevron", start_draw)
draw_body = route_view[start_draw:end_draw]
start_hit = route_view.index("func _find_closest_cell(position: Vector2) -> int:")
end_hit = route_view.index("func _draw_pixel_symbol", start_hit)
hit_body = route_view[start_hit:end_hit]
helper_start = route_view.index("func _get_route_geometry() -> Dictionary:")
helper_end = route_view.index("func _find_closest_cell", helper_start)
helper = route_view[helper_start:helper_end]

assert "_get_route_geometry()" in draw_body, "route drawing must use shared geometry"
assert "_get_route_geometry()" in hit_body, "mouse hit-testing must use shared geometry"
assert "_route_marker_size()" in draw_body, "node marker size must adapt to dense routes"
assert "_route_hit_radius()" in hit_body, "click target radius must match adaptive node size"
assert "var angle := -PI * 0.5 + TAU * float(i) / float(count)" in helper, "shared helper must generate periodic route nodes"
for shape in ["classic_ring", "narrow_ring", "deep_descent", "fractured_loop"]:
    assert f'"{shape}"' in route_view, f"route profile is missing: {shape}"
assert "route_shape_id == \"deep_descent\"" in helper, "deep descent must affect both drawing and hit-testing"
assert "route_shape_id == \"fractured_loop\"" in helper, "fractured loop must affect both drawing and hit-testing"
assert "var angle := -PI * 0.5 + TAU * float(i) / float(count)" not in hit_body, "hit-testing must not maintain a duplicate geometry formula"
assert "var radius_x := minf(size.x * 0.385, size.y * 0.78)" not in hit_body, "hit-testing must not independently calculate ellipse bounds"
for token in ["RouteViewScript.new()", "Vector2(620, 420)", "Vector2(900, 600)", "Vector2(1280, 720)", "route_view._find_closest_cell(point) == point_index", "stress_route_counts", "Geometry2D.segment_intersects_segment", "route_view._route_hit_radius()"]:
    assert token in smoke, f"Godot runtime smoke test misses route geometry scenario: {token}"
print("ROUTE GEOMETRY REGRESSION PASSED: shared drawing/input geometry, adaptive markers, dense-route stress tests")
print("NOTE: source guard passed; the corresponding GDScript smoke test still requires Godot runtime execution.")

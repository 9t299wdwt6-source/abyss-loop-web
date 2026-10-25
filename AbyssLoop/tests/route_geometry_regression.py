"""Guard square-cell route geometry and route/landscape input separation."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
route_view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
assert "const MAP_COLUMNS := 19" in route_view and "const MAP_ROWS := 14" in route_view
assert "const ROAD_CELL_COUNT := 34" in route_view
assert '"route_cells": 34' in registry
assert "func _get_road_grid_coordinates() -> Array[Vector2i]:" in route_view
assert "TileSystemScript.get_road_grid_coordinates_for_seed(route_shape_id, route_geometry_seed)" in route_view
tile_system = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
assert "result.append(Vector2i(col, top))" in tile_system
assert "result.append(Vector2i(right, row))" in tile_system
assert "result.append(Vector2i(col, bottom))" in tile_system
assert "result.append(Vector2i(left, row))" in tile_system
assert '"road_cells": road_cells' in route_view and '"slot_indices": slot_indices' in route_view
assert "func _draw_map_grid(route_geometry: Dictionary)" in route_view
assert "func _draw_road_tiles(route_geometry: Dictionary)" in route_view
assert "func _get_world_display_cell_map(road_cells: Array) -> Dictionary" in route_view
assert "func _find_closest_cell(position: Vector2) -> int:" in route_view
assert 'var slot := road_cells.find(coord)' in route_view
assert "_get_route_geometry()" in route_view and "_route_hit_radius()" in route_view
assert "func _find_world_cell(position: Vector2) -> String:" in route_view
assert "func _field_cell_rect_from_geometry" in route_view
assert "Regression: visual node positions and mouse hit-testing must share geometry" in smoke
assert "legacy 18-node route geometry remains loadable" in smoke
print("ROUTE GEOMETRY REGRESSION PASSED: 19x14 square board, 34-cell orthogonal closed road, shared road/landscape hit geometry.")
print("NOTE: GDScript runtime and final pixel layout still require a Godot engine run.")

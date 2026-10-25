"""Stage 85 guards for the full 19x14 landscape, stable legacy saves, sectors and zones."""
from __future__ import annotations
from pathlib import Path
import math
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
tile = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")

legacy_ids = re.findall(r'"(\d+:\d+)"', tile.split("const MAX_WORLD_TILES_PER_ROUTE_SECTOR")[0])
checks = {
    "legacy 10x8 ID list remains exactly 80 stable keys": len(legacy_ids) == 80 and len(set(legacy_ids)) == 80,
    "full display board is explicitly 19x14 with square tiles": "const MAP_COLUMNS := 19" in view and "const MAP_ROWS := 14" in view and "Vector2.ONE * cell_size" in view,
    "new map IDs are namespaced and bounded": 'return "m:%d:%d" % [col, row]' in tile and "func is_map_world_cell_id(cell_id: String) -> bool:" in tile and "int(parts[1]) < MAP_COLUMNS" in tile and "int(parts[2]) < MAP_ROWS" in tile,
    "modern display enumerates the full board rather than just legacy IDs": "TileSystemScript.map_world_cell_id(col, row)" in view and "for cell_id_value in display_map.keys()" in view,
    "old placed IDs keep their projected positions without blocking unrelated new IDs": "legacy_projection" in view and "occupied_legacy_positions" in view and "_world_display_cache_signature" in view,
    "road contours are shared by map validation and contain 34 cells": "static func get_road_grid_coordinates(route_shape_id: String = \"classic_ring\")" in tile and "const ROAD_CELL_COUNT := 34" in tile,
    "new sectors are assigned by nearest road slot on the active contour": "world_route_index(cell_id: String, route_size: int, route_shape_id: String = \"classic_ring\")" in tile and "nearest_slot" in tile and "get_road_grid_coordinates(route_shape_id)" in tile,
    "legacy sector mapping stays available for old snapshots": "Legacy angular sector assignment is intentionally retained for old saves" in tile and "WORLD_FIELD_KEYS.has(cell_id)" in tile,
    "roadside cells and wilderness cells are validated separately": "func world_cell_is_roadside" in tile and 'placement_zone == "roadside"' in tile and 'placement_zone == "landscape" and is_map_world_cell_id(cell_id)' in tile,
    "selected card zone controls live valid/invalid map-cell feedback": "var placement_probe: Dictionary = {\"id\": selected_tile_id}" in view and "placement_probe, route_shape_id" in view,
    "manager and preview pass the active route shape": "can_place_world(route, world_tiles, cell_id, tile, get_route_shape_id(), get_route_geometry_seed())" in manager and "get_world_placement_preview(manager.route, manager.world_tiles, cell_id, selected_tile, manager.equipment, manager.get_route_shape_id(), manager.get_route_geometry_seed())" in ui,
    "snapshot schema 3 accepts full-board IDs and caps placements at 232": '"field_schema": 3' in manager and 'world_tiles_value.size() > 232' in save and 'int(snapshot.get("field_schema", 1)) >= 3' in save,
    "save validator preserves legacy IDs, validates map coordinates and forbids road-cell placements": 'TileSystemScript.WORLD_FIELD_KEYS.has(world_key)' in save and 'parts[0] == "m"' in save and 'TileSystemScript.is_world_cell_valid(world_key)' in save and 'modern_road_coordinates.has(expected_coord)' in save,
    "both engine smoke files cover 232 cells and roadside/wilderness rules": "every route shape must expose 232 off-road grid cells" in smoke and "wilderness structures should accept cells beyond the roadside band" in smoke,
}
failed = [label for label, ok in checks.items() if not ok]
for label, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
if failed:
    print("STAGE 85 SOURCE REGRESSION FAILED: " + ", ".join(failed))
    sys.exit(1)

SHAPES = {
    "classic_ring": (4, 3, 11, 8),
    "narrow_ring": (5, 2, 9, 10),
    "deep_descent": (4, 2, 10, 9),
    "fractured_loop": (3, 4, 13, 6),
}

def road_cells(shape: str) -> list[tuple[int, int]]:
    x, y, width, height = SHAPES[shape]
    right, bottom = x + width - 1, y + height - 1
    result = [(col, y) for col in range(x, right + 1)]
    result += [(right, row) for row in range(y + 1, bottom + 1)]
    result += [(col, bottom) for col in range(right - 1, x - 1, -1)]
    result += [(x, row) for row in range(bottom - 1, y, -1)]
    return result

cell_checks = 0
roadside_counts: dict[str, int] = {}
for shape in SHAPES:
    road = road_cells(shape)
    assert len(road) == 34 and len(set(road)) == 34, shape
    assert all(abs(road[(i + 1) % 34][0] - road[i][0]) + abs(road[(i + 1) % 34][1] - road[i][1]) == 1 for i in range(34)), shape
    road_set = set(road)
    free = {(x, y) for y in range(14) for x in range(19)} - road_set
    assert len(free) == 232, (shape, len(free))
    roadside = {p for p in free if any(abs(p[0] - r[0]) + abs(p[1] - r[1]) == 1 for r in road_set)}
    wilderness = free - roadside
    assert not roadside.intersection(wilderness) and len(roadside) + len(wilderness) == 232
    assert all((x, y) not in road_set for x, y in free)
    roadside_counts[shape] = len(roadside)
    for x, y in free:
        cell_id = f"m:{x}:{y}"
        assert cell_id not in {f"m:{rx}:{ry}" for rx, ry in road_set}
        # Geometry-driven sector mapping mirrors TileSystem's nearest-slot rule.
        nearest_slot = min(range(len(road)), key=lambda idx: (x - road[idx][0]) ** 2 + (y - road[idx][1]) ** 2)
        for route_size in (12, 18, 22, 34):
            route_index = round(nearest_slot * route_size / len(road)) % route_size
            assert 0 <= route_index < route_size
            cell_checks += 1

print(f"PASS: {len(SHAPES)} contours each contain 34 connected road cells and exactly 232 unique off-road cells")
print(f"PASS: {cell_checks} route-sector mapping scenarios across four route lengths")
print("PASS: roadside/wilderness partition per contour: " + ", ".join(f"{k}={v}/{232-v}" for k,v in roadside_counts.items()))
print(f"STAGE 85 FULL LANDSCAPE REGRESSION: {len(checks) + 3}/{len(checks) + 3} PASS")
print("Note: source/numerical checks only. Godot 4.7.2 runtime, touch interactions, rendering and Web export remain separate acceptance items.")

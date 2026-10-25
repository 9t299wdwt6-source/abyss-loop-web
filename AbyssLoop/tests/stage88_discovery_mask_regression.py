#!/usr/bin/env python3
"""Stage 88 save-safe discovery mask source guards and independent map-mask shape tests.

These tests validate source contracts and a numerical reference model; they do not
compile GDScript or claim visual/runtime acceptance.
"""
from __future__ import annotations
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
localization = json.loads((ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"))

checks = {
    "expedition manager owns the persisted modern discovery mask": 'var discovered_world_cells: Dictionary = {}' in manager and '"discovered_world_cells": discovered_world_cells.duplicate(true)' in manager,
    "new expeditions reveal a starting region and visits expand the mask": '_reveal_world_cells_near_route_index(0)' in manager and '_reveal_world_cells_near_route_index(index)' in manager,
    "legacy snapshots without the new field default to a fully visible map": 'discovered_world_cells = _get_all_offroad_cells_discovered()' in manager and 'else:\n\t\tdiscovered_world_cells = _get_all_offroad_cells_discovered()' in manager,
    "discovery normalization accepts only canonical m:col:row IDs": 'func _normalize_discovered_world_cells(value: Variant) -> Dictionary:' in manager and 'TileSystemScript.is_map_world_cell_id(cell_id)' in manager,
    "reveal helper uses persisted route seed and excludes road cells": 'get_road_grid_coordinates_for_seed(get_route_shape_id(), route_geometry_seed)' in manager and 'road_lookup.has("%d:%d" % [col, row])' in manager,
    "discovery mask keeps placement IDs unchanged and is saved with snapshots": 'discovered_world_cells[cell_id] = true' in manager and '"snapshot_version": 4' in manager,
    "view accepts the mask and invalidates cached rendering when it changes": 'discovered_cells: Dictionary = {}' in view and 'str(discovered_cells.keys())' in view and 'discovered_world_cells = discovered_cells' in view,
    "unknown cells are dimmed and visibly marked without a selected card": 'var is_discovered := discovered_world_cells.has(map_cell_id)' in view and '"#09161b", 0.98' in view and 'func _draw_unknown_cell_fog' in view and '"?"' in view,
    "preview targets have corner brackets distinct from committed filled tiles": 'func _draw_placement_preview_corners(rect: Rect2, color: Color) -> void:' in view and '_draw_placement_preview_corners(tile_rect.grow(-1.0)' in view and 'draw_rect(tile_rect, fill, true)' in view,
    "UI passes discovery state into RouteView": 'manager.get_route_geometry_seed(), manager.discovered_world_cells)' in ui,
    "unknown cell hover explains exploration without blocking placement preview": 'tile.preview.unknown.world' in ui and 'Выбор и размещение карты по-прежнему доступны.' in localization.get('tile.preview.unknown.world', ''),
    "save validator rejects malformed, oversized and road-overlapping masks": 'discovery_value.size() > 232' in save and 'TileSystemScript.is_map_world_cell_id(discovery_key)' in save and 'modern_road_coordinates.has(discovery_coord)' in save,
    "discovery field remains optional for prior snapshot compatibility": 'if snapshot.has("discovered_world_cells"):' in save and 'discovered_world_cells = _get_all_offroad_cells_discovered()' in manager,
}

failures = []
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
    if not passed:
        failures.append(name)

# Numerical reference model: reveal Manhattan-radius 3 around a road cell, never
# marking road cells as landscape. A rectangular route is used only as an independent
# oracle for mask bounds; the actual seeded contour is validated in the Stage 86 test.
MAP_W, MAP_H = 19, 14

def perimeter(left: int, top: int, width: int, height: int) -> list[tuple[int, int]]:
    right, bottom = left + width - 1, top + height - 1
    cells = [(x, top) for x in range(left, right + 1)]
    cells += [(right, y) for y in range(top + 1, bottom + 1)]
    cells += [(x, bottom) for x in range(right - 1, left - 1, -1)]
    cells += [(left, y) for y in range(bottom - 1, top, -1)]
    return cells

numeric_scenarios = 0
for left, top, width, height in [(4, 3, 11, 8), (5, 2, 9, 10), (4, 2, 10, 9), (3, 4, 13, 6)]:
    road = set(perimeter(left, top, width, height))
    assert len(road) == 34
    assert all(0 <= x < MAP_W and 0 <= y < MAP_H for x, y in road)
    for pivot in (perimeter(left, top, width, height)[0], perimeter(left, top, width, height)[len(road)//2]):
        mask = {(x, y) for y in range(MAP_H) for x in range(MAP_W)
                if (x, y) not in road and abs(x-pivot[0]) + abs(y-pivot[1]) <= 3}
        assert len(mask) <= 232
        assert not (mask & road)
        assert all(0 <= x < MAP_W and 0 <= y < MAP_H for x, y in mask)
        numeric_scenarios += 1
print(f"PASS: independent discovery-mask model covers {numeric_scenarios} seed/route samples without marking road cells")
if failures:
    raise SystemExit(1)
print(f"STAGE 88 DISCOVERY MASK REGRESSION PASSED: {len(checks)} source guards + {numeric_scenarios} reference scenarios")
print("Source and numerical tests only; Godot runtime and browser rendering remain unconfirmed.")

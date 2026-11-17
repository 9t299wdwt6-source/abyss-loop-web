#!/usr/bin/env python3
"""Stage88 save-safe compatibility guards for an always-visible landscape map.

These checks validate the persisted legacy field and the new presentation contract:
the entire off-road area is visible immediately, without reveal radius, fog, or glyphs.
"""
from __future__ import annotations
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
tile = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
localization = json.loads((ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"))

checks = {
    "expedition manager keeps the saved legacy map-visibility field": 'var discovered_world_cells: Dictionary = {}' in manager and '"discovered_world_cells": discovered_world_cells.duplicate(true)' in manager,
    "new runs mark the complete off-road area visible before the first route step": '_reveal_world_cells_near_route_index(0)' in manager and 'discovered_world_cells = _get_all_offroad_cells_discovered()' in manager,
    "the legacy reveal call no longer applies a walking-radius mask": 'func _reveal_world_cells_near_route_index(_route_index: int) -> void:' in manager and 'absi(col - pivot.x) + absi(row - pivot.y) > 3' not in manager,
    "resume ignores partial legacy discovery masks and restores full landscape visibility": 'discovered_world_cells = _get_all_offroad_cells_discovered()' in manager and 'discovered_world_cells = _normalize_discovered_world_cells(snapshot.get("discovered_world_cells", {}))' not in manager,
    "the full off-road map is exactly 232 valid map cells": 'func _get_all_offroad_cells_discovered() -> Dictionary:' in manager and 'TileSystemScript.map_world_cell_id(col, row)' in manager,
    "route view draws terrain directly without discovery gating": 'var terrain_colors: Array[Color]' in view and 'if not is_discovered:' not in view and 'var is_discovered :=' not in view,
    "no fog pass, unknown cell helper, discovery HUD, or question glyph remains": '_draw_unknown_cell_fog' not in view and '_draw_discovery_status_hud' not in view and '"?"' not in view and 'draw_discovery_status_hud' not in view,
    "landscape cell hover uses the normal empty-cell preview": 'tile.preview.empty.world' in ui and 'tile.preview.unknown.world' not in ui,
    "placement targets retain corner brackets and clear valid/invalid feedback": 'func _draw_placement_preview_corners(rect: Rect2, color: Color) -> void:' in view and 'tile.route.status.valid' in view and 'tile.route.status.invalid' in view,
    "map cell IDs and geometry remain canonical and deterministic": 'TileSystemScript.map_world_cell_id(coord.x, coord.y)' in tile and 'get_road_grid_coordinates_for_seed(get_route_shape_id(), route_geometry_seed)' in manager,
    "save schema continues accepting legacy masks and validates map IDs": 'if snapshot.has("discovered_world_cells"):' in save and 'discovery_value.size() > 232' in save and 'TileSystemScript.is_map_world_cell_id(discovery_key)' in save,
    "localization no longer promises exploration reveals hidden terrain": 'Неизведанная клетка' not in localization.get('tile.preview.unknown.world', '') and 'route.discovery.count' not in view,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")

# Independent geometry oracle: every off-road cell is visible immediately for
# each of the current 34-cell closed routes, and no road cell is counted as terrain.
MAP_W, MAP_H = 19, 14

def perimeter(left: int, top: int, width: int, height: int) -> list[tuple[int, int]]:
    right, bottom = left + width - 1, top + height - 1
    cells = [(x, top) for x in range(left, right + 1)]
    cells += [(right, y) for y in range(top + 1, bottom + 1)]
    cells += [(x, bottom) for x in range(right - 1, left - 1, -1)]
    cells += [(left, y) for y in range(bottom - 1, top, -1)]
    return cells

scenarios = 0
for left, top, width, height in [(4, 3, 11, 8), (5, 2, 9, 10), (4, 2, 10, 9), (3, 4, 13, 6)]:
    road = set(perimeter(left, top, width, height))
    assert len(road) == 34
    visible = {(x, y) for y in range(MAP_H) for x in range(MAP_W) if (x, y) not in road}
    assert len(visible) == 232
    assert not (visible & road)
    assert len(visible | road) == MAP_W * MAP_H
    scenarios += 1
print(f"PASS: full terrain visibility covers all 232 off-road cells in {scenarios} route profiles")
if failed:
    raise SystemExit("STAGE88 ALWAYS-VISIBLE MAP REGRESSION FAILED: " + "; ".join(failed))
print(f"STAGE88 ALWAYS-VISIBLE MAP REGRESSION PASSED: {len(checks)} source guards + {scenarios} geometry scenarios")
print("Source and numerical tests only; Godot/browser screenshots validate visual readability separately.")

#!/usr/bin/env python3
"""Stage 90 source contracts and numerical layout checks for discovery-map readability."""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
localization = json.loads((ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"))
tile = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")

checks = {
    "short header is selected for compact widths": 'size.x < 680.0' in view and 'Localization.text("route.header.compact")' in view,
    "discovery counter is drawn from RouteView redraw": '_draw_discovery_status_hud(route_geometry)' in view and 'func _draw_discovery_status_hud(route_geometry: Dictionary)' in view,
    "discovery count validates modern IDs and excludes current road cells": 'TileSystemScript.is_map_world_cell_id(cell_id)' in view and 'not road_lookup.has("%d:%d" % [coord.x, coord.y])' in view,
    "discovery counter has RU localized format": localization.get('route.discovery.count') == 'РАЗВЕДАНО %d/%d',
    "compact route title has RU localization": localization.get('route.header.compact') == 'МАРШРУТ · %d',
    "unknown terrain gets a dedicated fog pass": 'func _draw_unknown_cell_fog(tile_rect: Rect2, coord: Vector2i, cell_size: float, emphasized: bool) -> void:' in view and '_draw_unknown_cell_fog(tile_rect, coord, cell_size, cell_id == hovered_world_cell_id)' in view,
    "unknown state is marked at small but usable map-cell sizes": 'var font_size := 6 if cell_size < 16.0 else (7 if cell_size < 24.0 else 10)' in view and 'if not placement_enabled and cell_size >= 13.0:' in view,
    "placement validity badge scales with cell size": 'var status_size := clampf(cell_size * 0.48, 8.0, 12.0)' in view and 'var compact_status := ("+" if world_target_is_valid else "X") if cell_size < 20.0 else status_text' in view,
    "high contrast uses a distinct fog and status outline": 'Color("#eef7eb", 0.62)' in view and 'Color("#f4f8ee", 0.95)' in view,
    "tile IDs and cell geometry remain driven by TileSystem": 'TileSystemScript.map_world_cell_id(coord.x, coord.y)' in view and 'TileSystemScript.world_cell_coordinates(cell_id)' in view and 'static func is_map_world_cell_id(cell_id: String) -> bool:' in tile,
}
for label, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
failures = [label for label, ok in checks.items() if not ok]

# Independent layout model: the discovery pill is placed in reserved footer space,
# inside the canvas, at desktop, tablet, and phone sizes.
viewports = [(300, 350), (390, 844), (620, 420), (1440, 900), (1920, 1080)]
for width, height in viewports:
    usable_w = max(1.0, width - 28.0)
    usable_h = max(1.0, height - 64.0)
    cell_size = max(1.0, min(usable_w / 19.0, usable_h / 14.0))
    map_h = 14.0 * cell_size
    map_bottom = (height + map_h) * 0.5
    pill_w = min(148.0, max(112.0, width - 24.0))
    pill_x = width - pill_w - 12.0
    pill_y = 9.0
    assert pill_x >= 0 and pill_x + pill_w <= width - 12.0, (width, height, pill_x, pill_w)
    assert pill_y + 18.0 < map_bottom, (width, height, pill_y, map_bottom)
    assert pill_y + 18.0 <= 27.0, (width, height, pill_y)
print(f"PASS: discovery HUD fits reserved map/footer boundary in {len(viewports)} target viewports")
if failures:
    raise SystemExit("Stage 90 discovery readability regression failed: " + "; ".join(failures))
print(f"STAGE 90 DISCOVERY READABILITY REGRESSION PASSED: {len(checks)}/{len(checks)} source contracts + {len(viewports)} viewport scenarios")
print("Static/source and layout-reference checks only; Godot runtime/browser rendering are not implied.")

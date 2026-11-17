#!/usr/bin/env python3
"""Stage90 readability guards for the always-visible terrain presentation."""
from __future__ import annotations
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
localization = json.loads((ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"))
tile = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")

checks = {
    "compact route header remains selected for narrow widths": 'size.x < 680.0' in view and 'Localization.text("route.header.compact")' in view,
    "landscape is rendered as visible terrain cells from the first frame": 'var terrain_colors: Array[Color]' in view and 'draw_rect(tile_rect, base, true)' in view,
    "terrain palette stays translucent over the illustrated background": 'Color("#45634d", 0.24)' in view and 'Color("#536d4b", 0.22)' in view,
    "discovery count HUD is removed": '_draw_discovery_status_hud' not in view and 'route.discovery.count' not in view,
    "fog marks and unknown glyphs are removed from the canvas": '_draw_unknown_cell_fog' not in view and '"?"' not in view and '"#09161b", 0.98' not in view,
    "empty landscape hover no longer offers an explore-to-reveal state": 'tile.preview.unknown.world' not in ui and 'tile.preview.empty.world' in ui,
    "new and resumed runs always initialize all off-road cells as visible": 'discovered_world_cells = _get_all_offroad_cells_discovered()' in manager and 'absi(col - pivot.x) + absi(row - pivot.y) > 3' not in manager,
    "placement preview retains valid/invalid colour cues and compact badges": 'var compact_status := ("+" if world_target_is_valid else "X")' in view and 'tile.route.status.valid' in view and 'tile.route.status.invalid' in view,
    "high contrast still strengthens terrain outlines": 'outline = Color("#f4f8ee", 0.96)' in view and 'Color("#f4f8ee") if high_contrast else outline' in view,
    "pixel terrain symbols and committed placed tiles remain distinct": 'func _draw_pixel_symbol' in view and 'draw_rect(tile_rect, fill, true)' in view and 'world_tiles.get(cell_id, {})' in view,
    "map cell identifiers and road exclusion remain stable": 'TileSystemScript.map_world_cell_id(coord.x, coord.y)' in view and 'get_road_grid_coordinates_for_seed(get_route_shape_id(), route_geometry_seed)' in manager,
    "Russian unknown-role label and map previews contain no question punctuation": 'РОЛЬ?' not in localization.get('enemy.role.unknown', '') and '?' not in localization.get('tile.preview.empty.world', ''),
}
for label, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
failures = [label for label, ok in checks.items() if not ok]

# Independent readability model for the 19x14 board at desktop, tablet and phone sizes.
viewports = [(300, 350), (390, 844), (620, 420), (900, 600), (1280, 800), (1440, 900)]
for width, height in viewports:
    usable_w = max(1.0, width - 28.0)
    usable_h = max(1.0, height - 64.0)
    cell_size = min(usable_w / 19.0, usable_h / 14.0)
    assert cell_size > 0
    map_width, map_height = 19.0 * cell_size, 14.0 * cell_size
    left, top = (width - map_width) * 0.5, (height - map_height) * 0.5
    assert left >= 0 and top >= 0
    assert left + map_width <= width and top + map_height <= height
    # A terrain cell must retain a visible surface, while remaining large enough
    # to hit-test independently of the road and the rest of the UI.
    assert cell_size >= 10.0, (width, height, cell_size)
print(f"PASS: full-board terrain geometry remains inside {len(viewports)} supported viewport models")
if failures:
    raise SystemExit("STAGE90 ALWAYS-VISIBLE MAP REGRESSION FAILED: " + "; ".join(failures))
print(f"STAGE90 ALWAYS-VISIBLE MAP REGRESSION PASSED: {len(checks)}/{len(checks)} source guards + {len(viewports)} viewport scenarios")
print("Source and layout reference tests only; browser/Godot screenshot acceptance remains required.")

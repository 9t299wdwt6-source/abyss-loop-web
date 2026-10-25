"""Static regression for stage 66B: card target readability, contrast, and localized previews."""
from pathlib import Path
import json
import sys
ROOT = Path(__file__).resolve().parents[1]
route = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
tile = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
catalog = json.loads((ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"))
checks = {
    "route target uses the exact TileSystem road placement validator": "_placement_rules.can_place(route_cells, placed_tiles, i)" in route,
    "landscape target uses the exact TileSystem landscape placement validator": "_placement_rules.can_place_world(route_cells, world_tiles, cell_id, placement_probe, route_shape_id, route_geometry_seed)" in route,
    "visual target state includes non-colour plus and cross symbols": 'Localization.text("tile.route.status.valid")' in route and 'Localization.text("tile.route.status.invalid")' in route,
    "high contrast mode adds light and dark edge separation to route markers": 'marker_rect.grow(3.0), Color("#f4f8ee")' in route and 'marker_rect.grow(1.0), Color("#081319")' in route,
    "high contrast mode makes field markers and label plates more distinct": 'tile_rect.grow(2.0), Color("#f4f8ee")' in route and 'label_rect, Color("#f4f8ee")' in route,
    "road-target and landscape-target preview status text comes from catalog": all(f'_t("{key}")' in ui for key in ("tile.preview.blocked.road", "tile.preview.empty.road", "tile.preview.blocked.world", "tile.preview.empty.world")),
    "dynamic road preview strings come from localization templates": all(f'Localization.text("{key}")' in tile for key in ("tile.forecast.route_baseline", "tile.forecast.neighbor_bonus", "tile.forecast.no_synergy")),
    "dynamic landscape preview strings cover sector, effects, caps, and combinations": all(f'Localization.text("{key}")' in tile for key in ("tile.forecast.world_sector", "tile.forecast.world_sector_delta", "tile.forecast.world_synergy_caps", "tile.forecast.world_visit_caps")),
    "tutorial no longer contradicts dual-target road placement": "На самой дороге карты не размещаются." not in catalog["tutorial.2.body"] and "узел дороги" in catalog["tutorial.2.body"] and "клетку ландшафта" in catalog["tutorial.2.body"],
    "help copy describes both legal placement targets": "дорожный узел или клетку ландшафта" in catalog["help.body"],
    "placement hover now checks sector cap before showing a legal target": 'can_place_world(route_cells, world_tiles, cell_id, placement_probe, route_shape_id, route_geometry_seed)' in route and 'world_target_is_valid := placement_enabled and placement_action_allowed and bool(world_check.get("ok", false))' in route,
    "Godot smoke remains listed for runtime check rather than falsely marked as passed": "Godot" in (ROOT / "CARD_PLACEMENT_RUNTIME_ACCEPTANCE_STAGE66A_RU.md").read_text(encoding="utf-8") and "source" in smoke.lower(),
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed: sys.exit("STAGE66B READABILITY/LOCALIZATION REGRESSION FAILED: " + "; ".join(failed))
print(f"STAGE66B READABILITY/LOCALIZATION REGRESSION: {len(checks)}/{len(checks)}")
print("Static/source checks only; Godot rendering and translated GDScript formatting still require runtime acceptance.")

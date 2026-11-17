"""Stage92 guard for the always-visible terrain and question-mark-free UI."""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
diagnostics = (ROOT / "scripts/ui/developer_diagnostics_report.gd").read_text(encoding="utf-8")
strings = json.loads((ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"))

ui_scripts = list((ROOT / "scripts/ui").glob("*.gd"))
ui_question_lines = [
    f"{path.name}:{line_number}:{line.strip()}"
    for path in ui_scripts
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1)
    if "?" in line
]

checks = {
    "new expeditions reveal the whole off-road field immediately": "_reveal_world_cells_near_route_index(0)" in manager and "discovered_world_cells = _get_all_offroad_cells_discovered()" in manager,
    "legacy reveal helper no longer waits for the player to walk nearby": "func _reveal_world_cells_near_route_index(_route_index: int) -> void:" in manager and "absi(col - pivot.x) + absi(row - pivot.y) > 3" not in manager,
    "resumed old saves also show the entire off-road field": "# The full off-road landscape is visible immediately on every new or resumed run." in manager and "discovered_world_cells = _normalize_discovered_world_cells(snapshot.get(" not in manager,
    "all 232 non-road map squares are represented by the full visibility helper": "func _get_all_offroad_cells_discovered() -> Dictionary:" in manager and "for row in range(TileSystemScript.MAP_ROWS)" in manager and "for col in range(TileSystemScript.MAP_COLUMNS)" in manager,
    "route view has no fog pass, discovery HUD, or question glyph": "_draw_unknown_cell_fog" not in view and "_draw_discovery_status_hud" not in view and "?" not in view,
    "unplaced terrain is visible with translucent biome tint instead of opaque fog": 'Color("#45634d", 0.24)' in view and 'Color("#3b5d4e", 0.26)' in view and '"#09161b", 0.98' not in view,
    "map placement validation and preview remain active on the revealed field": "_placement_rules.can_place_world" in view and "_draw_placement_preview_corners" in view and "tile.route.status.valid" in view,
    "hovering an empty map cell shows its ordinary empty-cell information": 'tile.preview.empty.world' in ui and "tile.preview.unknown.world" not in ui,
    "all player-facing UI scripts contain no question-mark glyphs": not ui_question_lines,
    "diagnostic fallback labels use a typographic dash instead of a question mark": "get(\"hp\", \"—\")" in diagnostics and '"?"' not in diagnostics,
    "Russian localization has no remaining visible question marks": all("?" not in value for value in strings.values() if isinstance(value, str)),
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if ui_question_lines:
    print("Visible UI question mark candidates:")
    print("\n".join(ui_question_lines))
if failed:
    raise SystemExit("STAGE92 ALWAYS-VISIBLE MAP REGRESSION FAILED: " + ", ".join(failed))
print(f"STAGE92 ALWAYS-VISIBLE MAP REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Source-level checks only; Godot/browser screenshot acceptance is still required.")

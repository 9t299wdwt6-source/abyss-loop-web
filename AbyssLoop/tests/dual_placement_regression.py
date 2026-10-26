"""Source-level regression for the dual road-node / landscape card placement UX."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
route = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
world_test = (ROOT / "tests/world_field_regression.py").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
localization = json.loads((ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"))

def block(source: str, start: str, end: str) -> str:
    first = source.index(start)
    last = source.index(end, first + len(start))
    return source[first:last]

route_click = block(ui, "func _on_route_cell_clicked(cell_index: int) -> void:", "func _on_world_cell_hovered(")
route_hover = block(ui, "func _on_route_cell_hovered(cell_index: int) -> void:", "func _on_route_cell_clicked(")
world_hover = block(ui, "func _on_world_cell_hovered(cell_id: String) -> void:", "func _on_world_cell_clicked(")
route_place = block(manager, "func place_tile(hand_index: int, cell_index: int) -> Dictionary:", "func place_world_tile(")

checks = {
    "road-node click invokes the route-tile placement API": "manager.place_tile(selected_tile_hand_index, cell_index)" in route_click,
    "route view handles touch press and ignores touch release/cancel": "if event is InputEventScreenTouch:" in route and "not touch_event.pressed or touch_event.canceled" in route,
    "screen-touch viewport coordinates are converted to RouteView-local coordinates": "make_input_local(touch_event)" in route and "_handle_click_position(local_touch.position)" in route,
    "mouse and touch use the same road/landscape click dispatcher": "func _handle_click_position(local_position: Vector2) -> void:" in route and "_handle_click_position(mouse_event.position)" in route and "world_cell_clicked.emit(world_id)" in route and "cell_clicked.emit(closest_index)" in route,
    "landscape click invokes the separate world-placement API": "manager.place_world_tile(selected_tile_hand_index, cell_id)" in ui,
    "road hover calls the road-synergy preview": "get_placement_preview(manager.route, manager.placed_tiles, cell_index, selected_tile, manager.equipment)" in route_hover,
    "landscape hover calls the landscape-sector preview": "get_world_placement_preview(manager.route, manager.world_tiles, cell_id, selected_tile, manager.equipment, manager.get_route_shape_id(), manager.get_route_geometry_seed())" in world_hover,
    "road placement remains blocked during active combat": "if not enemy.is_empty():" in route_place and "Во время боя размещение временно недоступно." in route_place,
    "road placement is blocked while event/perk choices are pending": "not pending_event.is_empty() or pending_perk_count > 0" in route_place,
    "road placement spends exactly the selected hand card and saves the run snapshot": 'placed_tiles[str(cell_index)] = tile' in route_place and 'tile_hand.remove_at(hand_index)' in route_place and 'save_run_snapshot()' in route_place and 'changed.emit()' in route_place,
    "road placement duplicates card data before it enters the route map": 'tile_hand[hand_index].duplicate(true)' in route_place,
    "placement lock message is shared by both UI targets": "func _get_tile_placement_block_reason()" in ui and "_get_tile_placement_block_reason()" in route_hover and "_get_tile_placement_block_reason()" in world_hover,
    "map visual uses the same validator as road placement and includes non-colour state icons": "_placement_rules.can_place(route_cells, placed_tiles, i, route_probe)" in route and 'Localization.text("tile.route.status.valid")' in route and 'Localization.text("tile.route.status.invalid")' in route and 'Color("#8fe3a5") if route_target_is_valid else Color("#ec8a7d")' in route,
    "blocked landscape cells include full-sector and global placement locks in visual state": "_placement_rules.can_place_world(route_cells, world_tiles, cell_id, placement_probe, route_shape_id, route_geometry_seed)" in route and 'world_target_is_valid := placement_enabled and placement_action_allowed and bool(world_check.get("ok", false))' in route and 'base = Color("#c96562", 0.42)' in route and 'outline = Color("#ed9d91", 1.0)' in route,
    "both click handlers guard against a missing manager": route_click.startswith("func _on_route_cell_clicked(cell_index: int) -> void:\n\tif manager == null or not is_instance_valid(manager):") and "func _on_world_cell_clicked(cell_id: String) -> void:\n\tif manager == null or not is_instance_valid(manager):" in ui,
    "landscape click shows the same action lock before calling the manager": "var blocked_reason := _get_tile_placement_block_reason()" in block(ui, "func _on_world_cell_clicked(cell_id: String) -> void:", "func _toggle_pause()") and "manager.place_world_tile(selected_tile_hand_index, cell_id)" in block(ui, "func _on_world_cell_clicked(cell_id: String) -> void:", "func _toggle_pause()"),
    "localization identifies both road and landscape targets after hint relocation": "ДОРОГЕ" in localization.get("route.no_tiles", "") and "ЛАНДШАФТЕ" in localization.get("route.no_tiles", "") and "Стартовый узел закрыт" in localization.get("expedition.route_hint", "") and "ландшафта" in localization.get("expedition.tiles.preview_description", ""),
    "route view label no longer claims that cards cannot be placed on roads": "РАЗМЕЩАЮТСЯ НА ЛАНДШАФТЕ, НЕ НА ДОРОГЕ" not in localization.get("route.no_tiles", ""),
    "Godot smoke includes road preview and relocated both-target guidance assertions": "road preview must identify the selected tile before placement" in smoke and "tile placement guidance must cover both road and landscape targets after hint relocation" in smoke,
    "existing road/landscape geometry contract remains covered": "road segments must never be treated as landscape placement cells" in smoke and "_find_world_cell(field_center) == world_cell_id" in smoke,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    raise SystemExit("DUAL PLACEMENT REGRESSION FAILED: " + ", ".join(failed))
print(f"DUAL PLACEMENT REGRESSION: {sum(checks.values())}/{len(checks)}")
print("Source-level checks only; verify actual clicks and rendering in Godot 4.7.2.")

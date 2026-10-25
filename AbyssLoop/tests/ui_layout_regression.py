"""Static regression guard for the collapsed-header layout bug (no Godot needed)."""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
catalog = json.loads((ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"))
required = {
    "fullscreen shell expands in both dimensions": "shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL\n\tshell.size_flags_vertical = Control.SIZE_EXPAND_FILL",
    "main column expands in both dimensions": "main_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL\n\tmain_column.size_flags_vertical = Control.SIZE_EXPAND_FILL",
    "brand has a minimum readable width on desktop and releases width for compact layouts": "_brand_box.custom_minimum_size.x = 0 if compact_layout else 285",
    "phase badge has a minimum width": "phase_panel.custom_minimum_size.x = 122",
    "settings button has a minimum width": "settings_button.custom_minimum_size.x = 112",
    "short labels do not autowrap": "label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if text_value.length() > 42 else TextServer.AUTOWRAP_OFF",
    "content root expands horizontally and vertically": "content_root.size_flags_vertical = Control.SIZE_EXPAND_FILL\n\tcontent_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL",
    "right expedition column uses a scroll container": "var right_scroll := ScrollContainer.new()",
    "right scroll container disables horizontal overflow": "right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED",
    "event log uses a bounded scroll area": "log_scroll = ScrollContainer.new()",
    "event log has a fixed minimum viewing height": "log_scroll.custom_minimum_size.y = 104",
    "buttons support keyboard focus": "button.focus_mode = Control.FOCUS_ALL",
    "disabled actions use muted styling": 'button.add_theme_stylebox_override("disabled", disabled_style)',
    "disabled action text remains readable": 'button.add_theme_color_override("font_disabled_color", Color("#b0bbb4"))',
    "help button is accessible in the header": 'help_button = _button(_t("header.button.help"), Callable(self, "_open_help_menu")' and catalog.get("header.button.help") == "Справка",
    "placement preview label exists in tactical panel for road and landscape targets": 'tile_preview_label = _label(_t("expedition.tiles.preview_title")' and catalog.get("expedition.tiles.preview_title") == "ПРЕДПРОСМОТР РАЗМЕЩЕНИЯ" and "get_placement_preview(manager.route, manager.placed_tiles, cell_index, selected_tile, manager.equipment)" in source and "get_world_placement_preview(manager.route, manager.world_tiles, cell_id, selected_tile, manager.equipment, manager.get_route_shape_id(), manager.get_route_geometry_seed())" in source,
    "route view emits hover state": "route_view.cell_hovered.connect(_on_route_cell_hovered)",
    "preview uses gameplay tile system": "manager.tile_system.get_world_placement_preview(manager.route, manager.world_tiles, cell_id, selected_tile, manager.equipment, manager.get_route_shape_id(), manager.get_route_geometry_seed())",
    "equipment summary wraps at the panel edge": "equipment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART",
    "equipment summary expands to the panel width": "equipment_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL",
    "expedition report uses a vertical details scroll area": "var details_scroll := ScrollContainer.new()",
    "expedition report details scroll vertically": "details_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO",
    "expedition report footer action remains outside the scroll area": "layout.add_child(continue_button)",
}
missing = [description for description, condition in required.items() if (not condition if isinstance(condition, bool) else condition not in source)]
if missing:
    print("UI LAYOUT REGRESSION CHECK FAILED")
    for item in missing:
        print(f"- {item}")
    sys.exit(1)
print("UI LAYOUT REGRESSION CHECK PASSED:")
for item in required:
    print(f"- {item}")
print("Note: this checks intended layout safeguards in source; it does not replace a Godot runtime test.")

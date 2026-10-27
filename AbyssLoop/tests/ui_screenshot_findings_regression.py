"""Regressions for concrete UI findings from the user's 1440x900 screenshots."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
route = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
project = (ROOT / "project.godot").read_text(encoding="utf-8")
checks = {
    "shelter content has a vertical scroll area instead of clipping below the viewport": "var base_scroll := ScrollContainer.new()" in ui and "base_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO" in ui and "base_scroll.add_child(base_content)" in ui,
    "shelter cards size to content so the scroll can reach the statistics/footer": "top_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN" in ui and "launch_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN" in ui and "_make_panel(base_content, C_PANEL, 16)" in ui,
    "shelter reassurance content is stacked in a single VBox child": "reassurance.add_child(reassurance_box)" in ui and "reassurance_box.add_child(_label(_t(\"base.risk.title\")" in ui and "reassurance_box.add_child(risk_description)" in ui and "reassurance.add_child(_label(" not in ui,
    "first-session onboarding content is stacked in a single VBox child": "first_session_panel.add_child(first_session_box)" in ui and "first_session_box.add_child(first_session_status_label)" in ui and "first_session_box.add_child(after_return_label)" in ui and "first_session_panel.add_child(_label(" not in ui,
    "long route instruction is placed in the tile panel, not under the route canvas": "tile_box.add_child(route_hint_label)" in ui and "map_box.add_child(route_hint_label)" not in ui and 'route_hint_label = _label(_t("expedition.route_hint"), 10, C_MUTED)' in ui,
    "route footer retains a concise prompt without a duplicate instruction line": "route.no_tiles" in route and "expedition.route_hint" in ui and '"expedition.route_hint": "Стартовый узел закрыт.' in (ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"),
    "expedition equipment wraps and uses a more readable 12px baseline": 'equipment_label = _label("", 12, C_TEXT)' in ui and "equipment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART" in ui,
    "tile cards retain a 64px hit target and readable text in responsive columns": "button.custom_minimum_size = Vector2(0 if tile_hand_grid.columns == 1 else 148, 64)" in ui and 'button.add_theme_font_size_override("font_size", 12)' in ui and "button.size_flags_horizontal = Control.SIZE_EXPAND_FILL" in ui,
    "repeated tile cards identify separate copies without changing gameplay state": "copies_by_tile_id" in ui and "copy_index_by_tile_id" in ui and "%s · %d/%d" in ui,
    "status, control and tile panel headings are enlarged": 'controls.add_child(_label(_t("expedition.controls.target_health"), 12, C_MUTED))' in ui and 'tile_box.add_child(_label(_t("expedition.tiles.title"), 12, C_MUTED, true))' in ui,
    "route marker labels use a fitted backing plate and adaptive font for dense routes": "label_font_size := 5 if _map_cell_size() < 18.0 else (6 if _map_cell_size() < 26.0 else (7 if count >= 30 else (8 if not placed.is_empty() else 9)))" in route and "var label_rect := Rect2" in route and 'draw_rect(label_rect, Color("#f4f8ee") if high_contrast else Color("#09191d", 0.86), true)' in route,
    "event and tutorial modal body font is increased": 'box.add_child(_label(body_text, 14, C_MUTED))' in ui,
    "right-hand expedition panel remains scrollable without horizontal overflow": "var right_scroll := ScrollContainer.new()" in ui and "right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED" in ui,
    "mobile viewport resize switches the shelter and expedition into compact layouts": "get_viewport().size_changed.connect(_on_viewport_size_changed)" in ui and "func _is_compact_layout() -> bool:" in ui and "if compact_layout == _compact_layout_active:" in ui,
    "Web stretch aspect expands to avoid portrait letterboxing": 'window/stretch/aspect="expand"' in project,
    "compact view uses the actual browser window as its virtual content size": "func _update_content_scale() -> void:" in ui and "root_window.content_scale_size = target_scale_size" in ui and "Vector2i(1440, 900)" in ui and "Window.CONTENT_SCALE_ASPECT_EXPAND" in ui,
    "viewport resize updates virtual content scale before breakpoint layout": "_update_content_scale()\n\t_apply_responsive_shell()" in ui and "get_viewport().size_changed.connect(_on_viewport_size_changed)" in ui,

    "compact shell hides overflow-prone desktop header and resource controls": "_brand_subtitle.visible = not compact_layout" in ui and "help_button.visible = not compact_layout" in ui and "_run_panel.visible = not compact_layout" in ui,
    "narrow shelter stacks preparation and buildings and grids statistics": "var top_row: BoxContainer = VBoxContainer.new() if compact_layout else HBoxContainer.new()" in ui and "var stats: Container = GridContainer.new() if compact_layout else HBoxContainer.new()" in ui,
    "narrow expedition uses a single vertical scroll container and stacked map/controls": "var expedition_scroll := ScrollContainer.new()" in ui and "var body: BoxContainer = VBoxContainer.new() if compact_layout else HBoxContainer.new()" in ui and "body.add_child(right_column)" in ui,
    "map hit targets use a smaller minimum canvas in compact mode": (
        "configure_compact_layout(compact_layout)" in ui
        or 'route_view.call("configure_compact_layout", compact_layout)' in ui
    ) and "func configure_compact_layout(compact: bool) -> void:" in route and "Vector2(300, 350) if compact else Vector2(620, 420)" in route,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL") + ": " + name)
assert not failed, "Screenshot UI regression failed: " + ", ".join(failed)
print(f"SCREENSHOT UI REGRESSION: {sum(checks.values())}/{len(checks)}")
print("Static checks only; verify shelter scrolling and font sizing in Godot at 1440x900 and 1920x1080.")

"""Stage 61 UI regression: modal bodies stay bounded and actions remain reachable."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")

start = ui.index("func _show_modal(")
end = ui.index("\nfunc _prepare_overlay()", start)
modal = ui[start:end]

checks = {
    "long dialog body has a dedicated scroll container": "var body_scroll := ScrollContainer.new()" in modal and "body_scroll.add_child(body_label)" in modal,
    "body scrolling is vertical and horizontal overflow is disabled": "body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO" in modal and "body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED" in modal,
    "modal body height is capped against viewport height": "var max_body_height := minf(280.0, maxf(120.0, viewport_size.y - 440.0))" in modal and "clampf(80.0 + float(body_text.length()) * 0.32, 110.0, max_body_height)" in modal,
    "long modal text wraps inside the available width": "body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART" in modal and "body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL" in modal,
    "dialog title and choice buttons are outside the body scroller": "modal_layout.add_child(title_label)" in modal and "modal_layout.add_child(button_parent)" in modal and "button_parent.add_child(button)" in modal,
    "choice buttons expand to the panel width and retain minimum height": "button.size_flags_horizontal = Control.SIZE_EXPAND_FILL" in modal and "button.custom_minimum_size = Vector2(0, 76 if not button_group.is_empty() else (64 if kind == \"event\" else (48 if kind == \"perk\" else 42)))" in modal,
    "settings retain their own bounded vertical scroll area": "var settings_scroll := ScrollContainer.new()" in modal and "settings_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO" in modal,
    "new overlays reapply saved high contrast before focus is configured": "if bool(GameState.settings.get(\"high_contrast\", false)):\n\t\t_apply_contrast_to_tree(overlay)" in ui[ui.index("func _configure_overlay_focus"):],
    "base screen reapplies high contrast when rebuilding controls": "if bool(GameState.settings.get(\"high_contrast\", false)):\n\t\t_apply_contrast_to_tree(self)" in ui[ui.index("func _render_base"):ui.index("func _start_expedition")],
    "expedition screen reapplies high contrast when rebuilding controls": "if bool(GameState.settings.get(\"high_contrast\", false)):\n\t\t_apply_contrast_to_tree(self)" in ui[ui.index("func _render_expedition"):ui.index("func _sync_expedition_view")],
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL") + ": " + name)
assert not failed, "UI modal responsiveness regression failed: " + ", ".join(failed)
print(f"UI MODAL RESPONSIVENESS REGRESSION: {sum(checks.values())}/{len(checks)}")
print("Static source guard only; verify actual clipping and focus in Godot 4.7.2.")

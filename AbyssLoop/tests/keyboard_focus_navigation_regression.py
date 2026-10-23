"""Source-level safeguards for predictable keyboard navigation and modal focus."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
catalog = json.loads((ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"))

checks = {
    "buttons advertise a visible high-contrast focus state": 'button.add_theme_stylebox_override("focus", focus_style)' in ui and 'focus_style.border_color = Color("#fff2a8")' in ui,
    "button commands use a short anti-double-activation guard": 'var action_guard := {"busy": false}' in ui and 'get_tree().create_timer(0.18)' in ui and 'callback.call()' in ui,
    "form controls use explicit high-contrast focus outlines": "func _apply_keyboard_focus_outline(control: Control)" in ui and 'control.add_theme_stylebox_override("focus", focus_style)' in ui,
    "expedition selectors participate in keyboard focus": all(f"_apply_keyboard_focus_outline({name})" in ui for name in ("expedition_mode_option", "difficulty_option", "modifier_option", "contract_option")),
    "seed input participates in keyboard focus": "_apply_keyboard_focus_outline(seed_input)" in ui,
    "settings sliders and toggles participate in keyboard focus": "_apply_keyboard_focus_outline(slider)" in ui and "_apply_keyboard_focus_outline(toggle)" in ui,
    "modals remember where focus came from": "var _focus_before_overlay: Control" in ui and "_focus_before_overlay = focus_owner as Control" in ui,
    "closing a modal restores valid prior focus": "call_deferred(\"_focus_control_if_valid\", restore_target)" in ui,
    "modal tab traversal is explicitly looped": "current.focus_next = current.get_path_to(next_control)" in ui and "current.focus_previous = current.get_path_to(previous_control)" in ui,
    "modal focus collection excludes disabled actions": "enabled = not (control as BaseButton).disabled" in ui,
    "confirmation starts on a safe option": 'effective_kind in ["confirm", "confirm_reset", "confirm_salvage"]' in ui and 'lower_text.contains("отмена")' in ui,
    "keyboard focus cannot escape to background while an overlay is open": "overlay.is_ancestor_of(target)" in ui,
    "destructive salvage confirmation is protected from Escape": '"confirm_salvage"' in ui and 'modal_kind in ["event", "perk", "confirm", "confirm_reset", "confirm_salvage"]' in ui,
    "Escape releases text-input focus before global shortcuts": "focused_control is LineEdit or focused_control is TextEdit" in ui and "(focused_control as Control).release_focus()" in ui,
    "screen transitions focus a primary action": "_base_primary_action = start_button" in ui and "call_deferred(\"_focus_control_if_valid\", pause_button)" in ui and "call_deferred(\"_focus_control_if_valid\", continue_button)" in ui,
    "help lists keyboard and confirmation behavior": '_t("help.body")' in ui and "Shift+Tab" in catalog.get("help.body", "") and "безопасном варианте" in catalog.get("help.body", ""),
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL") + ": " + name)
assert not failed, "Keyboard focus regression failed: " + ", ".join(failed)
print(f"KEYBOARD FOCUS NAVIGATION REGRESSION: {len(checks)}/{len(checks)}")
print("Note: source-level guards only; traversal order and visual focus must still be exercised in Godot 4.7.2.")

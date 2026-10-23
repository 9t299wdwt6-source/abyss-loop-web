"""Source-level checks for keyboard usability and protected modal decisions."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
catalog = json.loads((ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"))

checks = {
    "buttons are reachable by keyboard": "button.focus_mode = Control.FOCUS_ALL" in ui,
    "F1 opens contextual help": "KEY_F1" in ui and 'Callable(self, "_open_help_menu")' in ui,
    "Escape handles modal state": "key_event.keycode == KEY_ESCAPE" in ui,
    "event and level-up choices are not accidentally dismissed": 'modal_kind in ["event", "perk", "confirm", "confirm_reset", "confirm_salvage"]' in ui,
    "Space toggles expedition pause": "key_event.keycode == KEY_SPACE" in ui and "manager.set_pause(not manager.paused)" in ui,
    "1/2/3 switch simulation speed": all(f"key_event.keycode == KEY_{n}" in ui for n in (1, 2, 3)),
    "right column is bounded by a scroll container": "var right_scroll := ScrollContainer.new()" in ui,
    "log is inside a bounded scroll container": "log_scroll = ScrollContainer.new()" in ui and "log_scroll.custom_minimum_size.y = 104" in ui,
    "mouse wheel can scroll the log/controls without moving the whole window": "right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED" in ui and "log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED" in ui,
    "help can resume tutorial progress": '_t("modal.button.continue_tutorial_step") % (GameState.tutorial_page + 1)' in ui and "%d" in catalog.get("modal.button.continue_tutorial_step", ""),
}
failed = [name for name, ok in checks.items() if not ok]
assert not failed, "Keyboard UX checks failed: " + ", ".join(failed)
print("KEYBOARD/UX REGRESSION CHECK PASSED:")
for name in checks:
    print("- " + name)
print("Note: source-level guard only; key handling, scrolling, and layout must be checked inside Godot.")

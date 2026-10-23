"""Source-level guards for the first-run tutorial and saved tutorial progress."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
catalog = (ROOT / "localization/strings_ru.json").read_text(encoding="utf-8")

checks = {
    "five tutorial pages reference centralized catalog keys": all(f'"tutorial.{i}.title"' in catalog and f'"title_key": "tutorial.{i}.title"' in ui for i in range(1, 6)) and "TUTORIAL_STEPS" in ui,
    "first run launches tutorial": 'call_deferred("_show_tutorial_step", GameState.tutorial_page)' in ui,
    "tutorial state persists": '"tutorial_page": tutorial_page' in state and '"tutorial_completed": tutorial_completed' in state,
    "progress can go back and forward": 'Callable(self, "_show_tutorial_step").bind(bounded_step - 1)' in ui and 'Callable(self, "_show_tutorial_step").bind(bounded_step + 1)' in ui,
    "placement tutorial accurately describes both legal target types": "узел дороги" in catalog.lower() and "клетку ландшафта" in catalog.lower() and "на самой дороге карты не размещаются" not in catalog.lower(),
    "skip/complete state persists": 'func _finish_tutorial()' in ui and 'GameState.tutorial_completed = true' in ui,
    "reopen and reset help is available": 'func _open_help_menu()' in ui and 'func _restart_tutorial()' in ui,
    "help can be opened through the header": 'help_button = _button(_t("header.button.help"), Callable(self, "_open_help_menu")' in ui,
    "old save migration provides tutorial defaults": 'data["tutorial_completed"] = false' in save and 'data["tutorial_page"] = 0' in save,
}
failed = [name for name, ok in checks.items() if not ok]
assert not failed, "Tutorial regression checks failed: " + ", ".join(failed)
print("TUTORIAL REGRESSION CHECK PASSED:")
for name in checks:
    print("- " + name)
print("Note: source-level check only; visual and keyboard interactions need Godot runtime testing.")

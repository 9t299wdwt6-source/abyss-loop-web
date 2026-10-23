"""Source-level guards for the first-session onboarding path."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
catalog = (ROOT / "localization/strings_ru.json").read_text(encoding="utf-8")
checks = {
    "first session guide appears until first completed expedition": "if GameState.runs_completed == 0:" in ui,
    "guide distinguishes fresh run from resumable save": "if GameState.has_saved_expedition():" in ui and "GameState.runs_started > 0" in ui,
    "guide explains automatic closed route": "автоматически проходит замкнутый маршрут" in catalog,
    "guide explains safe return and risk": "вернитесь на базу вне боя" in catalog and "риск не стал слишком высоким" in catalog,
    "guide points to persistent shelter progression": "улучшение убежища" in catalog,
    "help remains available from first-session panel": 'Callable(self, "_open_help_menu")' in ui and "func _open_help_menu()" in ui,
    "first session state uses persisted run counters": '"runs_completed": runs_completed' in state and '"runs_started": runs_started' in state,
}
failed = [k for k,v in checks.items() if not v]
assert not failed, "First-session flow regression failed: " + ", ".join(failed)
print("FIRST-SESSION FLOW REGRESSION PASSED: %d checks" % len(checks))
for name in checks: print("- " + name)
print("Source-level check only; first-session usability still needs an in-engine playthrough.")

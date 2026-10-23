"""Source-level regression guards for choice-driven expedition events."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
event_system = (ROOT / "scripts/systems/expedition_event_system.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
game_state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "event content is data-driven": "const EXPEDITION_EVENTS := {" in registry and '"sealed_cache"' in registry,
    "every configured event offers multiple effects": registry.count('"id": "') >= 8 and registry.count('"effects": {') >= 8,
    "event system chooses weighted definitions": "func draw_event(" in event_system and "total_weight" in event_system,
    "every event cell interrupts route movement": '"event":\n\t\t\tshould_offer_event = true' in manager and "not pending_event.is_empty()" in manager,
    "event resolution checks affordability before spending": "if int(run_ledger.get(\"scrap\", 0)) < cost_scrap:" in manager,
    "choices update health and expedition danger": 'hero["hp"] = maxi(0, int(hero.get("hp", 0)) - damage)' in manager and "danger_delta" in manager,
    "risk effects can affect the next encounter": 'effects.get("spawn_bonus", 0.0)' in manager and 'effects.get("reward_bonus", 0.0)' in manager,
    "event choices are presented through a blocking modal": "func _show_event_choices() -> void:" in ui and '"event"' in ui,
    "unaffordable choice can be disabled": '"disabled": not available' in ui and 'button.disabled = bool(button_data.get("disabled", false))' in ui,
    "event decisions are included in persistent statistics": '"total_events_resolved": total_events_resolved' in game_state,
    "event choice history is shown in the expedition report": "ВАШИ ПОСЛЕДНИЕ РЕШЕНИЯ" in ui and '"event_history": event_history' in game_state,
    "smoke test covers event generation": "first_event" in smoke and "has_event_node" in smoke,
}
failed = [label for label, passed in checks.items() if not passed]
if failed:
    print("EXPEDITION EVENT REGRESSION CHECK FAILED")
    for label in failed:
        print(f"- {label}")
    sys.exit(1)
print("EXPEDITION EVENT REGRESSION CHECK PASSED:")
for label in checks:
    print(f"- {label}")
print("Note: source-level guard only; run tests/smoke_test.gd in Godot for runtime validation.")

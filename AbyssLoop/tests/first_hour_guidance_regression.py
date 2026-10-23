"""Source-level guards for context-sensitive first-expedition onboarding."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
catalog = json.loads((ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"))
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")

required_hints = {
    "onboarding.first_run.title",
    "onboarding.hint.first_tile",
    "onboarding.hint.wait_for_tile",
    "onboarding.hint.event",
    "onboarding.hint.perk",
    "onboarding.hint.boss",
    "onboarding.hint.boss_telegraph",
    "onboarding.hint.elite",
    "onboarding.hint.combat",
    "onboarding.hint.low_health",
    "onboarding.hint.after_first_tile",
    "onboarding.hint.synergy_active",
    "onboarding.hint.after_tiles_no_synergy",
}

checks = {
    "first-run panel is created and hidden until an active first expedition": all(token in ui for token in ("first_hour_guide_panel = _make_panel", "first_hour_guide_panel.visible = false", "manager.active and GameState.runs_completed == 0")),
    "guide refresh is called from the live expedition HUD sync": "_refresh_first_hour_guide()" in ui and "func _refresh_first_hour_guide()" in ui,
    "event and perk guidance takes priority before combat and tile hints": ui.index('if not manager.pending_event.is_empty():', ui.index('func _first_hour_guide_text')) < ui.index('if int(manager.pending_perk_count) > 0:', ui.index('func _first_hour_guide_text')) < ui.index('if not manager.enemy.is_empty():', ui.index('func _first_hour_guide_text')),
    "normal, elite, boss and telegraphed boss encounter states have distinct hints": all(key in ui for key in ("onboarding.hint.combat", "onboarding.hint.elite", "onboarding.hint.boss", "onboarding.hint.boss_telegraph")) and "telegraph_pending" in ui,
    "first tile and later tile placement have separate guidance": all(key in ui for key in ("onboarding.hint.first_tile", "onboarding.hint.after_first_tile", "onboarding.hint.after_tiles_no_synergy")) and "manager.tile_hand.is_empty()" in ui,
    "synergy is inferred from the same tile-system calculation rather than a guessed heuristic": "get_synergy_bonus(manager.placed_tiles, route_index, manager.route.size())" in ui and "get_world_synergy_bonus(manager.world_tiles" in ui,
    "low-health hint does not replace or unlock the return action": "int(manager.hero.get(\"hp\", max_hp)) * 3 <= max_hp" in ui and "func _request_return()" in ui,
    "all first-hour guide strings exist, are used and are non-empty": required_hints <= set(catalog) and all(isinstance(catalog[key], str) and catalog[key].strip() for key in required_hints) and all(f'_t("{key}")' in ui for key in required_hints if key != "onboarding.first_run.title"),
    "guide is presentation-only and does not mutate gameplay or save state": "presentation-only guidance" in ui and "GameState.save_now()" not in ui[ui.index("func _refresh_first_hour_guide"):ui.index("func _build_tile_hand")],
    "event flow still blocks the route until a choice is resolved": "if paused or not pending_event.is_empty():" in manager,
    "guide signature avoids recomputing synergy on every rendered frame": "if signature == _first_hour_guide_signature:" in ui and "_first_hour_has_tile_synergy()" in ui,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL") + ": " + name)
assert not failed, "First-hour guidance regression failed: " + ", ".join(failed)
print(f"FIRST-HOUR GUIDANCE REGRESSION: {sum(checks.values())}/{len(checks)}")
print("Source-level check only; visual fitting and the actual first-hour playthrough require Godot runtime testing.")

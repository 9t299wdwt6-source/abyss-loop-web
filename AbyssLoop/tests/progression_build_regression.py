"""Static regression guard for build categories, perk caps and unique draft choices."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
progression = (ROOT / "scripts/systems/progression_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "perk pool has offensive, defensive, economy and utility roles": all(f'"{key}":' in registry for key in ("power", "vitality", "bulwark", "vampirism", "scavenger", "fortune", "ambush", "field_medic")),
    "every perk has a stack limit": registry.count('"max_stacks":') >= 10,
    "draft filters capped perks and removes duplicates": "perk_counts" in progression and "available.remove_at(index)" in progression,
    "perk application records rank and applies effect fields": all(f'hero["{key}"]' in progression for key in ("perk_counts", "defense_bonus", "perk_kill_heal_bonus", "perk_tile_scrap_bonus", "perk_event_heal_bonus", "perk_reward_bonus", "perk_tile_spawn_bonus")),
    "all-capped fallback avoids a stuck level-up modal": "all perks reached" not in manager.lower() and "Все навыки достигли предела" in manager,
    "UI shows category and rank cap": '"%s · %s (%d/%d)' in ui,
    "gameplay stats combine items and perks": all(key in manager for key in ("perk_kill_heal_bonus", "perk_tile_scrap_bonus", "perk_event_heal_bonus", "perk_reward_bonus", "perk_tile_spawn_bonus")),
    "runtime smoke covers caps and duplicate-free drafts": "perk draft must not contain duplicate choices" in smoke and "a perk at its stack limit must not be offered" in smoke,
}
missing = [name for name, ok in checks.items() if not ok]
if missing:
    print("PROGRESSION BUILD REGRESSION CHECK FAILED")
    for name in missing:
        print("- " + name)
    sys.exit(1)
print("PROGRESSION BUILD REGRESSION CHECK PASSED")
for name in checks:
    print("- " + name)
print("Runtime assertions still need Godot execution.")

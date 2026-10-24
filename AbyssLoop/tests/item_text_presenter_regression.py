#!/usr/bin/env python3
"""Static regression checks for the pure equipment text presenter."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
presenter = (ROOT / "scripts/ui/item_text_presenter.gd").read_text(encoding="utf-8")
checks = {
    "UI preloads the dedicated item presenter": 'preload("res://scripts/ui/item_text_presenter.gd")' in ui,
    "item bonus formatting delegates to presenter": "return ItemTextPresenterScript.format_item_bonus(item)" in ui,
    "value list formatting delegates to presenter": "return ItemTextPresenterScript.format_value_list(values)" in ui,
    "all equipment bonus fields remain represented": all(k in presenter for k in ("attack", "defense", "hp", "speed", "crit", "kill_heal", "tile_scrap", "event_heal", "reward_bonus", "tile_spawn_bonus", "bleed_chance", "bleed_damage", "barrier_on_encounter")),
    "empty bonus output remains explicit": '"без бонусов"' in presenter,
    "item comparison wording and thresholds are centralized": all(token in presenter for token in ("format_item_comparison", '"новый слот"', 'delta > 0.05', 'delta < -0.05', '"примерно равно "')) and "ItemTextPresenterScript.format_item_comparison(true, delta)" in ui,
    "loadout synergy/set text and effect descriptions are centralized": all(token in presenter for token in ("format_loadout_synergy_preview", '"active_synergies"', '"active_sets"', 'Эффект: ', '"Синергия до:')) and "ItemTextPresenterScript.format_loadout_synergy_preview(current_stats, candidate_stats, InventorySystemScript.SYNERGY_DEFS)" in ui,
    "presenter only formats values and does not mutate game state": all(k not in presenter for k in ("GameState.", "inventory_system.", "queue_free(", "append_array(")),
}
missing = [name for name, ok in checks.items() if not ok]
print("ITEM TEXT PRESENTER REGRESSION " + ("FAILED" if missing else "PASSED"))
for name, ok in checks.items():
    print(("[FAIL] " if not ok else "[PASS] ") + name)
sys.exit(1 if missing else 0)

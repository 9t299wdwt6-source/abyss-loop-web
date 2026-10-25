"""Stage 76 source guards: contextual biome loot and tactical hand exchange."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
loot = (ROOT / "scripts/systems/loot_system.gd").read_text(encoding="utf-8")
tile = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
presenter = (ROOT / "scripts/ui/item_text_presenter.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
audit = (ROOT / "tools/content_v1_audit.py").read_text(encoding="utf-8")

biomes = {
    "spore": "spore_bane",
    "crystal": "prism_sunder",
    "bone": "bone_splitter",
    "echo": "echo_cutter",
}

checks = {
    "four existing stable affixes grant matching biome damage and trophy bonuses": all(
        f'"{affix}"' in inventory and f'"{biome}_damage_bonus": 0.08' in inventory and f'"{biome}_trophy_bonus": 0.06' in inventory
        for biome, affix in biomes.items()
    ),
    "biome trophy bonuses have bounded aggregation caps and are part of recognized stats": all(
        f'"{biome}_trophy_bonus": {{"min": 0.0, "max": 0.12}}' in inventory and f'"{biome}_trophy_bonus"' in inventory[inventory.find("func _numeric_stat_keys"):]
        for biome in biomes
    ),
    "affix descriptions communicate the six percentage-point reward correctly": all(
        f'"{affix}"' in inventory and "+6 п.п. к шансу их трофея" in inventory[inventory.find(f'"{affix}"'):inventory.find(f'"{affix}"') + 250]
        for affix in biomes.values()
    ),
    "equipped contextual stats are derived from equipped loadout, not backpack contents": 'for trophy_biome in ["spore", "crystal", "bone", "echo"]' in manager and 'equipment_stats.get(trophy_biome + "_trophy_bonus", 0.0)' in manager,
    "victory uses defeated enemy biome to choose only its matching affix": 'var defeated_biome := str(defeated_enemy.get("biome_tag", ""))' in manager and 'hero.get("equipped_" + defeated_biome + "_trophy_bonus", 0.0)' in manager and 'roll_biome_trophy(defeated_enemy' in manager,
    "trophy chance formula caps global and biome-specific bonuses and leaves bosses guaranteed": all(x in loot for x in ('clampf(trophy_find_bonus, 0.0, 0.25)', 'clampf(biome_specific_bonus, 0.0, 0.12)', 'if is_boss:', 'chance = 1.0', 'return chance', 'return clampf(chance, 0.0, 0.96)')),
    "landscape focus raises only the matching biome trophy chance": 'active_tile_ids.has(str(definition.get("tile_id", "")))' in loot and 'chance = minf(0.96, chance + 0.22)' in loot,
    "item text displays biome-specific trophy chance": 'шанс трофея биома %s +%d п.п.' in presenter and 'trophy_value > 0.0' in presenter,
    "save validation rejects out-of-range contextual trophy stats": '"spore_trophy_bonus", "crystal_trophy_bonus", "bone_trophy_bonus", "echo_trophy_bonus"' in save and 'numeric_value > 0.12' in save,
    "tile draft can exclude a specific card while preserving old caller compatibility": 'func draw_tile(rng: RandomNumberGenerator, unlock_rift: bool, excluded_tile_ids: Array = [])' in tile and 'if not excluded_tile_ids.has(str(choice_value))' in tile,
    "hand exchange requires active run, valid card, crystal and one exchange per loop": all(x in manager for x in ('func get_tile_exchange_preview(hand_index: int)', 'if not active:', 'run_ledger.get("last_tile_exchange_loop", -1)) == loop_count', 'run_ledger.get("crystals", 0)) < 1', 'func exchange_tile(hand_index: int)')),
    "hand exchange is blocked during combat, event, perk and pending settlement": 'if not enemy.is_empty() or not pending_event.is_empty() or pending_perk_count > 0:' in manager and 'if not pending_end_outcome.is_empty():' in manager[manager.find('func get_tile_exchange_preview'):manager.find('func exchange_tile')],
    "exchange excludes the old card and updates its loop marker only once": 'draw_tile(run_rng, unlock_rare, [old_tile_id])' in manager and 'run_ledger["last_tile_exchange_loop"] = loop_count' in manager,
    "failed persistence rolls back hand, ledger, RNG and event history": all(x in manager for x in ('var previous_hand := tile_hand.duplicate(true)', 'var previous_rng_state := run_rng.state', 'var previous_event_log := event_log.duplicate(true)', 'if not save_run_snapshot():', 'tile_hand = previous_hand', 'run_rng.state = previous_rng_state', 'event_log = previous_event_log')),
    "loop exchange marker is validated and old saves remain optional": 'if ledger.has("last_tile_exchange_loop"):' in save and 'ledger["last_tile_exchange_loop"]' in manager,
    "UI exposes redraw reason, live drop/rarity forecast, and wires the button callback": all(x in ui for x in ('ПЕРЕПИСАТЬ КАРТУ · 1 КРИСТАЛЛ', 'Callable(self, "_on_exchange_selected_tile")', 'get_tile_exchange_preview(selected_tile_hand_index)', 'loot_preparation_label.text = preparation_text + "\\n" + _format_live_loot_forecast()', 'func _format_live_loot_forecast(detailed: bool = false) -> String:', 'func _on_exchange_selected_tile()')),
    "content audit accepts the new stat keys while preserving stable IDs": all(f'"{biome}_trophy_bonus"' in audit for biome in biomes),
    "Godot smoke describes contextual trophies and card exchange constraints": all(x in smoke for x in ('biome affixes must add trophy chance only through equipped gear stats', 'card redraw must exclude the selected tile ID', 'card exchange must be limited to once per loop', 'card exchange must not allow spending a missing crystal')),
}

failed = [label for label, passed in checks.items() if not passed]
for label, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {label}")
if failed:
    print("STAGE 76 REGRESSION FAILED: " + "; ".join(failed))
    sys.exit(1)
print(f"STAGE 76 REGRESSION PASSED: {len(checks)}/{len(checks)} source guards")
print("Source-level only; Godot compile, runtime, browser export and visual acceptance are separate gates.")

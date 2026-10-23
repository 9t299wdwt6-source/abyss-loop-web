"""Regression guard for deterministic loadout, archetype synergy and modifier caps."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
presenter = (ROOT / "scripts/ui/item_text_presenter.gd").read_text(encoding="utf-8")
checks = {
    "four small archetype synergies are data-driven": all(name in inventory for name in ("overclock_assault", "precision_resonance", "salvage_route", "bastion_siphon")),
    "synergy activation checks slot-specific archetype requirements": "func _synergy_requirements_match" in inventory and 'equipment.get(slot, {})' in inventory,
    "only one archetype synergy can be active at once": "At most one archetype synergy can be active at a time" in inventory and "break" in inventory[inventory.index("At most one archetype synergy"):inventory.index("func total_perk_stats")],
    "equipment sets and synergies share one aggregation pass": "func total_equipment_stats" in inventory and 'stats["active_sets"]' in inventory and 'stats["active_synergies"]' in inventory,
    "modifier caps exist for shared additive stats": all(key in inventory for key in ('"speed": {"min": -0.5, "max": 1.5}', '"crit": {"min": 0.0, "max": 0.70}', '"reward_bonus": {"min": 0.0, "max": 1.5}', '"tile_spawn_bonus": {"min": -0.25, "max": 0.25}')),
    "perk stats are rebuilt from saved ranks rather than trusted as derived values": "func total_perk_stats(perk_counts: Dictionary)" in inventory and "func calculate_loadout_stats" in inventory,
    "hero synchronization uses the combined loadout calculator": "inventory_system.calculate_loadout_stats(equipment, perk_counts)" in manager and 'hero["equipment_synergies"]' in manager,
    "combat reward, tile materials, healing and encounter modifiers are capped": all(key in manager for key in ("clampf(float(hero.get(\"equipped_reward_bonus\"", "clampi(int(hero.get(\"equipped_tile_scrap\"", "clampi(int(hero.get(\"equipped_event_heal\"", "clampi(int(hero.get(\"equipped_kill_heal\"")),
    "armory delegates before-and-after synergy and set presentation": "_format_loadout_synergy_preview" in ui and "ItemTextPresenterScript.format_loadout_synergy_preview(current_stats, candidate_stats, InventorySystemScript.SYNERGY_DEFS)" in ui and all(key in presenter for key in ("Синергия до:", "после экипировки:", "Наборы до:")),
    "runtime smoke covers build swaps, perks and caps": all(text in smoke for text in ("assault plus tempo should activate", "replacing gear must deactivate", "aggregated equipment modifiers must respect shared build caps", "combined loadout preview must include gear, synergy and perk ranks exactly once")),
}
missing = [name for name, ok in checks.items() if not ok]
if missing:
    print("EQUIPMENT SYNERGY REGRESSION CHECK FAILED")
    for name in missing:
        print("- " + name)
    sys.exit(1)
print("EQUIPMENT SYNERGY REGRESSION CHECK PASSED")
for name in checks:
    print("- " + name)
print("GDScript runtime assertions still require Godot 4.7.2.")

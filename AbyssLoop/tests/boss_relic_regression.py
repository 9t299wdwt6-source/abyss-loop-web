"""Regression guards for boss-specific item drops and rarity progression."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
presenter = (ROOT / "scripts/ui/item_text_presenter.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "Warden drops a named weapon/armor pair from Vanguard": all(token in inventory for token in ('"warden_edge"', '"warden_shell"', '"set_id": "vanguard"')),
    "Harvester drops a named weapon/core pair from Resonance": all(token in inventory for token in ('"harvester_needle"', '"harvester_heart"', '"set_id": "resonance"')),
    "boss relics retain unique identity, rank and source metadata": all(token in inventory for token in ('"unique_id"', '"is_boss_relic": true', '"source_enemy_id"', '"source_enemy_name"', 'func roll_boss_item')),
    "boss relics scale with expedition rank inside bounded stat limits": all(token in inventory for token in ('var rank_bonus := mini(5', 'minf(0.20', 'minf(0.5', 'minf(1.5')),
    "boss victories prefer named relics with a generic fallback": "inventory_system.roll_boss_item(defeated_enemy" in manager and "if item.is_empty():" in manager and 'not bool(item.get("is_boss_relic", false))' in manager,
    "elite/boss gear has distinct upgrade and salvage tiers": all(token in inventory for token in ('"Элитная":', '"Боссовая":', 'rarity_multiplier = 1.45', 'rarity_multiplier = 2.0', 'rarity_scrap = 7', 'rarity_scrap = 14', 'rarity_crystals = 3')),
    "item details show bleed and opening barrier stats": all(token in presenter for token in ("bleed_chance", "bleed_damage", "barrier_on_encounter")),
    "armory shows the boss source and matching set": "Реликвия босса:" in ui and 'item.get("source_enemy_name"' in ui,
    "Godot smoke covers boss drops and all salvage tiers": all(token in smoke for token in ("warden_relic", "harvester_relic", "elite_salvage", "boss_salvage")),
}
failed = [label for label, ok in checks.items() if not ok]
for label, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
if failed:
    print("BOSS RELIC REGRESSION FAILED: " + ", ".join(failed))
    sys.exit(1)
print(f"BOSS RELIC REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Source guards only; Godot smoke test remains the runtime validation.")

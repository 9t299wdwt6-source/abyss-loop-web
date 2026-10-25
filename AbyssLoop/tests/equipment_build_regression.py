"""Static regression guard for item archetypes, active set bonuses and safe equipment data."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "slot-specific item archetypes are defined": all(name in inventory for name in ("assault", "precision", "siphon", "bastion", "scavenger", "field_medic", "tempo", "resonance", "pathfinder")),
    "two-piece set bonuses are data-driven": all(name in inventory for name in ('"vanguard"', '"scavenger"', '"resonance"', '"threshold": 2', '"effects"')),
    "comparison score includes utility effects": "func item_power" in inventory and all(key in inventory for key in ("kill_heal", "tile_scrap", "event_heal", "reward_bonus", "tile_spawn_bonus")),
    "rare and epic drops have a slot-specific data-driven affix pool": "const ITEM_AFFIXES" in inventory and all(key in inventory for key in ('"affix_ids"', '"affix_names"', '"affix_description"', "func apply_random_affixes")) and '"Модификаторы экипировки"' in (ROOT / "tools/content_v1_audit.py").read_text(encoding="utf-8"),
    "rarity affixes alter actual equipment stats and show in the armory": "var delta_value: Variant = stats[stat_key_value]" in inventory and 'result["power"] = item_power(result)' in inventory and "Модификаторы предмета:" in ui,
    "set effects are applied centrally": "func total_equipment_stats" in inventory and "stats[effect_key] = stats.get(effect_key, 0) + effects[effect_key_value]" in inventory,
    "combat and event traits affect gameplay": all(s in manager for s in ('equipped_kill_heal', 'equipped_tile_scrap', 'equipped_event_heal', 'equipped_reward_bonus', 'equipped_tile_spawn_bonus')),
    "armory compares candidates with current gear": "func _format_item_comparison" in ui and "inventory_system.item_power(item) - inventory_system.item_power(current)" in ui,
    "save validation bounds new numerical properties": "func _validate_item" in save and all(key in save for key in ('"tile_spawn_bonus"', '"reward_bonus"', 'is_finite(numeric_value)')),
    "runtime smoke covers item rolls and set bonuses": "two-piece vanguard set must apply actual stats" in smoke and "rolled equipment must have a gameplay archetype" in smoke,
}
missing = [name for name, ok in checks.items() if not ok]
if missing:
    print("EQUIPMENT BUILD REGRESSION CHECK FAILED")
    for name in missing:
        print("- " + name)
    sys.exit(1)
print("EQUIPMENT BUILD REGRESSION CHECK PASSED")
for name in checks:
    print("- " + name)
print("Runtime assertions in smoke_test.gd still require Godot execution.")

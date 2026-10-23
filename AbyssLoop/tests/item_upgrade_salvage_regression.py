"""Static guards for Prototype 41 gear upgrades and safe item recycling."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
project = (ROOT / "project.godot").read_text(encoding="utf-8")
checks = {
    "items have a separate bounded upgrade level": "const MAX_UPGRADE_LEVEL := 10" in inventory and '"upgrade_level": 0' in inventory,
    "upgrade prices scale with rank, prior upgrades and rarity": all(token in inventory for token in ("func get_upgrade_cost", "power_tier", '"Редкий"', '"Эпический"', "scrap_cost", "crystal_cost")),
    "preview improves the appropriate stats per slot": all(token in inventory for token in ('"weapon":', '"armor":', '"core":', 'upgraded["attack"]', 'upgraded["defense"]', 'upgraded["hp"]', 'upgraded["speed"]', 'upgraded["crit"]')),
    "upgrade keeps original ID and other item fields by deep-copying without reroll": 'var upgraded := item.duplicate(true)' in inventory and 'upgraded["upgrade_level"] = next_level' in inventory and 'upgraded["power"] = item_power(upgraded)' in inventory,
    "salvage rewards are deterministic and account for rarity and upgrade level": "func get_salvage_reward" in inventory and "rank * 5" in inventory and "upgrade_level * 7" in inventory and '"Эпический"' in inventory,
    "authoritative upgrade rejects active expeditions and insufficient resources": "func upgrade_armory_item(item_id: String) -> Dictionary:" in state and "if has_saved_expedition():" in state and "if scrap < scrap_cost or crystals < crystal_cost:" in state,
    "upgrading syncs the armory item and an equipped copy with the same ID": 'armory[item_index] = upgraded.duplicate(true)' in state and 'str(equipped_value.get("id", "")) == item_id' in state and 'loadout[slot] = upgraded.duplicate(true)' in state,
    "upgrade transaction rolls back costs and both inventories if saving fails": all(token in state for token in ("old_scrap := scrap", "old_crystals := crystals", "old_armory: Array = armory.duplicate(true)", "old_loadout: Dictionary = loadout.duplicate(true)", "if not save_now():", "armory = old_armory", "loadout = old_loadout")),
    "equipped gear cannot be salvaged in the authoritative state layer": "func is_item_equipped(item_id: String) -> bool:" in state and "if is_item_equipped(item_id):" in state and "Экипировку нельзя разобрать" in state,
    "salvage transaction returns rewards once and rolls back if save fails": "armory.remove_at(item_index)" in state and 'scrap += int(reward.get("scrap", 0))' in state and 'crystals += int(reward.get("crystals", 0))' in state and "Разбор и выдача ресурсов отменены" in state,
    "legacy save items without upgrade_level remain valid while new level is bounded": '"upgrade_level"' in save and 'if item.has("upgrade_level") and int(item.get("upgrade_level", 0)) > 10:' in save and 'if item.has(stat_key) and (not _is_non_negative_integer(item[stat_key])' in save,
    "UI exposes item details and explicit before/after upgrade preview and costs": "func _open_armory_item(item_id: String) -> void:" in ui and "preview_upgrade_item(item)" in ui and "После улучшения: %s" in ui and "upgrade_text" in ui and "GameState.scrap" in ui and "GameState.crystals" in ui,
    "salvage is a two-step confirmation and blocks equipped items in UI": "func _request_salvage_item(item_id: String) -> void:" in ui and '"confirm_salvage"' in ui and "GameState.is_item_equipped(item_id)" in ui and "Перед разбором появится дополнительное подтверждение." in ui,
    "runtime smoke covers weapon, armor, core, rarity, cap and preserved affixes": all(token in smoke for token in ("weapon_fixture", "upgraded_weapon", "rare_fixture", "armor_fixture", "core_fixture", "maxed_item", "epic_salvage", "set_id", "bleed_chance")),
    "new build identifies itself as version 0.61.0 without changing profile name": 'config/name="Abyss Loop"' in project and 'config/version="0.61.0"' in project,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    print("ITEM UPGRADE/SALVAGE REGRESSION FAILED: " + ", ".join(failed))
    sys.exit(1)
print(f"ITEM UPGRADE/SALVAGE REGRESSION PASSED: {len(checks)} checks")
print("Source guards only; GDScript save/UI operations still require Godot 4.7.2 runtime tests.")

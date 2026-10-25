"""Prototype 61 mechanics-pass source guards; deliberately not an engine/browser test."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
tiles = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
enemies = (ROOT / "scripts/systems/enemy_system.gd").read_text(encoding="utf-8")
combat = (ROOT / "scripts/systems/combat_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
saves = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
route_view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
item_text = (ROOT / "scripts/ui/item_text_presenter.gd").read_text(encoding="utf-8")

checks = {
    "lifesteal and phase-dodge are real loadout stats with caps and item-power weight": all(token in inventory for token in ('"lifesteal": {"min": 0.0, "max": 0.25}', '"dodge_chance": {"min": 0.0, "max": 0.25}', '"lifesteal", "dodge_chance"', '"id": "leech"', '"id": "phaseweave"', '"phasebound"', '"living_phase"', '"lifesteal"')),
    "weapon, armor and core upgrades can improve their relevant combat stats": all(token in inventory for token in ('upgraded["lifesteal"]', 'upgraded["dodge_chance"]', 'item["power"] = item_power(item)')),
    "secret rewards include distinct named relics using the new combat mechanics": all(token in inventory for token in ('"prism_heart"', '"echo_veil"', '"rootwatch_mantle"', '"bone_impulse_edge"', '"lifesteal": 0.0, "dodge_chance": 0.0')),
    "persistent equipment validation bounds the new stats instead of trusting saved numbers": all(token in saves for token in ('"lifesteal", "dodge_chance"', 'numeric_value > 0.25')),
    "combat resolves dodge before damage and communicates the outcome to the caller": all(token in combat for token in ('var dodge_chance := clampf', '"dodged": true', '"dodged": false')),
    "expedition applies healing from dealt damage and skips hit effects after a successful dodge": all(token in manager for token in ('var lifesteal_ratio :=', 'var stolen_health :=', 'enemy_hit.get("dodged", false)', '"dodge_chance"] = clampf')),
    "new road and landscape tiles are registered with explicit placement zones and themed enemy pools": all(token in registry for token in ('"echo_spring"', '"fault_line"', '"spore_garden"', '"crystal_hive"', '"bone_orchard"', '"echo_obelisk"', '"placement_zone": "road"', '"placement_zone": "landscape"', '"enemy_pool": ["echo_wisp"]', '"enemy_pool": ["prism_mite"]', '"enemy_pool": ["bone_warden"]')),
    "tile visits return biome pools and apply non-cosmetic risk, healing and reward effects": all(token in tiles for token in ('"enemy_pool": []', 'result["enemy_pool"] = enemy_pool_value.duplicate(true)', '"echo_spring":', '"fault_line":', '"spore_garden":', '"crystal_hive":', '"bone_orchard":', '"echo_obelisk":', 'result.spawn_bonus = 0.42', 'result.reward_bonus = 0.18')),
    "biome enemies are excluded from ordinary random encounters and can be forced by a tile": all(token in enemies for token in ('preferred_pool: Array = []', 'ContentRegistry.ENEMIES.has(preferred_id)', 'not bool(definition.get("landscape_only", false))', 'create_enemy(loop_count, danger, rng, strength_bonus, preferred_pool)')),
    "road and landscape tile pools propagate through sectors, random events and encounter creation": all(token in manager for token in ('encounter_pool: Array[String] = []', 'effects.get("enemy_pool", [])', 'world_effects.get("enemy_pool", [])', '"enemy_pool": enemy_pool.duplicate(true)', 'event_enemy_pool', 'enemy_pool)')),
    "landscape secrets unlock guaranteed follow-up events and named equipment rewards": all(token in registry for token in ('"secret_prism_echo_found"', '"secret_root_bone_found"', '"prism_echo": {', '"root_bone_memory": {', '"grant_item_id": "prism_heart"', '"grant_item_id": "bone_impulse_edge"')),
    "placement previews and the map renderer can show the new set of tiles": all(token in route_view for token in ('"echo_spring"', '"fault_line"', '"spore_garden"', '"crystal_hive"', '"bone_orchard"', '"echo_obelisk"')) and all(token in item_text for token in ('lifesteal', 'dodge_chance')),
    "equipment archetype combinations now reward deliberate use of added slots": all(token in inventory for token in ('"echo_guard"', '"deep_hunter"', '"quiet_cartography"', '"special_damage_reduction"', '"elite_boss_damage_bonus"')),
    "content validation checks tile pools and secret recipe tile references": all(token in registry for token in ('tile:%s references unknown biome enemy', 'landscape secret recipe references unknown tile', 'landscape secret recipe is missing its discovery flag or title')),
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    print("EQUIPMENT/LANDSCAPE MECHANICS REGRESSION FAILED: " + ", ".join(failed))
    sys.exit(1)
print(f"EQUIPMENT/LANDSCAPE MECHANICS REGRESSION PASSED: {len(checks)}/{len(checks)} source guards")
print("Source-level only. This does not compile GDScript or certify Godot runtime, browser export, balance, or visuals.")

"""Source guards for the player-managed equipment slots, run backpack, and landscape affinities.

These checks deliberately complement rather than replace Godot runtime testing.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
game_state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
saves = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
presenter = (ROOT / "scripts/ui/item_text_presenter.gd").read_text(encoding="utf-8")
audit = (ROOT / "tools/content_v1_audit.py").read_text(encoding="utf-8")

checks = {
    "six typed equipment slots and a bounded twelve-cell run backpack are defined centrally": all(token in inventory for token in ('"weapon", "helmet", "armor", "shield", "amulet", "core"', "const BACKPACK_CAPACITY := 12", "func can_equip_item")),
    "new helmet, shield and amulet types have authored archetypes, upgrades and affix pools": all(token in inventory for token in ('"helmet": [', '"shield": [', '"amulet": [', '"hard_shell_helm"', '"crystal_brace"', '"echo_pendant"', '"helmet":', '"shield",', '"amulet":')),
    "loot and secret relics enter the hand-managed backpack instead of auto-equipping": all(token in manager for token in ('if _store_run_item(item):', 'Предмет в начало рюкзака', 'правый клик — быстро надеть')) and 'Автоматически экипирована' not in manager and 'should_equip(item, current)' not in manager,
    "bag capacity is enforced with FIFO ejection and keeps an ejection ledger for later salvage": all(token in manager for token in ('if bag.size() >= BACKPACK_CAPACITY:', 'bag.pop_back()', 'bag.push_front(item.duplicate(true))', 'last_inventory_evicted_item', 'run_ledger["inventory_ejections"] = ejections')) and 'GameState.register_item(item)' not in manager,
    "equipment swap removes the selected item and does not return displaced run gear to the bag": all(token in manager for token in ('func equip_bag_item(item_id: String)', 'bag.remove_at(item_index)', 'equipment[slot] = candidate.duplicate(true)', 'Старая экипировка не возвращается в рюкзак')) and 'bag.append(displaced)' not in manager,
    "equip and unequip persist snapshots and roll back bag, gear, ledger and eviction feedback on save failure": all(token in manager for token in ('func equip_bag_item', 'func unequip_run_slot', 'func discard_run_bag_item', 'if not save_run_snapshot():', 'bag = old_bag', 'equipment = old_equipment', 'var old_run_ledger: Dictionary = run_ledger.duplicate(true)', 'run_ledger = old_run_ledger')),
    "equipment changes cannot be exploited to heal by repeatedly swapping max-health gear": all(token in manager for token in ('hp_before_change := int(hero.get("hp", 1))', 'hero["hp"] = mini(int(hero.get("max_hp", hp_before_change)), hp_before_change)')),
    "run UI exposes six equipment slots, twelve explicit backpack positions, comparison and manual equip": all(token in ui for token in ('РЮКЗАК · %d/%d', 'func _open_run_backpack()', 'range(manager.BACKPACK_CAPACITY)', r'%02d\nПУСТО', 'func _open_run_backpack_item', 'Надеть в слот', 'Сейчас надето', 'Сравнение силы:', 'format_loadout_synergy_preview(current_stats, candidate_stats, InventorySystemScript.SYNERGY_DEFS)', 'Синергии: %s', 'Комплекты: %s')),
    "equipment and backpack render as separate three-column grids with a bounded scroll area": all(token in ui for token in ('"group": "equipment_grid"', '"group": "backpack_grid"', 'current_grid.columns = 3', 'slots_scroll', 'backpack_has_slot_grids')),
    "backpack supports drag-and-drop, right-click quick equip, and rarity borders": all(token in ui for token in ('InventoryDragButtonScript', 'on_inventory_quick_equip', 'on_inventory_drag_drop', 'rarity_border')) and all(token in (ROOT / "scripts/ui/inventory_drag_button.gd").read_text(encoding="utf-8") for token in ('MOUSE_BUTTON_RIGHT', '_get_drag_data', '_drop_data')),
    "items are not manually discarded; queue overflow owns the run-loss rule": 'Убрать из рюкзака этой экспедиции' not in ui and 'РЮКЗАК ПЕРЕПОЛНЕН' in manager,
    "backpack actions stay in a visible footer and details avoid an empty grid scroll area": all(token in ui for token in ('backpack_footer = VBoxContainer.new()', 'elif kind == "backpack" and backpack_has_slot_grids and backpack_footer != null:', 'if backpack_has_slot_grids:', 'else:\n\t\t\tbackpack_layout.add_child(button_parent)')),
    "backpack panel scrolls its bounded slot list and supports explicit resume": all(token in ui for token in ('kind == "backpack"', 'slots_scroll', 'func _resume_after_backpack', 'manager.set_pause(false)')),
    "legacy and current saves normalize all six slots and cap/validate backpack items": all(token in saves for token in ('"weapon", "helmet", "armor", "shield", "amulet", "core"', 'backpack_value.size() > 12', 'not _validate_item(backpack_item_value)', 'not _validate_item(run_item_value, slot)')),
    "permanent equip and unequip use all six slots with rollback if saving fails": all(token in game_state for token in ('InventorySystemScript.EQUIPMENT_SLOTS.has(slot)', 'var old_loadout: Dictionary = loadout.duplicate(true)', 'if not save_now():')),
    "only gear surviving settlement enters the permanent armory transactionally": all(token in manager for token in ('func _collect_run_items_for_settlement(outcome: String)', 'retained_run_items')) and all(token in game_state for token in ('retained_run_items: Array = []', 'var old_armory: Array = armory.duplicate(true)', 'armory = old_armory')),
    "landscape-affinity relics resolve on their matching field tile and affect visit/enemy/reward modifiers": all(token in inventory for token in ('func get_landscape_affinity_effects', '"crystal_hive"', '"echo_obelisk"', '"spore_garden"', '"bone_orchard"', '"fault_line"')) and all(token in manager for token in ('get_landscape_affinity_effects(equipment', 'landscape_affinity.get("heal"', 'landscape_affinity.get(affinity_resource', 'landscape_affinity.get("enemy_bonus"', 'landscape_affinity.get("reward_bonus"')),
    "affinity metadata is validated and the content registry accepts six slot categories": all(token in saves for token in ('"landscape_affinity", "affinity_name"', '"affinity_effect"')) and '"weapon", "helmet", "armor", "shield", "amulet", "core"' in audit,
    "item text shows risky as well as protective encounter modifiers and landscape links": 'риск встречи +%d%%' in presenter and 'Связь с ландшафтом' in ui,
    "helmet/shield/amulet stats actively interact with elite and boss attacks": all(token in inventory for token in ('"special_damage_reduction": {"min": 0.0, "max": 0.35}', '"elite_boss_damage_bonus": {"min": 0.0, "max": 0.25}', '"echo_guard"', '"deep_hunter"')) and all(token in manager for token in ('player_attack_source["attack"]', 'hero.get("elite_boss_damage_bonus"', 'hero.get("special_damage_reduction"', 'if is_special and special_guard > 0.0')),
    "enemy-specific stats have bounded saved values and appear in item tooltips": all(token in saves for token in ('"special_damage_reduction", "elite_boss_damage_bonus"', 'numeric_value > 0.35', 'numeric_value > 0.25')) and all(token in presenter for token in ('защита от особых атак', 'урон элите и боссам')),
}

failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    print("EQUIPMENT/BACKPACK REGRESSION FAILED: " + "; ".join(failed))
    sys.exit(1)
print(f"EQUIPMENT/BACKPACK REGRESSION PASSED: {len(checks)}/{len(checks)} source guards")
print("Source guards only; GDScript compilation, click flows, save/reload and real balance still require Godot 4.7.2 runtime acceptance.")

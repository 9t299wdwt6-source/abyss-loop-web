"""Stage 82 regression: one equipment instance may exist only once in a run."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
preflight = (ROOT / "tools/release_preflight.py").read_text(encoding="utf-8")
packager = (ROOT / "tools/package_release.py").read_text(encoding="utf-8")
checks = {
    "duplicate backpack IDs are rejected instead of being reported as successful loot": 'if not find_run_item(item_id).is_empty():\n\t\treturn false' in manager,
    "new item insertion checks all equipped slots before evicting an old item": all(token in manager for token in ('func _store_run_item(item: Dictionary, except_equipped_slot: String = "")', 'for slot_value in InventorySystemScript.EQUIPMENT_SLOTS:', 'if equipped_slot == except_equipped_slot:', 'last_inventory_evicted_item.clear()', 'var evicted_value: Variant = bag.pop_back()')),
    "unequipping permits moving its own item but blocks duplicate IDs in other slots": 'var stored: bool = _store_run_item(item_value, slot)' in manager and 'if not find_run_item(item_id).is_empty():\n\t\treturn false' in manager,
    "manual equip refuses an item ID that is already equipped": all(token in manager for token in ('var candidate_id := str(candidate.get("id", ""))', 'if typeof(equipped_value) == TYPE_DICTIONARY and str(equipped_value.get("id", "")) == candidate_id:', 'Этот экземпляр предмета уже экипирован')),
    "snapshot restore validates every equipment slot, ID, and equipment-slot compatibility": all(token in manager for token in ('var imported_equipment: Dictionary', 'var normalized_equipment: Dictionary', 'var seen_equipped_item_ids: Dictionary', 'inventory_system.can_equip_item(candidate, slot)', 'normalized_equipment[slot] = {}')),
    "restored equipment wins over bag copies and duplicate equipped copies are removed": all(token in manager for token in ('var unique_bag: Array = []', 'if seen_equipped_item_ids.has(bag_item_id):', 'bag = unique_bag')),
    "rejected duplicates cannot evict the backpack tail or create ejection dust": all(token in smoke for token in ('bag_size_before_duplicate', 'ejection_count_before_duplicate', 'dust_before_duplicate', 'duplicate backpack item IDs must be rejected', 'a rejected duplicate must not change backpack capacity or ejection rewards')),
    "runtime smoke checks identity uniqueness against currently equipped gear": 'item identity must be unique across equipped slots and backpack' in smoke,
    "loot paths keep using the shared run-inventory insertion gate": manager.count('_store_run_item(item)') >= 3 and 'if _store_run_item(item):' in manager,
    "new Stage 82 audit evidence is mandatory in package preflight": all(token in preflight for token in ('ROADMAP_STATUS_STAGE82_RU.md', 'STAGE82_INVENTORY_IDENTITY_AND_SETTLEMENT_AUDIT_BUILD_REPORT_RU.md', 'tests/stage82_inventory_identity_regression.py', 'tests/stage82_static_test_report.txt')) and all(token in packager for token in ('ROADMAP_STATUS_STAGE82_RU.md', 'STAGE82_INVENTORY_IDENTITY_AND_SETTLEMENT_AUDIT_BUILD_REPORT_RU.md', 'tests/stage82_inventory_identity_regression.py', 'tests/stage82_static_test_report.txt')),
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    raise SystemExit("STAGE 82 INVENTORY IDENTITY REGRESSION FAILED: " + "; ".join(failed))
print(f"STAGE 82 INVENTORY IDENTITY REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Source-level evidence only; Godot restore/drag-drop/save behavior still requires runtime acceptance.")

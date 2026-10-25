"""Stage 79 compatibility guards for migrated backpack/equipment behavior."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
button = (ROOT / "scripts/ui/inventory_drag_button.gd").read_text(encoding="utf-8")
presenter = (ROOT / "scripts/ui/item_text_presenter.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
checks = {
    "the active run backpack remains a fixed 12-slot FIFO queue": "const BACKPACK_CAPACITY := InventorySystemScript.BACKPACK_CAPACITY" in manager and "if bag.size() >= BACKPACK_CAPACITY:" in manager and "bag.pop_back()" in manager and "bag.push_front(item.duplicate(true))" in manager,
    "new snapshots record order version and keep legacy cache empty": '"inventory_order_version": INVENTORY_ORDER_VERSION' in manager and '"field_cache": []' in manager,
    "legacy snapshots combine old bag/cache chronology and migrate to newest-first": all(token in manager for token in ('snapshot.get("inventory_order_version", 1)', "imported_items.append_array(legacy_bag)", "imported_items.append_array(legacy_cache)", "imported_items.reverse()", "field_cache.clear()")),
    "equipping removes the new item from bag and never returns displaced run gear to it": all(token in manager for token in ("func equip_bag_item", "bag.remove_at(item_index)", "equipment[slot] = candidate.duplicate(true)", "Старая экипировка не возвращается в рюкзак")),
    "unequipping returns gear at the front and uses FIFO eviction when full": all(token in manager for token in ("func unequip_run_slot", "_store_run_item(item_value, slot)", "Снят предмет:")),
    "players can reorder inventory and persist the discard order": all(token in manager for token in ("func can_reorder_run_bag_item", "func reorder_run_bag_item", "bag.insert(normalized_target, item)", "save_run_snapshot()")),
    "right-click quick equips and drag/drop targets compatible equipment slots": all(token in button for token in ("MOUSE_BUTTON_RIGHT", "on_inventory_quick_equip", "_get_drag_data", "_can_drop_data", "equipment_slot_target")),
    "UI loads drag controls for inventory grids": "InventoryDragButtonScript" in ui and "configure_inventory_control" in ui,
    "UI explains FIFO behavior and uses only the 12 active backpack cells": all(token in ui for token in ("старейшая вещь в ячейке 12 вытесняется", '"group": "backpack_grid"')) and '"group": "field_cache_grid"' not in ui,
    "empty bag cells are valid drag reorder targets": '"inventory_cell_index": index, "draggable": false' in ui and "can_reorder_inventory_item" in button,
    "drop tiers include a rare relic tier with a lower baseline roll band": all(token in inventory for token in ('"Реликтовый"', "const RARITY_BASE_WEIGHTS", "func get_rarity_distribution", "cumulative_rarity_chance += float(rarity_distribution.get(rarity_name, 0.0))")),
    "cache tiles can roll equipment and successful roll consumes prepared bonuses": all(token in manager for token in ("func _try_cache_equipment_drop", 'get_equipment_drop_chance("cache"', 'if cache_node_found:', 'run_ledger["pending_item_drop_bonus"] = 0.0')),
    "save validator accepts older snapshots but validates explicit ordering versions": all(token in save for token in ('snapshot.has("inventory_order_version")', 'int(inventory_order_version) not in [1, 2]', 'snapshot.get("field_cache", [])')),
    "ejected item ledger is optional for legacy saves, capped at 100, and validates item payloads and unique IDs": all(token in save for token in ('ledger.get("inventory_ejections", [])', 'ejections_value.size() > 100', 'not _validate_item(ejection_value)', 'ejection_ids.has(ejection_id)')),
    "settlement banks only surviving gear, with the backpack kept on safe return and lost on defeat": all(token in manager for token in ('func _collect_run_items_for_settlement(outcome: String)', 'if outcome == "return":', 'retained_run_items := _collect_run_items_for_settlement(outcome)')) and 'Only gear that survived to settlement enters the permanent shelter armory.' in (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8"),
    "equipped item comparison still reports deltas beyond raw power": 'format_stat_comparison(item, current)' in ui and 'static func format_stat_comparison(candidate: Dictionary, current: Dictionary)' in presenter,
    "smoke source explicitly covers FIFO queue behavior": "STAGE79_LOOP_HERO_BACKPACK_QUEUE" in smoke and "last_inventory_evicted_item" in smoke,
    "run drops are not copied into permanent armory until settlement": "GameState.register_item(item)" not in manager and "_collect_run_items_for_settlement(outcome)" in manager and "retained_run_items: Array = []" in (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8"),
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    print("STAGE 79 INVENTORY REGRESSION FAILED: " + "; ".join(failed))
    sys.exit(1)
print(f"STAGE 79 INVENTORY REGRESSION PASSED: {len(checks)}/{len(checks)} source guards")
print("Source-level only; Godot parse/runtime and visual mouse interaction require a Godot 4.7.2 runtime check.")

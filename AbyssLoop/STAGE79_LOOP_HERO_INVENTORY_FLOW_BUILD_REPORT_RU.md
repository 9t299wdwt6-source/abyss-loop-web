# Abyss Loop — Stage 79: Loop Hero-style inventory and equipment flow

**Project version:** `0.61.0` (stable profile identity unchanged)  
**Base:** Stage 78 — Equipment Comparison and Field Cache  
**Status:** source-level candidate; Godot 4.7.2 runtime not verified  
**Main focus:** loot arrival, player-controlled equipment, backpack ordering and overflow.

## Implemented

### Loot acquisition and rarity

- Normal enemy equipment continues to use the shared configured drop chance (`loot_item_chance`, default 18%) with bounded bonuses from encounters and prepared effects.
- Elite equipment uses the configured elite floor (45%). Registered bosses retain their named signature equipment reward. Cache tiles use a separate 35% default chance.
- Item rarity is rolled independently after the item-drop check. Before equipment-based bonuses, the bands are Common 70%, Rare 24%, Epic 5.2%, Relic 0.8%; rare-find bonuses shift the roll upward within a bounded range.
- Successful drops are added to the active expedition backpack. They are not immediately copied to the permanent shelter armory.

### Backpack queue

- The active backpack has exactly 12 cells and uses newest-first order: newly found items enter cell 01; cell 12 is the oldest.
- When full, insertion ejects the oldest item from cell 12, then inserts the new item into cell 01. Ejected items do not remain in the active backpack or permanent armory.
- Ejected item records are kept in a bounded ledger of at most 100 valid, unique item payloads. The ledger exists only as groundwork for a later resource-conversion mechanic; no conversion resource is awarded yet.
- Drag-and-drop changes the queue order, allowing the player to protect valuable loot by moving it toward the newest end before later drops arrive.
- A separate overflow cache has been removed from active UI and active snapshots. Legacy `field_cache` data is accepted during snapshot migration and folded into the new ordering.

### Manual equipment

- Six equipment categories remain: weapon, helmet, armor, shield, amulet and Abyss core.
- Left-clicking an item opens comparison/details. The dedicated equip button manually equips it to its matching slot.
- Right-click provides the quick-equip action. Dragging an item onto an equipment slot performs the same compatible-slot check before equipping.
- Dragging an item to a backpack cell changes its FIFO position. Empty cells can be reorder targets; the queue remains compact, so no holes are stored in the save.
- Replacing a run item does not return the displaced run gear into the backpack, following the Loop Hero-style slot flow. The player chooses whether to replace the current slot item with a newly found item.
- Unequipping inserts the item at the front of the backpack. If the queue is full, the oldest backpack item is ejected under the same FIFO rule.
- Item rarity is visible by border treatment, and item details preserve current stat, set and synergy comparison.

### Settlement and save safety

- Newly dropped items become permanent armory stock only through settlement, not at the moment of loot generation.
- On safe return, surviving backpack items and equipped items can be banked in one transaction. On defeat, only the final equipped loadout is retained; un-equipped backpack loot is lost. Ejected loot is never banked.
- Equip/unequip/reorder operations use save snapshots. If unequip persistence fails, the queue, equipment, hero stats, event log, ejection ledger and last-ejected feedback are rolled back together.
- Snapshot schema remains compatible: missing ordering version is treated as legacy order; old backpack + field-cache chronology is migrated to newest-first; current saves write ordering version 2 and an empty legacy field cache.
- Save validation accepts old ledgers without `inventory_ejections`; if present, the ledger must contain no more than 100 valid, unique item IDs.

## Verification

- Full Python static/regression suite: **105/105 PASS**.
- Equipment/backpack regression: **21/21 source guards PASS**.
- Landscape secret regression: **9/9 source guards PASS**.
- Stage 79 inventory regression: **18/18 source guards PASS**.
- Independent release preflight: **7/7 PASS**; all 110 required handoff files are present and the current static report is complete.
- Final development ZIP is generated with `tools/package_release.py` after the report is finalized. Archive-to-source correspondence, ZIP CRC and the single `AbyssLoop/` top-level folder are checked before handoff.

## Not verified

The environment does not contain Godot 4.7.2. GDScript parsing, editor/import, in-engine smoke, actual mouse drag/right-click behavior, and save/reload runtime behavior are **not claimed as passed**. Browser export/deploy was not run. These checks are reserved for the later integrated acceptance pass, per the development plan.

## Follow-up

Next gameplay step: reconcile the actual item drop / rarity outcomes and add a dedicated base resource for ejected items. Do not award that resource until its conversion rate, cap, and interaction with base upgrades are explicitly implemented and regression-tested.

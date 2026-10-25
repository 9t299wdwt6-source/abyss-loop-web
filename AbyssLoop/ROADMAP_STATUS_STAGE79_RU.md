# Abyss Loop — roadmap status after Stage 79

**Current stage:** Stage 79 — Loop Hero-style inventory/equipment flow.  
**Project version:** `0.61.0`; profile identity and existing save schema versions remain unchanged.  
**Source base:** Stage 78 equipment comparison + overflow-cache build.  
**Static suite:** 105/105 PASS.  
**Godot 4.7.2 runtime:** not available in the development environment; no runtime PASS is claimed.

## Stage 79 complete at source level

- Implemented a 12-cell newest-first backpack. New loot enters cell 01; the oldest item at cell 12 is ejected when the backpack is full.
- Removed the extra 6-cell active-run cache from normal UI and active snapshots. Stage 78 `field_cache` data can still migrate from old saves.
- Preserved manual equipment choice: click for detail/comparison, use the equip action, right-click for quick equip, drag to a matching slot, and drag to reorder the backpack queue.
- Added lower odds for higher rarity, independent from the base chance to receive any item. Existing rates include 18% ordinary, 45% elite floor, 35% cache, and the current named boss-relic reward behavior.
- Removed immediate copies of run loot into the permanent armory. Surviving gear is transferred transactionally at settlement; overflow-ejected items are not banked.
- Added ejection ledger normalization and validation (maximum 100 unique valid item payloads) to support a later resource-conversion stage without awarding resources prematurely.
- Added transaction rollback for unequip when the persistence write fails, including the ejection ledger and feedback state.

## Current behavior contracts

1. **Acquisition:** valid loot enters the backpack queue; rarity is decided separately from the chance of item drop.
2. **Player choice:** no automatic replacement. The player can compare and equip; the compatible slot is enforced.
3. **Queue control:** drag reorder sets which item will be lost first. Newest is front; oldest is back.
4. **Overflow:** the oldest item is removed from the run backpack. It disappears from active inventory; its bounded ledger record is reserved only for future base-resource conversion.
5. **Settlement:** safe return banks surviving backpack contents and equipped items. Defeat banks the final equipped loadout only. No ejected item is retained by the armory.
6. **Compatibility:** saves without `inventory_order_version` migrate from the older bag + field-cache chronology. Current writes use version 2 and empty `field_cache`.

## Next development stages

### Stage 80 — ejected-loot conversion to a base resource
- Define one Abyss-themed resource name, conversion amount and a ceiling.
- Convert ejected item records exactly once during a committed settlement, using rarity and item power without making higher tiers an exploit.
- Keep an id/settlement ledger to prevent duplicate resource awards after save retry/reload.
- Show the resource on the base screen and make it usable for a documented base upgrade; don't change this until the resource path is wired end-to-end.

### Stage 81 — item reward audit and player feedback
- Make the displayed drop chance and realized outcome agree for normal enemies, elites, bosses and caches.
- Show the rarity distribution and bonuses from equipped gear, without exposing hidden RNG values beyond a useful range.
- Add an explicit “oldest item will be lost” confirmation preview when the 12-cell backpack is full, while retaining Loop Hero-style automatic overflow after the drop succeeds.

### Integrated validation after the mechanics pass
- Static regression suite and release preflight.
- Godot 4.7.2 clean import/parse, smoke and save/reload gates.
- Runtime checks for right-click quick equip, drag to compatible/incompatible slot, reorder to first/last cell, a full-bag drop, cache drop, boss loot, and both return and defeat settlement.
- Inspect UI at 1920×1080 and phone/compact sizes. Web export and deployment only in the planned later batch; not per step.

## Evidence boundary

`tests/reports/STATIC_TEST_REPORT.txt` is the current source-level report. It does not prove GDScript compilation or in-game input behavior. Preserve previous build archives. This stage must not be labeled runtime-tested until the exact candidate passes Godot 4.7.2 gates.

# Stage 79 — runtime acceptance checklist (Godot 4.7.2)

Run this checklist on the exact packaged ZIP after extracting `AbyssLoop/` into a clean folder. This document is a checklist, not evidence that runtime checks have passed.

## Import and smoke
- [ ] Open/import with Godot 4.7.2 stable; no parse errors or inferred-Variant warnings promoted to errors.
- [ ] Run `tests/smoke_test.gd`; item queue assertions pass.
- [ ] Start a new expedition and resume an existing Stage 78 save; no lost items or duplicate gear IDs.

## Loot acquisition
- [ ] Defeat an ordinary enemy that does not roll an equipment drop and confirm only the non-equipment rewards appear.
- [ ] Defeat an ordinary enemy that does roll a drop; the new item appears in backpack cell 01 without equipping itself.
- [ ] Defeat an elite and verify its increased drop chance and elite rarity treatment.
- [ ] Defeat a registered boss and verify its named reward enters the backpack without automatically replacing gear.
- [ ] Open a cache tile; verify the cache's independent item-drop chance and the same inventory insertion path.
- [ ] With rarity modifiers off, inspect enough seeded/automated rolls to confirm higher rarity bands are rarer than common items. Do not infer balance from one roll.

## Player-managed gear
- [ ] Left-click an item: item details, current slot and stat comparison appear.
- [ ] Use the equip button: the candidate goes to its matching slot; the old run item is not silently returned to the backpack.
- [ ] Right-click a backpack item: it quick-equips to its compatible slot.
- [ ] Drag an item onto a compatible slot: it equips.
- [ ] Drag an item onto an incompatible slot: placement is rejected and both item positions remain unchanged.
- [ ] Drag an item to cell 01 and cell 12; the stored order updates after save/reload.
- [ ] Unequip an item; it returns to cell 01. If the backpack is full, the old item in cell 12 is ejected and appears in the ejection record only.

## Overflow and settlement
- [ ] Fill 12 backpack cells, then receive one more item: exactly one oldest item disappears, the backpack remains at 12, the new item is in cell 01, and no extra cache stores it.
- [ ] Reload after overflow: the queue order and bounded ejection ledger are preserved.
- [ ] Safe return: remaining backpack gear and equipped gear enter the permanent armory once; ejected items do not.
- [ ] Defeat: the equipped loadout survives per current design; unequipped backpack loot and ejected items do not enter the armory.
- [ ] Simulate/force a save failure for unequip/reorder if a test fixture is available; state and ejection ledger roll back without duplication.
- [ ] Legacy Stage 78 snapshot with bag + field cache migrates to newest-first order and current snapshots write an empty `field_cache`.
- [ ] Invalid ejection ledger (>100 entries, duplicate IDs, or invalid item payload) is rejected by snapshot validation.

## UI and layout
- [ ] Item rarity borders, item name and slot icon/text are distinguishable at 1920×1080 and compact size.
- [ ] The backpack's 12 cells remain visible/scrollable without hiding the close/resume controls.
- [ ] Mouse drag does not activate the button callback accidentally; right-click quick equip doesn't also trigger left-click item details.
- [ ] Keyboard focus remains visible and the panel can be closed/reopened without duplicate overlays.

## Acceptance status
Record the exact ZIP SHA-256, Godot build string, import logs, smoke output and screenshots before promoting any runtime status. Web/browser acceptance is a separate later batch.

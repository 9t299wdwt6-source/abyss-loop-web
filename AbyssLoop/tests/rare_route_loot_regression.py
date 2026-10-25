"""Stage 75: rare road cards prepare meaningful, bounded equipment loot."""
from pathlib import Path
import json, sys
ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
tile = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
presenter = (ROOT / "scripts/ui/item_text_presenter.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
audit = (ROOT / "tools/content_v1_audit.py").read_text(encoding="utf-8")
checks = {
  "lost convoy and hunter marker are explicitly road-only authored cards": all(x in registry and x in tile for x in ('"lost_convoy"', '"hunter_marker"')) and '"placement_zone": "road"' in registry,
  "new cards enter the same weighted rare-draft path only after unlock": all(f'choices.append("{x}")' in tile for x in ("lost_convoy", "hunter_marker")) and 'tile_id in ["rift", "signal", "archive", "nursery", "fault_line", "spore_garden", "crystal_hive", "bone_orchard", "echo_obelisk", "lost_convoy", "hunter_marker"]' in tile,
  "convoy pays materials and arms a bounded rarity bias": 'ledger["pending_item_rarity_bonus"] = next_rarity_bonus' in tile and 'minf(0.18, old_rarity_bonus + 0.12)' in tile,
  "hunter marker arms a bounded drop chance bonus and exposes risk tradeoff": 'ledger["pending_item_drop_bonus"] = next_drop_bonus' in tile and 'minf(0.30, old_drop_bonus + 0.15)' in tile,
  "equipped loadout has a capped rare-find stat and the generated roll consumes it": '"rare_find_bonus": {"min": 0.0, "max": 0.12}' in inventory and 'equipped_rare_find_bonus' in manager and 'inventory_system.roll_item(drop_rng, loop_count, int(hero.level), boss_rarity_bonus)' in manager and 'var boss_rarity_bonus: float = 0.0 if is_boss else effective_rarity_bonus' in manager,
  "rarity bias is optional and capped, leaving unmodified rolls unchanged": 'rarity_bonus: float = 0.0' in inventory and 'func get_rarity_distribution(rarity_bonus: float = 0.0)' in inventory and 'func get_effective_rarity_bonus' in inventory and 'RARITY_BASE_WEIGHTS' in inventory,
  "prepared loot is consumed only after a successful non-boss drop": 'run_ledger["pending_item_rarity_bonus"] = 0.0' in manager and 'run_ledger["pending_item_drop_bonus"] = 0.0' in manager and 'if not is_boss:' in manager,
  "new stat is valid in saved equipment and surfaced in the tooltip": '"rare_find_bonus"' in save and 'шкала редкости находок' in presenter and 'rare_find_bonus' in audit,
  "Godot smoke includes bounds, monotonic rarity and equipped loadout cases": all(x in smoke for x in ("lost convoy rarity preparation must stop at 18 percentage points", "hunter marker drop preparation must be capped at 30 percentage points", "prepared rarity bonus must never reduce the rolled item's rarity", "rare-find modifier must be derived from equipped slots only")),
  "two route formations and three local synergies are registered with meaningful tradeoffs": all(x in registry for x in ('"salvage_route"', '"marked_ambush"', '"convoy_ward"', '"convoy_hunt"', '"marker_snare"'))
}
failed = [label for label, ok in checks.items() if not ok]
for label, ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'}: {label}")
if failed: print("RARE ROUTE LOOT REGRESSION FAILED: " + "; ".join(failed)); sys.exit(1)
print(f"RARE ROUTE LOOT REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Static source checks only; GDScript smoke must run in Godot 4.7.2.")

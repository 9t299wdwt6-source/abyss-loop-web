from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
enemies = (ROOT / "scripts/systems/enemy_system.gd").read_text(encoding="utf-8")
saves = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
presenter = (ROOT / "scripts/ui/item_text_presenter.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "six-slot item stats include general and four biome-specific combat counters": all(f'"{tag}_{suffix}"' in inventory for tag in ("spore", "crystal", "bone", "echo") for suffix in ("damage_bonus", "resistance")) and '"biome_damage_bonus"' in inventory and '"biome_resistance"' in inventory,
    "Abyss Tracker set grants bounded offense, defense and modest reward": '"abyss_tracker"' in inventory and '"biome_damage_bonus": 0.05' in inventory and '"biome_resistance": 0.025' in inventory,
    "rare item affixes create each theme counter in valid equipment slots": all(key in inventory for key in ("spore_bane", "bone_splitter", "prism_sunder", "echo_cutter", "spore_filter", "echo_dampener", "crystal_grounding", "bone_sieve")),
    "themed enemies carry persistent canonical biome tags": all(f'"biome_tag": "{tag}"' in registry for tag in ("spore", "crystal", "bone", "echo")) and '"biome_tag": str(def.get("biome_tag", ""))' in enemies,
    "affinity bonus requires both matching equipped relic and live landscape sector": "get_landscape_combat_bonus" in inventory and 'not active_tile_ids.has(affinity)' in inventory and 'str(affinity_tags.get(affinity, "")) != tag' in inventory,
    "hero attack applies biome and matching-landscape bonus before hit resolution": '_get_biome_stat(enemy, "damage_bonus")' in manager and 'get_landscape_combat_bonus(equipment, _get_current_landscape_tile_ids(), enemy)' in manager and '1.0 + combined_biome_bonus' in manager,
    "biome resistance mitigates matching enemies but does not replace special-attack guard": '_get_biome_stat(fighter, "resistance")' in manager and '1.0 - biome_resistance' in manager and 'special_guard' in manager,
    "saved item counters are bounded during validation": all(key in saves for key in ("biome_damage_bonus", "spore_damage_bonus", "crystal_resistance", "echo_resistance")) and 'numeric_value > 0.20' in saves and 'numeric_value > 0.25' in saves,
    "item text explains all themed counters and biome-conditioned relic bonuses": all(x in presenter for x in ("урон существам ландшафта", "защита от существ ландшафта", 'for biome_tag in ["spore", "crystal", "bone", "echo"]', 'biome_tag + "_damage_bonus"', 'biome_tag + "_resistance"')),
    "runtime smoke covers contextual bonus positive and negative cases": "matching crystal relic and landscape must add contextual combat damage" in smoke and "landscape affinity must not activate away from its named tile" in smoke,
    "new landscape pairings offer distinct strategic risk/reward tradeoffs": all(key in registry for key in ("spore_hunt", "crystal_snare", "bone_archive", "echo_ward")),
}
failed=[k for k,v in checks.items() if not v]
for name, passed in checks.items(): print(("PASS" if passed else "FAIL") + ": " + name)
if failed:
    print("BIOME EQUIPMENT INTERACTION REGRESSION FAILED: " + ", ".join(failed)); sys.exit(1)
print(f"BIOME EQUIPMENT INTERACTION REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Source-level only; Godot runtime and balance remain separate validation gates.")

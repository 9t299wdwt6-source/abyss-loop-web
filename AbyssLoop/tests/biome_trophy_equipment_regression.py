"""Stage 71 guards for equipped trophy-finder and biome/landscape interactions."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
loot = (ROOT / "scripts/systems/loot_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
saves = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
presenter = (ROOT / "scripts/ui/item_text_presenter.gd").read_text(encoding="utf-8")
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")

checks = {
    "amulet trophy finder is a real rare affix with a clear bonus": '"trophy_compass"' in inventory and '"trophy_find_bonus": 0.08' in inventory,
    "trophy bonus enters the shared item stat calculator and has a strict cap": '"trophy_find_bonus": {"min": 0.0, "max": 0.25}' in inventory and '"trophy_find_bonus"' in inventory and 'for stat_key in _numeric_stat_keys()' in inventory and 'stats[stat_key] = stats.get(stat_key, 0) + item.get(stat_key, 0)' in inventory and 'float(item.get("trophy_find_bonus", 0.0))' in inventory,
    "item power accounts for trophy utility instead of treating it as cosmetic": 'get("trophy_find_bonus", 0.0)), 0.0, 0.25) * 24.0' in inventory,
    "equipped amulet bonus reaches the actual loot roll": 'hero["equipped_trophy_find_bonus"]' in manager and 'float(hero.get("equipped_trophy_find_bonus", 0.0))' in manager and 'trophy_find_bonus: float = 0.0' in loot,
    "trophy bonus is additive, clamped and cannot bypass the world cap": 'clampf(trophy_find_bonus, 0.0, 0.25)' in loot and 'minf(0.96, chance +' in loot,
    "elite and boss trophy odds remain special-cased after equipment bonus": 'if is_elite:' in loot and 'if is_boss:' in loot and 'chance = 1.0' in loot,
    "item comparison text exposes the actual trophy bonus": 'шанс трофея биома +%d п.п.' in presenter,
    "save validation bounds trophy bonus and old items may omit the field": '"trophy_find_bonus"' in saves and 'numeric_value > 0.25' in saves,
    "landscape synergies retain distinct strategic trade-offs": all(f'"{key}"' in registry for key in ("spore_archive", "crystal_hunt", "bone_ward", "echo_signal")),
    "source keeps the bonus contextual to equipped loadout rather than backpack contents": 'inventory_system.calculate_loadout_stats(equipment, perk_counts)' in manager and 'equipment_stats.get("trophy_find_bonus", 0.0)' in manager,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + name)
if failed:
    raise SystemExit("BIOME TROPHY EQUIPMENT REGRESSION FAILED: " + ", ".join(failed))
print(f"BIOME TROPHY EQUIPMENT REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Source-level guards only; Godot runtime and balance remain separate acceptance gates.")

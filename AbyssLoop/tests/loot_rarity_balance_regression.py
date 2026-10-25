"""Stage 81 regression: consistent source odds and weighted rarity quality."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
loot = (ROOT / "scripts/systems/loot_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "base rarity weights match 70/24/5.2/0.8 percent": all(x in inventory for x in ('"Обычный": 0.70', '"Редкий": 0.24', '"Эпический": 0.052', '"Реликтовый": 0.008')),
    "one weighted distribution powers item rolls rather than additive uniform bias": all(x in inventory for x in ("func get_rarity_distribution", "func roll_rarity", "var rarity := roll_rarity(rng, rarity_bonus)", "cumulative_rarity_chance += float(rarity_distribution.get(rarity_name, 0.0))")) and "rng.randf() + clampf(rarity_bonus" not in inventory,
    "rarity odds normalize and retain ordered tier list": all(x in inventory for x in ("const RARITY_ORDER", "total_weight += float(weights.get(rarity_name, 0.0))", "distribution[rarity_name] = float(weights.get(rarity_name, 0.0)) / total_weight")),
    "rarity bonus is clamped and cannot flatten hierarchy at its cap": all(x in inventory for x in ("clampf(equipped_bonus, 0.0, 0.12)", "clampf(prepared_bonus, 0.0, 0.18)", "clampf(source_bonus, 0.0, 0.06)", "0.0, 0.25")),
    "source-specific drop chance is centralized for enemy, elite, boss and cache": all(x in loot for x in ('func get_equipment_drop_chance', 'source == "boss"', '"cache_item_drop_chance", 0.35', '"elite_item_chance", 0.45', '"loot_item_chance", 0.18')),
    "elite and cache gain bounded quality bias without being guaranteed top quality": all(x in loot for x in ('"enemy": 0.0', '"elite": 0.04', '"cache": 0.02', 'func get_source_rarity_bonus')),
    "both combat and cache use the same drop probability helper": 'loot_system.get_equipment_drop_chance("cache"' in manager and "loot_system.get_equipment_drop_chance(drop_source" in manager,
    "both paths use common rarity-distribution weighting with gear and prepared bonuses": 'inventory_system.get_effective_rarity_bonus(equipped_rarity_bonus, pending_rarity_bonus, loot_system.get_source_rarity_bonus("cache"))' in manager and "var source_quality_bonus" in manager and "inventory_system.get_rarity_distribution" in manager,
    "elite keeps rolled rarity tier and applies only a separate stat premium": 'Трофей элиты' in manager and 'item["rarity"] = "Элитная"' not in manager and 'ceil(float(elite_stat_value) * 1.10)' in manager,
    "boss guaranteed named loot is kept separate from ordinary rarity distribution": 'if is_boss:' in manager and 'гарантированная награда босса; обычная шкала редкости для неё не используется' in manager.lower(),
    "failed rolls disclose source drop probability without pretending rarity rolled": 'Шанс редкости не бросался, поскольку предмета нет' in manager,
    "successful item feedback displays its conditional rarity probability": 'шанс качества «%s» при текущей подготовке' in manager.lower() and 'шанс этого качества при текущей подготовке' in manager.lower(),
    "UI displays actual source odds and conditional quality forecast": all(x in ui for x in ('func _format_live_loot_forecast', 'get_equipment_drop_chance("enemy"', 'get_equipment_drop_chance("elite"', 'get_equipment_drop_chance("cache"', 'КАЧЕСТВО (если предмет выпал)')),
    "runtime smoke covers normalized and monotonically improved quality odds": all(x in smoke for x in ('rarity distribution must sum to one', 'relic chance must remain below epic chance at maximum bias', 'equipment drop probabilities must use source-specific weights')),
    "old prepared bonuses remain capped and are consumed only on successful drops": all(x in manager for x in ('run_ledger["pending_item_rarity_bonus"] = 0.0', 'run_ledger["pending_item_drop_bonus"] = 0.0', 'if not is_boss:')),
    "all existing boss relic and inventory APIs remain available": all(x in inventory for x in ('func roll_boss_item', 'func apply_random_affixes', 'func can_equip_item', 'func item_power')),
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    print("LOOT RARITY BALANCE REGRESSION FAILED: " + "; ".join(failed))
    raise SystemExit(1)
print(f"LOOT RARITY BALANCE REGRESSION PASSED: {len(checks)}/{len(checks)} source checks")
print("Source-level only: actual seeded draws, GDScript parsing, UI, and balance distribution still require Godot 4.7.2 runtime acceptance.")

"""Source guards for equipment-to-enemy interactions and deliberate multi-slot builds."""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
saves = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
presenter = (ROOT / "scripts/ui/item_text_presenter.gd").read_text(encoding="utf-8")
manifest = json.loads((ROOT / "tests/fixtures/content_v1_stable_ids.json").read_text(encoding="utf-8"))

checks = {
    "special-attack mitigation and elite/boss damage have explicit caps": all(token in inventory for token in (
        '"special_damage_reduction": {"min": 0.0, "max": 0.35}',
        '"elite_boss_damage_bonus": {"min": 0.0, "max": 0.25}',
    )),
    "new helmet, shield and amulet archetypes provide those stats": all(token in inventory for token in (
        '"id": "observer"', '"special_damage_reduction": 0.07',
        '"id": "deep_sight"', '"elite_boss_damage_bonus": 0.06',
        '"id": "reflector"', '"id": "event_reader"',
    )),
    "gear stats are included in central aggregation and item power": all(token in inventory for token in (
        '"special_damage_reduction", "elite_boss_damage_bonus"',
        'score += clampf(float(item.get("special_damage_reduction", 0.0))',
        'score += clampf(float(item.get("elite_boss_damage_bonus", 0.0))',
    )),
    "the derived hero stats are recalculated from current equipment": all(token in manager for token in (
        'hero["special_damage_reduction"] = clampf(float(equipment_stats.get("special_damage_reduction", 0.0))',
        'hero["elite_boss_damage_bonus"] = clampf(float(equipment_stats.get("elite_boss_damage_bonus", 0.0))',
    )),
    "hero attacks against elite and boss targets receive a bounded damage bonus": all(token in manager for token in (
        'var player_attack_source: Dictionary = hero.duplicate(true)',
        'hero.get("elite_boss_damage_bonus", 0.0)',
        'bool(enemy.get("is_elite", false)) or bool(enemy.get("is_boss", false))',
        'combat_system.perform_attack(player_attack_source, enemy',
    )),
    "special equipment defense is applied only to elite/boss special attacks after their multipliers": all(token in manager for token in (
        'var is_special := (is_boss_attacker or is_elite_attacker)',
        'var special_guard := clampf(float(hero.get("special_damage_reduction", 0.0))',
        'if is_special and special_guard > 0.0:',
        'attack_source["attack"] = float(attack_source.get("attack", 1.0)) * (1.0 - special_guard)',
    )),
    "cross-slot synergies reward purposeful helmet/shield/amulet combinations": all(token in inventory for token in (
        '"echo_guard"', '"deep_hunter"', '"quiet_cartography"',
        '"requirements": {"helmet": ["observer"], "shield": ["reflector"]}',
        '"requirements": {"helmet": ["deep_sight"], "amulet": ["event_reader"]}',
        '"requirements": {"helmet": ["echo_hood"], "amulet": ["wayfinder"]}',
    )),
    "upgrade steps can improve the newly introduced combat-specific stats": all(token in inventory for token in (
        'upgraded["special_damage_reduction"] = minf',
        'upgraded["elite_boss_damage_bonus"] = minf',
    )),
    "save validation rejects out-of-range values from old or edited item data": all(token in saves for token in (
        '"special_damage_reduction", "elite_boss_damage_bonus"',
        'numeric_value > 0.35', 'numeric_value > 0.25',
    )),
    "new affix stable IDs are recorded in the reviewed content manifest": all(
        item_id in manifest.get("Модификаторы экипировки", [])
        for item_id in ("boss_lens", "bossproof_ridge", "phase_catching_brace")
    ),
    "item detail formatting explains both elite offense and special-attack protection": all(token in presenter for token in (
        'защита от особых атак', 'урон элите и боссам +%d%%',
    )),
}

failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    print("EQUIPMENT/ENEMY INTERACTION REGRESSION FAILED: " + "; ".join(failed))
    sys.exit(1)
print(f"EQUIPMENT/ENEMY INTERACTION REGRESSION PASSED: {len(checks)}/{len(checks)} source guards")
print("Source-only checks; fight timing, hit values, and save/reload remain to be accepted in Godot 4.7.2.")

"""Static guards for the expanded four-boss rotation and distinct combat mechanics."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
enemies = (ROOT / "scripts/systems/enemy_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "the first four boss milestones rotate through four separate enemies": all(token in registry for token in ('"warden": {', '"harvester": {', '"matriarch": {', '"bellkeeper": {')) and 'boss_cycle_ids == ["warden", "harvester", "matriarch", "bellkeeper"]' in smoke,
    "new bosses have different multi-phase attack patterns": all(token in registry for token in ('"Матриарх мшистой гнили"', '"Глашатай пустого колокола"', '"Споровый шторм"', '"Последняя тишина"')),
    "boss special effects travel from data registry into combat status application": all(token in enemies for token in ('"special_effect_id": str(def.get("special_effect_id", "wound"))', '"special_effect_duration"', '"special_effect_magnitude"')) and 'status_effect_system.apply_effect(hero, boss_effect_id' in manager,
    "the new boss relics offer distinct build directions and matched sets": all(token in inventory for token in ('"matriarch_scythe"', '"matriarch_mantle"', '"bell_tuning_fork"', '"bell_veil"')),
    "Godot smoke checks four milestones and four distinct special effects": all(token in smoke for token in ('boss_special_effects.has("wound")', 'boss_special_effects.has("distortion")', 'boss_special_effects.has("poison")', 'boss_special_effects.has("weakness")')),
}
failed=[name for name,ok in checks.items() if not ok]
for name,ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    print("FOUR BOSS ROTATION REGRESSION FAILED: "+", ".join(failed))
    sys.exit(1)
print(f"FOUR BOSS ROTATION REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Source guards only; Godot runtime smoke is required for the in-engine combat result.")

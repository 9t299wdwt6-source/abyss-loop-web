"""Static regression guard for role-based enemy behaviors."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
enemies = (ROOT / "scripts/systems/enemy_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "enemy roster contains fast, tank, caster, support and hunter roles": all(f'"role": "{role}"' in registry for role in ("fast", "tank", "caster", "support", "hunter")),
    "enemy config explains its behavior before the action": '"behavior_hint"' in registry and '"ability_text"' in enemies,
    "support is ordered behind front-line enemies in groups": "var front_line: Array = []" in enemies and "return front_line + support_line" in enemies,
    "support heals the most injured ally with a capped amount": "_get_lowest_health_ally" in manager and "before_hp + heal_amount" in manager and "max_hp" in manager,
    "hunter telegraphs an empowered attack at low hero health": "Охотник замечает слабость героя" in manager and "<= 0.35" in manager,
    "caster applies a registered timed distortion effect": '_apply_enemy_status_effect("distortion"' in manager and 'return status_effect_system.apply_effect(hero, effect_id, duration, magnitude, source_id)' in manager and "status_effect_system.tick_effects(hero, delta)" in manager and "attack_speed_penalty" in manager,
    "smoke test verifies tactical enemy roles": "enemy roster must include support, execute and weaken roles" in smoke,
}
missing = [name for name, ok in checks.items() if not ok]
if missing:
    print("ENEMY ROLE REGRESSION CHECK FAILED")
    for name in missing:
        print("- " + name)
    sys.exit(1)
print("ENEMY ROLE REGRESSION CHECK PASSED")
for name in checks:
    print("- " + name)
print("Enemy combat behaviors still require Godot runtime verification.")

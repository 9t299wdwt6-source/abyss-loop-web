"""Regression guards for data-driven elites, telegraphs and rewards."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
enemies = (ROOT / "scripts/systems/enemy_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
route_view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
project = (ROOT / "project.godot").read_text(encoding="utf-8")
checks = {
    "elite cadence and tuning live in balance config": all(x in registry for x in ('"elite_loop_interval": 4', '"elite_hp_multiplier": 1.40', '"elite_item_chance": 0.45')),
    "each enemy role has a registered elite status ability": all(f'"{role}":' in registry for role in ("fast", "tank", "caster", "support", "hunter")) and 'const ELITE_ROLE_ABILITIES :=' in registry,
    "content validation checks elite ability effect and schedule": 'for elite_role_value in ELITE_ROLE_ABILITIES.keys()' in registry and 'elite ability:%s has invalid effect parameters' in registry,
    "promotion boosts one normal enemy and preserves boss distinction": 'func promote_encounter_to_elite(' in enemies and 'if bool(elite.get("is_boss", false))' in enemies and 'elite["is_elite"] = true' in enemies,
    "elite spawn cadence excludes boss cycles": 'var elite_due := not boss_encounter' in manager and 'posmod(loop_count, boss_interval) != 0' in manager,
    "special attacks are telegraphed before impact for elites": 'is_boss_attacker or is_elite_attacker' in manager and 'if is_special and not bool(fighter.get("telegraph_pending", false))' in manager,
    "elite role ability applies through shared status system": 'if is_special and is_elite_attacker:' in manager and 'status_effect_system.apply_effect(hero, elite_status_id' in manager,
    "elite gives increased reward and a named item rarity": 'elite_reward_bonus' in manager and 'elite_item_chance' in manager and 'Элитная находка' in manager,
    "elite victory count flows through the run ledger into the atomic result summary": 'elites_defeated' in manager and 'for ledger_key in ["scrap", "crystals", "victories", "bosses_defeated", "elites_defeated"' in manager and '"elites_defeated": maxi(0, int(earned.get("elites_defeated", 0)))' in state and 'int(run_ledger.get("elites_defeated", 0))' in manager[manager.index("func _finish_run(outcome: String) -> void:"):manager.index("\nfunc _scale_healing(")],
    "lifetime elite count survives saves and old saves default safely": all(x in state for x in ('var total_elites_defeated: int = 0', 'saved.get("total_elites_defeated", 0)', 'func record_elite_victory()', '"total_elites_defeated": total_elites_defeated')) and '"total_elites_defeated"' in save,
    "elite defeat total appears in shelter stats and expedition report": 'GameState.total_elites_defeated' in ui and 'Побеждено элит' in ui,
    "map and combat HUD visibly identify elites": '"Э" if elite_encounter else' in route_view and '"[ЭЛИТА · %s] · %s · %s"' in ui,
    "runtime smoke tests promotion, data ability, barrier behavior and reward stats": all(x in smoke for x in ('promote_encounter_to_elite', 'is_elite', 'elite_ability', 'bosses must not be reclassified')),
    "project version advances with current build": 'config/version="0.61.0"' in project,
}
failed = [label for label, passed in checks.items() if not passed]
for label, passed in checks.items(): print(f"{'PASS' if passed else 'FAIL'}: {label}")
if failed:
    print("ELITE ENEMY REGRESSION FAILED: " + ", ".join(failed)); sys.exit(1)
print(f"ELITE ENEMY REGRESSION PASSED: {len(checks)} checks")
print("Source guards only; Godot runtime smoke needs execution in Godot 4.7.2.")

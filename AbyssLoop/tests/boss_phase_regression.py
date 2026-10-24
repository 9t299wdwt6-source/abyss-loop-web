"""Static regression guard for multi-phase bosses and telegraphed special attacks."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
enemies = (ROOT / "scripts/systems/enemy_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "all four bosses have multi-phase definitions": registry.count('"threshold": 0.66') >= 4 and registry.count('"threshold": 0.33') >= 4 and all(token in registry for token in ('"warden": {', '"harvester": {', '"matriarch": {', '"bellkeeper": {')),
    "boss registry defines different special effects": all(token in registry for token in ('"special_effect_id": "distortion"', '"special_effect_id": "poison"', '"special_effect_id": "weakness"')) and 'fighter.get("special_effect_id", "wound")' in manager,
    "phase definitions tune attack, defense, cadence and warning": all(key in registry for key in ('"attack_multiplier"', '"defense_bonus"', '"special_every"', '"telegraph"')),
    "boss instance stores scaled baseline stats and phase data": all(key in enemies for key in ('"base_attack"', '"base_defense"', '"phase_index"', '"phase_name"', '"phases"', '"phase_telegraph"')),
    "health thresholds trigger one-way phase advancement": "func _update_boss_phase" in manager and 'enemy["phase_index"] = next_phase' in manager and 'hp_ratio > float(phase.get("threshold", 0.0))' in manager,
    "new special attacks warn and wait for a later turn": "ПРЕДУПРЕЖДЕНИЕ:" in manager and 'fighter["telegraph_pending"] = true' in manager and 'fighter["attack_timer"] = 0.0' in manager,
    "UI shows boss phase and pending strike": 'manager.enemy.get("phase_name", "Фаза 1")' in ui and 'ГОТОВИТ УДАР' in ui,
    "runtime smoke checks phase definition and telegraph": "boss definition must contain multiple phases" in smoke and "boss must expose a special-attack telegraph" in smoke,
    "phase entry effects are defined by boss data and applied once": '"status_on_enter"' in registry and 'status_effect_system.apply_effect(effect_target, phase_effect_id' in manager,
    "boss status metadata is carried from registry to live enemies": '"special_effect_id": str(def.get("special_effect_id", "wound"))' in enemies and '"special_effect_duration"' in enemies and '"special_effect_magnitude"' in enemies,
    "snapshot migration normalizes and validates boss phase state": '_normalize_boss_phase_snapshot' in save and '_validate_boss_phase_state' in save,
    "runtime smoke crosses two thresholds without repeating a phase": 'phase_after_first_transition' in smoke and 'boss_phase_manager._update_boss_phase()' in smoke,
}
missing = [name for name, ok in checks.items() if not ok]
if missing:
    print("BOSS PHASE REGRESSION CHECK FAILED")
    for name in missing:
        print("- " + name)
    sys.exit(1)
print("BOSS PHASE REGRESSION CHECK PASSED")
for name in checks:
    print("- " + name)
print("The actual phase fight still requires Godot runtime testing.")

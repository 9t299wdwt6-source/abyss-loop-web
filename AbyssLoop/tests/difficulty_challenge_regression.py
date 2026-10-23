"""Stage 46 static guards for difficulty rules, scoring and profile records."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
project = (ROOT / "project.godot").read_text(encoding="utf-8")
checks = {
    "four named difficulties provide explicit rule descriptions": all(f'"{key}"' in registry for key in ["standard", "volatile", "attrition", "abyssal"]) and '"description"' in registry,
    "all difficulty modes define combat, rewards, healing, retention and score multiplier": all(f'"{field}"' in registry for field in ["enemy_attack_multiplier", "enemy_health_multiplier", "enemy_defense_multiplier", "reward_multiplier", "encounter_chance_delta", "danger_growth_multiplier", "event_damage_multiplier", "healing_multiplier", "defeat_keep_ratio", "starting_danger", "challenge_score_multiplier"]),
    "difficulty registry validates bounds and required fields": 'difficulty:%s missing %s' in registry and 'has invalid risk/reward fields' in registry,
    "selected difficulty is described in pre-expedition preview and refreshed on change": 'СЛОЖНОСТЬ: %s — %s' in ui and '_refresh_modifier_preview()' in ui[ui.index('func _on_difficulty_selected'):ui.index('func _on_modifier_selected')],
    "difficulty cannot be swapped during an active or resumable run": 'if not GameState.has_saved_expedition():' in ui and 'if active:\n\t\treturn false' in manager[manager.index('func start_run'):manager.index('func get_run_modifier')],
    "difficulty id persists in expedition snapshot and restore validates it": '"difficulty_id": difficulty_id' in manager and 'snapshot.get("difficulty_id", "standard")' in manager and 'ContentRegistry.DIFFICULTY_PRESETS.has(difficulty_id)' in manager,
    "difficulty healing modifier applies to cycle, event, shrine, kill and tile healing": all(term in manager for term in ['func _scale_healing(amount: int)', '_scale_healing(int(ContentRegistry.BALANCE.get("loop_heal_base"', '_scale_healing(maxi(0, int(effects.get("heal"', '_scale_healing(4)', '_scale_healing(clampi(int(hero.get("equipped_kill_heal"', '_scale_healing(int(world_synergy.get("heal"']),
    "defeat retention forecast and atomic settlement use chosen difficulty": 'active_difficulty.get("defeat_keep_ratio"' in manager and 'GameState.settle_expedition(' in manager and 'summary_metadata, record_key, challenge_score' in manager and 'defeat_keep_ratio_override: float = -1.0' in state,
    "difficulty rewards affect both actual loop income and forecast": 'active_difficulty.get("reward_multiplier", 1.0)' in manager and 'var projected_scrap := int(round(float(projected_scrap_base) * float(active_difficulty.get("reward_multiplier", 1.0))' in manager,
    "score uses real run counters and successful optional objectives": all(term in manager for term in ['run_ledger.get("victories"', 'run_ledger.get("bosses_defeated"', 'run_ledger.get("elites_defeated"', 'run_challenge.get("completed"', 'run_contract.get("completed"', '"challenge_score": challenge_score']),
    "best score and difficulty records persist with safe old-save defaults": all(term in state for term in ['var difficulty_records: Dictionary = {}', 'saved.get("difficulty_records", {})', 'func record_difficulty_result(', '"difficulty_records": difficulty_records.duplicate(true)']),
    "result screen reports selected difficulty score and personal record": all(term in ui for term in ['"Сложность: %s · счёт испытания: %d"', '"Рекорд сложности: %d очков']),
    "supply objective and contract targets reflect observed run yields": '"target": 300, "scrap_reward": 30, "crystal_reward": 3' in registry and '"target": 300, "deadline_loops": 3' in registry,
    "prototype version advances without changing stable app name": 'config/name="Abyss Loop"' in project and 'config/version="0.61.0"' in project,
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    print("DIFFICULTY / CHALLENGE REGRESSION FAILED")
    for item in failed: print("- " + item)
    sys.exit(1)
print(f"DIFFICULTY / CHALLENGE REGRESSION PASSED: {len(checks)} checks")
for name in checks: print("- " + name)
print("Source-level checks only; Godot runtime difficulty balance still requires matched campaigns in Godot 4.7.2.")

"""Stage 92 guards for eight-floor campaign pressure, scoring and profile records."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
project = (ROOT / "project.godot").read_text(encoding="utf-8")

checks = {
    "eight numbered floors define combat, reward, recovery and score rules": 'const ABYSS_FLOOR_COUNT := 8' in registry and all(field in registry for field in ['"enemy_attack_multiplier"', '"enemy_health_multiplier"', '"enemy_defense_multiplier"', '"reward_multiplier"', '"healing_multiplier"', '"defeat_keep_ratio"', '"challenge_score_multiplier"']),
    "floor registry validates bounds, monotonic pressure, and known biome content": 'abyss floor pressure/rewards must not decrease' in registry and 'floor_enemy_pool' in registry and 'floor_tile_pool' in registry and 'ABYSS_FLOORS.size() != ABYSS_FLOOR_COUNT' in registry,
    "new and resumed runs store a floor ID instead of a selectable difficulty": 'requested_floor_id: int = 1' in manager and '"floor_id": floor_id' in manager and 'snapshot.get("floor_id", 1)' in manager and 'DIFFICULTY_PRESETS.get(difficulty_id' not in manager,
    "floor pressure controls healing, retention, rewards and score multiplier": all(token in manager for token in ['func _scale_healing(amount: int)', 'active_difficulty.get("defeat_keep_ratio"', 'active_difficulty.get("reward_multiplier"', 'active_difficulty.get("challenge_score_multiplier"']),
    "floor selection is limited to permanently unlocked floors": 'range(1, GameState.highest_unlocked_floor + 1)' in ui and 'GameState.is_abyss_floor_unlocked(requested_floor_id)' in manager,
    "challenge score and personal records are keyed by floor": '"floor_%02d" % floor_id' in manager and 'func record_difficulty_result(' in state and 'difficulty_records' in state,
    "result screen reports the floor name and its own best record": 'Этаж Бездны %d/8' in ui and 'Рекорд этого этажа' in ui and '"floor_name": str(get_floor_config()' in manager,
    "difficulty selector is absent from the preparation UI": 'difficulty_option' not in ui and 'selected_difficulty_id' not in ui and 'СЛОЖНОСТЬ:' not in ui,
    "run score still uses real campaign counters and completed optional objectives": all(token in manager for token in ['run_ledger.get("victories"', 'run_ledger.get("bosses_defeated"', 'run_ledger.get("elites_defeated"', 'run_challenge.get("completed"', '"challenge_score": challenge_score']),
    "prototype version advances without changing stable app name": 'config/name="Abyss Loop"' in project and 'config/version="0.61.0"' in project,
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    print("ABYSS FLOOR / CHALLENGE REGRESSION FAILED")
    for item in failed:
        print("- " + item)
    sys.exit(1)
print(f"ABYSS FLOOR / CHALLENGE REGRESSION PASSED: {len(checks)} checks")
for name in checks:
    print("- " + name)
print("Source-level only; matched floor-to-floor balance still requires Godot 4.7.2 gameplay acceptance.")

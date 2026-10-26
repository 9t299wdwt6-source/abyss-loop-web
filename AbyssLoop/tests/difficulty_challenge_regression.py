"""Regression guards for the eight-floor campaign progression and absence of difficulty selectors."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
enemy = (ROOT / "scripts/systems/enemy_system.gd").read_text(encoding="utf-8")
project = (ROOT / "project.godot").read_text(encoding="utf-8")
checks = {
    "campaign has exactly eight ordered floor definitions": 'const FLOOR_COUNT: int = 8' in registry and 'const FLOOR_DEFS: Array[Dictionary] = [' in registry and 'FLOOR_DEFS.size() != FLOOR_COUNT' in registry,
    "every floor config has its own registered guardian, biome, and enemy pool": all(field in registry for field in ['"biome"', '"boss_id"', '"enemy_pool"', '"starting_danger"', '"reward_multiplier"']) and 'floor:%d references unknown boss' in registry and 'floor:%d references unknown enemy' in registry,
    "new expedition starts on an unlocked floor and does not accept a difficulty choice": 'requested_floor_number: int = 1' in manager and 'floor_number > int(GameState.highest_unlocked_floor)' in manager and 'difficulty_id = "standard"' in manager,
    "each floor derives a reproducible independent world and RNG seed": 'func _get_floor_seed(base_seed: int, requested_floor: int)' in manager and 'route_system.create_route(floor_seed' in manager and 'run_rng.seed = floor_seed' in manager,
    "floor enemy pools and guardian IDs feed production encounter generation": 'floor_config.get("enemy_pool", [])' in manager and 'preferred_boss_id' in manager and 'create_boss(loop_count, danger + strength_bonus, rng, preferred_boss_id)' in enemy,
    "floor modifiers affect combat, healing, route danger, events, and rewards": all(text in manager for text in ['floor_config.get("enemy_attack_multiplier"', 'floor_config.get("enemy_health_multiplier"', 'floor_config.get("enemy_defense_multiplier"', 'floor_config.get("healing_multiplier"', 'floor_config.get("danger_growth_multiplier"', 'floor_config.get("event_damage_multiplier"', 'floor_config.get("reward_multiplier"']),
    "defeating the configured guardian completes the floor only after the battle and perk flow": 'is_floor_guardian' in manager and 'run_ledger["floor_boss_defeated"] = true' in manager and 'func _maybe_finish_floor_after_boss()' in manager and 'pending_perk_count > 0 or not enemy.is_empty() or not pending_event.is_empty()' in manager,
    "unlocking the next floor is part of the durable settlement transaction": 'var highest_unlocked_floor: int = 1' in state and 'saved.get("highest_unlocked_floor", 1)' in state and '"highest_unlocked_floor": highest_unlocked_floor' in state and 'summary_metadata.get("floor_cleared", false)' in state and 'highest_unlocked_floor = old_highest_unlocked_floor' in state,
    "floor number and clear state survive save/restore and appear in the final summary": '"floor_number": floor_number' in manager and 'snapshot.get("floor_number", 1)' in manager and '"floor_cleared": bool(run_ledger.get("floor_cleared", false))' in manager,
    "preparation UI exposes the eight-floor selector and no difficulty/mode selectors": 'floor_option = OptionButton.new()' in ui and 'ContentRegistry.FLOOR_DEFS' in ui and '_on_floor_selected' in ui and 'difficulty_option' not in ui and 'expedition_mode_option' not in ui and 'СЛОЖНОСТЬ:' not in ui,
    "results report a floor clear and the next unlocked floor instead of a difficulty result": 'ЭТАЖ ПРОЙДЕН' in ui and 'Этаж %d/8' in ui and 'Сложность:' not in ui and 'Рекорд сложности' not in ui,
    "prototype version and stable application name remain intact": 'config/name="Abyss Loop"' in project and 'config/version="0.61.0"' in project,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"[{'PASS' if ok else 'FAIL'}] {name}")
if failed:
    raise SystemExit("FLOOR / PROGRESSION REGRESSION FAILED: " + ", ".join(failed))
print(f"FLOOR / PROGRESSION REGRESSION PASSED: {len(checks)}/{len(checks)} source guards")
print("These source guards complement, but do not replace, the Godot floor progression runtime acceptance.")

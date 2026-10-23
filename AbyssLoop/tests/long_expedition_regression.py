"""Source-level guards for the stage-48 long expedition / endgame contract."""
from pathlib import Path
import json
import sys
ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
game_state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
project = (ROOT / "project.godot").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
catalog = json.loads((ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"))
checks = {
    "standalone expedition mode is separate from difficulty and route modifiers": 'const EXPEDITION_MODES :=' in registry and 'var expedition_mode_id: String = "standard"' in manager and 'var run_modifier_id: String = "standard"' in manager,
    "endgame target is 12 loops and four scheduled bosses": '"goal_loops": 12' in registry and '"goal_bosses": 4' in registry and 'boss_loop_interval' in manager,
    "mode selection is exposed in the preparation screen": '_t("base.mode.label")' in ui and catalog.get("base.mode.label") == "РЕЖИМ ЭКСПЕДИЦИИ" and 'ContentRegistry.EXPEDITION_MODES.keys()' in ui and 'selected_expedition_mode_id)' in ui,
    "mode is passed through start-run and stored in the run snapshot": 'selected_contract_id, selected_expedition_mode_id)' in ui and '"expedition_mode_id": expedition_mode_id' in manager,
    "old snapshots without mode fall back to standard": 'snapshot.get("expedition_mode_id", "standard")' in manager and 'if not ContentRegistry.EXPEDITION_MODES.has(expedition_mode_id)' in manager,
    "long mode applies soft cap to danger while standard mode remains unchanged": 'func _clamp_long_mode_danger' in manager and 'return value' in manager and 'max_danger' in registry,
    "long mode caps loop reward multiplier without changing standard formula": 'combined_reward_multiplier = minf(combined_reward_multiplier' in manager and '"reward_multiplier_cap": 1.80' in registry,
    "enemy/boss scaling input is bounded only in the long mode": 'func _effective_scaling_loop' in manager and 'if expedition_mode_id != "long_expedition":' in manager and 'create_encounter(encounter_scaling_loop' in manager,
    "checkpoint writes occur at intervals, are idempotent, and remain bounded": 'func _record_long_expedition_checkpoint' in manager and 'loop_count % interval' in manager and 'int(previous_value.get("loop", -1)) == loop_count' in manager and 'while checkpoints.size() > 8' in manager,
    "checkpoint data includes survival, danger, boss count and resources": all(k in manager for k in ['"hp": int(hero.get("hp", 0))', '"danger": snappedf(danger, 0.01)', '"bosses_defeated": int(run_ledger.get("bosses_defeated", 0))', '"scrap": int(run_ledger.get("scrap", 0))', '"crystals": int(run_ledger.get("crystals", 0))']),
    "restored checkpoints reject malformed/duplicate loops and clamp payload values": all(k in manager for k in ['var restored_checkpoints: Array = []', 'seen_checkpoint_loops.has(checkpoint_loop)', 'checkpoint_loop > 12', 'clampf(float(checkpoint_entry.get("danger", 1.0)), 1.0, 6.0)', 'while restored_checkpoints.size() > 8']),
    "endgame completion requires loop goal, boss goal, and no pending battle/perk/event": all(k in manager for k in ['func _maybe_finish_long_expedition()', 'pending_perk_count > 0', 'not enemy.is_empty()', 'not pending_event.is_empty()', 'goal.get("target_loops", 12)', 'goal.get("target_bosses", 4)']),
    "completed endgame settles as a full-retention return and adds a score bonus": 'run_ledger["endgame_completed"] = true' in manager and '_finish_run("return")' in manager and 'raw_score += 250' in manager,
    "atomic settlement metadata exposes endgame progress and completion state": all(k in manager[manager.index("func _finish_run(outcome: String) -> void:"):manager.index("\nfunc _scale_healing(")] for k in ['"expedition_mode_name": str(get_expedition_mode().get("name", "Обычная экспедиция"))', '"endgame_target_loops": int(endgame_goal.get("target_loops", 0))', '"endgame_target_bosses": int(endgame_goal.get("target_bosses", 0))', '"endgame_completed": bool(run_ledger.get("endgame_completed", false))', '"endgame_checkpoints":']) and 'summary.merge(summary_metadata, true)' in game_state,
    "history persists mode and endgame completion": all(k in game_state for k in ['"expedition_mode_id": str(source.get', '"expedition_mode_name": str(source.get', '"endgame_completed": bool(source.get']),
    "Godot smoke test covers long-mode caps and idempotent checkpoint creation": all(term in smoke for term in ['Long expedition soft caps are isolated', '_effective_scaling_loop(50) == 12', '_clamp_long_mode_danger(99.0) == 6.0', 'checkpoint must not duplicate', 'standard expedition scaling must remain uncapped']),
    "prototype version advanced to 0.61.0": 'config/version="0.61.0"' in project,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"[{'PASS' if ok else 'FAIL'}] {name}")
if failed:
    raise SystemExit(f"LONG EXPEDITION REGRESSION FAILED: {len(failed)} checks: {failed}")
print(f"LONG EXPEDITION REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Static guards only. Final-boss flow, save/resume, and balance must be played in Godot 4.7.2.")

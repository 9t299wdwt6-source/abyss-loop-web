"""Cross-system guards for checkpoint, event, terminal settlement and release-gate behavior."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
game_state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
runner = (ROOT / "tools/run_runtime_gate.py").read_text(encoding="utf-8")
packager = (ROOT / "tools/package_release.py").read_text(encoding="utf-8")
runtime_test = (ROOT / "tests/expedition_integration_audit.gd").read_text(encoding="utf-8")

checks = {
    "checkpoint updates roll back in-memory snapshot after failed disk write": "var previous_snapshot: Dictionary = saved_expedition.duplicate(true)" in game_state and "saved_expedition = previous_snapshot\n\t\treturn false" in game_state,
    "discard is a result-bearing transaction and restores checkpoint on failure": "func clear_saved_expedition() -> bool:" in game_state and "if not save_now():\n\t\tsaved_expedition = previous_snapshot\n\t\treturn false" in game_state,
    "settlement snapshots every durable field including history, records and loadout": all(token in game_state for token in ["var old_scrap := scrap", "var old_crystals := crystals", "var old_runs_completed := runs_completed", "var old_best_loop := best_loop", "var old_total_events_resolved := total_events_resolved", "var old_saved_expedition: Dictionary", "var old_last_summary: Dictionary", "var old_difficulty_records: Dictionary", "var old_expedition_history: Array", "var old_loadout: Dictionary"]),
    "failed settlement restores rewards, counters, history, difficulty record, loadout, summary and checkpoint": all(token in game_state for token in ["scrap = old_scrap", "crystals = old_crystals", "runs_completed = old_runs_completed", "best_loop = old_best_loop", "total_events_resolved = old_total_events_resolved", "saved_expedition = old_saved_expedition", "last_summary = old_last_summary", "difficulty_records = old_difficulty_records", "expedition_history = old_expedition_history", "loadout = old_loadout", '"_persistence_ok": false']),
    "rich summary, history row and difficulty result are added before the single settlement save": game_state.index('summary["history_saved"] = history_saved') < game_state.index('last_summary = summary.duplicate(true)', game_state.index('func settle_expedition')) < game_state.index('if not save_now():', game_state.index('func settle_expedition')) and 'summary["difficulty_record_saved"] = not difficulty_record_key.strip_edges().is_empty()' in game_state,
    "manager no longer performs follow-up history/record saves after settling rewards": 'GameState.record_expedition_history(summary)' not in manager and 'GameState.record_difficulty_result(record_key' not in manager,
    "manager halts and pauses after failed terminal save instead of emitting completion": 'if not bool(summary.get("_persistence_ok", true)):' in manager and "active = true\n\t\tpaused = true" in manager and "return\n\tsummary.erase(\"_persistence_ok\")" in manager,
    "retry keeps original terminal outcome and prevents double settlement": "if not pending_end_outcome.is_empty():\n\t\toutcome = pending_end_outcome" in manager and 'pending_end_outcome = ""' in manager and "if not active:\n\t\treturn\n\tif pending_end_outcome.is_empty():" in manager,
    "failed settlement locks event, perk, tile, speed and unpause actions": (
        all("if not pending_end_outcome.is_empty():" in manager[manager.find(f"func {fn}"):manager.find("\nfunc ", manager.find(f"func {fn}")+5) if "\nfunc " in manager[manager.find(f"func {fn}")+5:] else len(manager)] for fn in ["resolve_event_choice", "choose_perk", "set_speed", "place_tile", "place_world_tile"])
        and "if not pending_end_outcome.is_empty() and not value:" in manager[manager.find("func set_pause"):manager.find("\nfunc ", manager.find("func set_pause")+5)]
    ),
    "periodic or manual snapshot failure is visible only once until next successful save": "var _snapshot_save_failure_notified: bool = false" in manager and "_snapshot_save_failure_notified = false" in manager and "Последняя подтверждённая контрольная точка сохранена" in manager,
    "UI confirms deleting an expedition only after durable deletion succeeds": "if not GameState.clear_saved_expedition():" in ui and "Не удалось сохранить удаление забега" in ui,
    "runtime gate executes the cross-system audit after save regression": runner.index('"Save-system regression"') < runner.index('"Expedition integration audit"') and "tests/expedition_integration_audit.gd" in runner,
    "runtime gate requires all seven gates before creating a runtime-tested archive": "len(steps) == 7" in runner and "if not success:" in runner,
    "package release requires the integration checklist and runnable audit": '"tests/expedition_integration_audit.gd"' in packager and '"tests/expedition_integration_audit_regression.py"' in packager and '"INTEGRATION_AUDIT_RUNTIME_CHECKLIST_Prototype54.md"' in packager,
    "runtime script tests exactly-once summary, history and difficulty record persistence": all(token in runtime_test for token in ['GameState.expedition_history.size() == history_before_settlement', 'difficulty_runs_before', 'persisted_profile.get("last_summary", {})', 'matching_history_rows == 1', 'GameState.last_summary.get("history_saved", false)']),
    "runtime script injects a rejected save and checks terminal outcome idempotency": all(token in runtime_test for token in ["GameState.set_saved_expedition(invalid_snapshot)", "GameState.clear_saved_expedition()", 'manager.end_run("return")', 'manager.end_run("defeat")', '"outcome"']),
    "current project version is stable-name 0.61.0": 'config/name="Abyss Loop"' in (ROOT / "project.godot").read_text(encoding="utf-8") and 'config/version="0.61.0"' in (ROOT / "project.godot").read_text(encoding="utf-8"),
}
failed = [name for name, ok in checks.items() if not ok]
assert not failed, "EXPEDITION INTEGRATION AUDIT REGRESSION FAILED: " + ", ".join(failed)
print(f"EXPEDITION INTEGRATION AUDIT REGRESSION PASSED: {len(checks)}/{len(checks)} source-level integration invariants")
for name in checks:
    print("- " + name)
print("The Godot integration script is wired into the Windows runtime gate; it must still pass in Godot 4.7.2 to claim runtime acceptance.")

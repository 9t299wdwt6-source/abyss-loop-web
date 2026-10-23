"""Source-level regression for the entire expedition result commit boundary."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
runtime = (ROOT / "tests/expedition_integration_audit.gd").read_text(encoding="utf-8")
project = (ROOT / "project.godot").read_text(encoding="utf-8")

start = manager.index("func _finish_run(outcome: String) -> void:")
end = manager.index("\nfunc _scale_healing(", start)
finish = manager[start:end]
settle_start = state.index("func settle_expedition(")
settle_end = state.index("\nfunc record_difficulty_result(", settle_start)
settle = state[settle_start:settle_end]

checks = {
    "full result metadata is constructed before terminal persistence": finish.index("var summary_metadata: Dictionary") < finish.index("GameState.settle_expedition("),
    "replay identity includes run counter seed and difficulty": '"run_id": "%d-%d-%s" % [GameState.runs_started, run_seed, difficulty_id]' in finish and '"seed": run_seed' in finish,
    "score includes loops battles bosses elites events and objective rewards": all(token in finish for token in ['run_ledger.get(\"victories\"', 'run_ledger.get(\"bosses_defeated\"', 'run_ledger.get(\"elites_defeated\"', 'run_ledger.get(\"events_resolved\"', 'raw_score += 250']),
    "settlement atomically accepts rich metadata score difficulty and final loadout": "summary_metadata, record_key, challenge_score" in finish and "equipment" in finish[finish.index("GameState.settle_expedition("):],
    "checkpoint clear and reward addition precede exactly one durable save": all(token in settle for token in ["saved_expedition.clear()", "scrap += kept_scrap", "crystals += kept_crystals", "runs_completed += 1", "if not save_now():"]),
    "rich summary, difficulty record and bounded history are in the same payload": all(token in settle for token in ["last_summary = summary.duplicate(true)", "difficulty_records[difficulty_record_key]", "expedition_history.append(history_entry)", "MAX_EXPEDITION_HISTORY"]),
    "failed persistence rolls back history records loadout rewards and the checkpoint": all(token in settle for token in ["saved_expedition = old_saved_expedition", "difficulty_records = old_difficulty_records", "expedition_history = old_expedition_history", "loadout = old_loadout", "scrap = old_scrap", 'return {"_persistence_ok": false']),
    "terminal failure pauses run and retains original return/defeat outcome": 'if not pending_end_outcome.is_empty():\n\t\toutcome = pending_end_outcome' in manager and 'active = true\n\t\tpaused = true' in finish,
    "successful commit only then emits completion summary": finish.index('if not bool(summary.get("_persistence_ok", true))') < finish.index('run_finished.emit(summary.duplicate(true))'),
    "runtime integration audit verifies persisted summary and exactly one history row": all(token in runtime for token in ['persisted_profile.get("last_summary", {})', "matching_history_rows == 1", "history_before_settlement + 1", "difficulty_runs_before + 1"]),
    "build identity is 0.61.0 and stable application name is unchanged": 'config/name="Abyss Loop"' in project and 'config/version="0.61.0"' in project,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
assert not failed, "GAMEPLAY CYCLE REGRESSION FAILED: " + ", ".join(failed)
print(f"GAMEPLAY CYCLE REGRESSION PASSED: {len(checks)}/{len(checks)} assertions")
print("Source-level guard only; execute expedition_integration_audit.gd with Godot 4.7.2 for runtime verification.")

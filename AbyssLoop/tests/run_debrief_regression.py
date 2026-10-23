"""Static guard for the pure post-run debrief presenter and its UI delegation."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
presenter = (ROOT / "scripts/ui/run_debrief_presenter.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
game_state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
finish = manager[manager.index("func _finish_run(outcome: String) -> void:"):manager.index("\nfunc _scale_healing(")]
settle_call = manager[manager.index("GameState.settle_expedition("):manager.index("GameState.settle_expedition(") + 220]
checks = {
    "summary screen renders a dedicated debrief panel and delegates to presenter": '"РАЗБОР ЗАБЕГА · СЛЕДУЮЩИЙ ШАГ"' in ui and "RunDebriefPresenterScript.build(summary)" in ui,
    "UI preloads extracted pure presenter": 'preload("res://scripts/ui/run_debrief_presenter.gd")' in ui,
    "debrief presenter handles endgame, return and defeat paths": 'bool(summary.get("endgame_completed", false))' in presenter and 'outcome == "return"' in presenter and 'lost_crystals > 0' in presenter,
    "debrief uses actual loss, victory, boss and loop metrics": all(term in presenter for term in ['summary.get("lost_crystals", 0)', 'summary.get("lost_scrap", 0)', 'summary.get("victories", 0)', 'summary.get("bosses_defeated", 0)', 'summary.get("loops", 0)']),
    "debrief handles unfinished or failed optional contracts": 'bool(contract.get("failed", false))' in presenter and 'not bool(contract.get("completed", false))' in presenter,
    "presenter is read-only and cannot change gameplay or rewards": all(term not in presenter for term in ["GameState.", "resource_system.", "manager.", "queue_free(", "append_array(", "settle_expedition("]),
    "summary metadata still comes from finalized expedition ledger and atomic settlement": all(term in finish for term in ['"bosses_defeated": int(run_ledger.get("bosses_defeated", 0))', '"events_resolved": int(run_ledger.get("events_resolved", 0))', '"challenge_score": challenge_score']) and "GameState.settle_expedition(" in settle_call and "run_ledger, outcome, loop_count" in settle_call and '"lost_crystals": maxi(0, int(earned.get("crystals", 0)) - kept_crystals)' in game_state,
    "Godot smoke calls extracted presenter for return, defeat and endgame cases": all(term in smoke for term in ("return_debrief", "defeat_debrief", "endgame_debrief", "RunDebriefPresenterType.build(")),
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + name)
assert not failed, "Run debrief regression failed: " + ", ".join(failed)
print(f"RUN DEBRIEF REGRESSION: {sum(checks.values())}/{len(checks)}")
print("Source-level only; rendered fit and game feel require Godot runtime review.")

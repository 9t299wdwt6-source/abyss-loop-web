"""Static checks for goals and one-time objective payouts."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
reg=(ROOT/"scripts/core/content_registry.gd").read_text(encoding="utf-8")
manager=(ROOT/"scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui=(ROOT/"scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke=(ROOT/"tests/smoke_test.gd").read_text(encoding="utf-8")
checks={
"objective catalogue covers loops, bosses, combat, events and resources": all(x in reg for x in ('"cycle_milestone"','"boss_contract"','"combat_record"','"event_research"','"material_survey"')),
"goal is picked deterministically from the same seed shown in preparation": '_choose_objective_for_seed(run_seed, run_modifier_id)' in manager and 'objective_rng.seed = int(seed_value) ^ 0x51A7C3' in manager and 'preview_objective_for_seed(_get_preview_seed(), selected_modifier_id)' in ui,
"goal progress is derived from real run counters": all(x in manager for x in ('"loops": return int(loop_count)','"bosses": return int(run_ledger.get("bosses_defeated"','"events": return int(run_ledger.get("events_resolved"')),
"objective reward has an idempotent rewarded flag": 'run_objective["rewarded"] = true' in manager and 'bool(run_objective.get("rewarded", false))' in manager,
"goal survives snapshots and appears in run/report UI": '"run_objective": run_objective.duplicate(true)' in manager and 'ЦЕЛЬ:' in ui and 'ЦЕЛЬ ЭКСПЕДИЦИИ:' in ui,
"runtime smoke verifies objective catalogue": 'EXPEDITION_OBJECTIVES.size() >= 5' in smoke,
"objective UI previews condition and reward before launch": 'АВТОЦЕЛЬ ЭКСПЕДИЦИИ (по seed):' in ui and 'objective_label.tooltip_text' in ui and '_on_seed_input_changed' in ui,
"objective filtering checks run feasibility and supported counters": '_objective_is_feasible_for_run' in manager and 'supported_objective_kinds' in reg and 'objective:%s uses unsupported progress kind' in reg,
}
missing=[k for k,v in checks.items() if not v]
if missing:
 print("OBJECTIVE REGRESSION FAILED")
 for m in missing: print("- "+m)
 sys.exit(1)
print("OBJECTIVE REGRESSION PASSED")
for k in checks: print("- "+k)
print("Objective progress/payout need Godot runtime testing.")

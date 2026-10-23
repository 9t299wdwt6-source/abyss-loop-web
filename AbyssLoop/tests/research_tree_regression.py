"""Static checks for branching research and real gameplay effects."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
reg=(ROOT/"scripts/core/content_registry.gd").read_text(encoding="utf-8")
base=(ROOT/"scripts/systems/base_system.gd").read_text(encoding="utf-8")
manager=(ROOT/"scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui=(ROOT/"scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke=(ROOT/"tests/smoke_test.gd").read_text(encoding="utf-8")
checks={
"research branches contain tactical, combat, economy and event paths": all(x in reg for x in ('"rare_survey"','"field_training"','"event_forecasting"','"supply_contracts"','"crystal_study"')),
"dependencies are declared and checked centrally": '"prerequisites"' in reg and 'prerequisites_met' in base and 'missing' in base,
"rare tiles, starting attack, events and cycle income use unlock effects": all(x in manager for x in ('unlock_rare_tiles','field_training_attack','event_damage_reduction','loop_crystal_bonus')) and 'get_unlock_effect("route_reward_bonus")' in (ROOT/"scripts/core/game_state.gd").read_text(encoding="utf-8"),
"research interface is scrollable and displays effect/dependency": 'var research_scroll := ScrollContainer.new()' in ui and 'ЭФФЕКТ:' in ui and 'Зависимости:' in ui,
"runtime smoke covers research effects": all(x in smoke for x in ('rare_survey','field_training','event_forecasting')),
"four shelter specializations have explicit root nodes and summaries": all(x in reg for x in ('const RESEARCH_BRANCHES := {','"tactics": {','"preparation": {','"scouting": {','"economy": {','"entry_node"')),
"branch-aware UI displays progress, next-node preview and blocked reasons": all(x in ui for x in ('get_research_branch_status(branch_id)','Следующий открываемый узел:','ЗАБЛОКИРОВАНО · не изучено:','Будущие узлы закрыты')),
}
missing=[k for k,v in checks.items() if not v]
if missing:
 print("RESEARCH TREE REGRESSION FAILED")
 for m in missing: print("- "+m)
 sys.exit(1)
print("RESEARCH TREE REGRESSION PASSED")
for k in checks: print("- "+k)
print("Actual purchases and their effects require Godot runtime testing.")

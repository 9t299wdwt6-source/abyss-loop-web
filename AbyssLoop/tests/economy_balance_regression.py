"""Static checks for centralized balance data and the return/continue forecast."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
reg=(ROOT/"scripts/core/content_registry.gd").read_text(encoding="utf-8")
manager=(ROOT/"scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
loot=(ROOT/"scripts/systems/loot_system.gd").read_text(encoding="utf-8")
enemy=(ROOT/"scripts/systems/enemy_system.gd").read_text(encoding="utf-8")
ui=(ROOT/"scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
game_state=(ROOT/"scripts/core/game_state.gd").read_text(encoding="utf-8")
checks={
"core economy coefficients are centralized": all(x in reg for x in ('"loop_danger_growth"','"encounter_chance_base"','"encounter_chance_min"','"encounter_chance_max"','"loop_heal_base"','"loop_crystal_interval"')),
"enemy and loot scaling use configured values": 'enemy_loop_scaling' in enemy and 'boss_cycle_scaling' in enemy and 'loot_crystal_loop_step' in loot,
"difficulty alters reward and danger trajectory": 'danger_growth_multiplier' in manager and 'reward_multiplier' in manager and 'encounter_chance_delta' in manager,
"return preview compares safe payout, defeat loss and next-loop risk": 'func get_return_forecast' in manager and 'defeat_scrap' in manager and 'danger_next' in manager and 'boss_next' in manager,
"return confirmation surfaces the estimate": 'get_return_forecast()' in ui and 'расчётная вероятность обычной встречи' in ui and 'Безопасный возврат сохраняет' in ui,
"defeat retention stays configured in one place": 'ContentRegistry.BALANCE.defeat_keep_ratio' in game_state and 'defeat_keep_ratio' in reg,
}
missing=[k for k,v in checks.items() if not v]
if missing:
 print("ECONOMY BALANCE REGRESSION FAILED")
 for m in missing: print("- "+m)
 sys.exit(1)
print("ECONOMY BALANCE REGRESSION PASSED")
for k in checks: print("- "+k)
print("Forecast accuracy still requires in-engine gameplay comparisons.")

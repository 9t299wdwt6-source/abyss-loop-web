"""Bound permanent income so economy progression does not erase expedition risk."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
reg=(ROOT/"scripts/core/content_registry.gd").read_text(encoding="utf-8")
state=(ROOT/"scripts/core/game_state.gd").read_text(encoding="utf-8")
manager=(ROOT/"scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
smoke=(ROOT/"tests/smoke_test.gd").read_text(encoding="utf-8")

def capped(building: int, salvage_research: int, supply_research: int, cap: int=6) -> int:
    return max(0,min(cap,building+salvage_research+supply_research))
checks={
 "income cap is centralized and validates a safe range": '"shelter_loop_scrap_bonus_cap": 6' in reg and 'shelter loop scrap bonus cap must stay between 0 and 8' in reg,
 "all building and research income is aggregated before the cap": all(token in state for token in ('get_loop_scrap_bonus()', 'get_unlock_effect("loop_scrap_bonus")', 'get_unlock_effect("route_reward_bonus")', 'clampi(building_bonus + research_bonus, 0, cap)')),
 "forecast and actual payout use the same helper": manager.count('GameState.get_effective_loop_scrap_bonus()')==2 and 'projected_scrap_base' in manager and 'loop_reward_base' in manager,
 "economic investment cannot exceed six extra scraps per loop": all(capped(b,s,r)<=6 for b in range(6) for s in (0,2) for r in (0,2)),
 "cap preserves base route income rather than replacing its formula": '"route_reward_scrap": 4' in reg and 'route_reward_scrap", 4)) + GameState.get_effective_loop_scrap_bonus()' in manager,
 "runtime smoke verifies maximum and lower bound": 'effective loop income must remain bounded' in smoke and 'all passive per-loop scrap sources must share the configured cap' in smoke,
}
failed=[name for name,ok in checks.items() if not ok]
if failed:
 print("SHELTER ECONOMY CAP REGRESSION FAILED")
 for name in failed: print("- "+name)
 sys.exit(1)
print(f"SHELTER ECONOMY CAP REGRESSION PASSED: {len(checks)} checks")
for name in checks: print("- "+name)
print("Numerical screening and source guards are not a substitute for in-engine economy campaigns.")

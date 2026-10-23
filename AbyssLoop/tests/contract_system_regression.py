"""Static contract-system guards; actual contract runs still require Godot runtime."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "optional contracts include none and four timed resource-backed jobs": all(f'"{key}"' in registry for key in ("none", "landscape_survey", "bounty_hunter", "event_archive", "boss_bounty", "salvage_quota")),
    "each contract defines target, deadline, cost and payout": all(field in registry for field in ('"deadline_loops"', '"scrap_cost"', '"crystal_cost"', '"scrap_reward"', '"crystal_reward"')),
    "contract conditions use real world/combat/event counters": all(f'"{key}"' in manager for key in ('world_tiles', 'victories', 'events', 'bosses', 'scrap')) and 'world_tiles.size()' in manager,
    "deadline failure and one-time payout are explicitly guarded": 'loop_count > maxi(0, int(run_contract.get("deadline_loops", 1)))' in manager and 'run_contract["rewarded"] = true' in manager,
    "contract affordability is checked before run generation": 'func can_accept_contract(contract_id: String) -> Dictionary:' in manager and 'GameState.scrap < scrap_cost or GameState.crystals < crystal_cost' in manager,
    "fee, run counter and first snapshot commit atomically": 'func commit_expedition_start(snapshot: Dictionary' in state and 'GameState.commit_expedition_start(export_run_state()' in manager,
    "contract state persists in snapshot v4": '"snapshot_version": 4' in manager and '"run_contract": run_contract.duplicate(true)' in manager,
    "snapshot migration supplies empty contract for old runs": 'migrated_v2["run_contract"] = {}' in save and 'migrated_v3["snapshot_version"] = 4' in save,
    "snapshot validator checks registered contract and state flags": 'ContentRegistry.EXPEDITION_CONTRACTS.has(contract_id)' in save and '"cost_paid"' in save,
    "preparation UI previews price deadline and payout": 'contract_option.item_selected.connect(_on_contract_selected)' in ui and 'Срок: до цикла %d. Награда:' in ui,
    "active HUD and run result show contract status": 'contract_label.text = "КОНТРАКТ:' in ui and 'summary.get("contract", {})' in ui,
    "runtime smoke verifies contract definitions and registration": 'ContentRegistry.EXPEDITION_CONTRACTS.size() >= 5' in smoke and 'contract_manager.can_accept_contract("none")' in smoke,
    "project version is 0.61.0 for this build": 'config/version="0.61.0"' in (ROOT / "project.godot").read_text(encoding="utf-8"),
}
failed = [key for key, ok in checks.items() if not ok]
for key, ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'}: {key}")
if failed:
    print("CONTRACT SYSTEM REGRESSION FAILED: " + ", ".join(failed)); sys.exit(1)
print("CONTRACT SYSTEM REGRESSION PASSED: %d checks" % len(checks))
print("Static source evidence only; contract flow must also be run in Godot 4.7.2.")

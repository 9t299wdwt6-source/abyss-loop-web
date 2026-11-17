"""Guards that the retired optional-contract UI stays out of the campaign path.

Legacy contract payloads remain readable so previously saved runs/history are not
damaged, but new expeditions always start without a contract and the UI has no
contract picker, HUD, fee, or payout surface.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
project = (ROOT / "project.godot").read_text(encoding="utf-8")

checks = {
    "legacy contract definitions remain available for old run data": 'const EXPEDITION_CONTRACTS :=' in registry and 'ContentRegistry.EXPEDITION_CONTRACTS.has(contract_id)' in save,
    "old contract snapshots can still be migrated safely": '"run_contract": run_contract.duplicate(true)' in manager and 'migrated_v2["run_contract"] = {}' in save,
    "new runs always pass the no-contract value": 'manager.start_run("standard", requested_seed, selected_modifier_id, "none", selected_expedition_mode_id, selected_floor_id)' in ui,
    "base preparation has no contract selector or price/deadline preview": 'contract_option' not in ui and 'selected_contract_id' not in ui and 'Срок: до цикла' not in ui,
    "active HUD and result UI no longer expose contract status": 'contract_label' not in ui and 'КОНТРАКТ:' not in ui and 'summary.get("contract", {})' not in ui,
    "legacy contract engine code is isolated from the current UI": 'func can_accept_contract(contract_id: String)' in manager and 'selected_contract_id' not in ui,
    "old contract definitions remain covered by a compatibility smoke fixture": 'ContentRegistry.EXPEDITION_CONTRACTS.size() >= 5' in smoke and 'contract_manager.can_accept_contract("none")' in smoke,
    "stable application identity remains unchanged": 'config/version="0.61.0"' in project,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    print("RETIRED CONTRACT UI REGRESSION FAILED: " + ", ".join(failed))
    sys.exit(1)
print(f"RETIRED CONTRACT UI REGRESSION PASSED: {len(checks)}/{len(checks)}")
print("Legacy contract data is retained only for backward compatibility; it is not offered by the current campaign UI.")

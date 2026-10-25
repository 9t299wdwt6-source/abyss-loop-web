"""Stage 83 source guard: inventory-to-settlement flow must be exercised by the release runtime gate."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
runtime_test = (ROOT / "tests/inventory_settlement_runtime_acceptance.gd").read_text(encoding="utf-8")
runtime_gate = (ROOT / "tools/run_runtime_gate.py").read_text(encoding="utf-8")
packager = (ROOT / "tools/package_release.py").read_text(encoding="utf-8")
preflight = (ROOT / "tools/release_preflight.py").read_text(encoding="utf-8")
checks = {
    "the runtime test refuses to run against a player's normal save profile": 'OS.get_environment("ABYSS_LOOP_RUNTIME_QA") != "1"' in runtime_test and "get_tree().quit(2)" in runtime_test,
    "the integration test starts a real run through the production manager API": 'manager.start_run("standard", 83008301)' in runtime_test,
    "the test fills the actual configured backpack capacity": "InventorySystemScript.BACKPACK_CAPACITY" in runtime_test and "_store_run_item" in runtime_test,
    "duplicate IDs are rejected before the test checks state immutability": all(x in runtime_test for x in ("duplicate item IDs are rejected", "bag_before_duplicate", "ejections_before_duplicate", "dust_before_duplicate")),
    "overflow checks FIFO eviction and real dust calculation": all(x in runtime_test for x in ("get_ejection_echo_dust", "last_inventory_evicted_item", "inventory_ejections_count", "inventory_ejections_dust")),
    "manual equipment uses the production equip API and enforces unique location": all(x in runtime_test for x in ("equip_bag_item(return_overflow_id)", "_item_is_equipped", "all live bag and equipment instance IDs are unique after restore")),
    "the active checkpoint is saved and restored by a second manager": all(x in runtime_test for x in ("save_run_snapshot()", "restore_saved_run()", "preserves exact bag order")),
    "return settlement banks carried gear and full ejection dust": all(x in runtime_test for x in ("end_run(\"return\")", "safe return banks the full cumulative overflow dust", "carried backpack loot survives a safe return")),
    "ejected gear is not banked after a safe return": "the ejected item is not restored to the permanent armory" in runtime_test and "GameState.get_armory_item(oldest_item_id).is_empty()" in runtime_test,
    "settlement retry verifies idempotency across all durable resources": all(x in runtime_test for x in ("_already_settled", "retries cannot double-pay dust", "retries cannot duplicate campaign completion")),
    "defeat path verifies equipped retention and carried-loot loss": all(x in runtime_test for x in ("end_run(\"defeat\")", "equipped loot survives defeat", "unequipped bag loot is lost on defeat")),
    "the runtime test is part of the fail-closed release gate": all(x in runtime_gate for x in ("Inventory-to-settlement runtime acceptance", "inventory_settlement_runtime_acceptance_runner.tscn", "len(steps) == 8")),
    "runtime report validation requires all eight gates": "Inventory-to-settlement runtime acceptance" in packager and "all eight runtime gates" in packager,
    "Stage 83 documents and runner are mandatory release files": all(x in packager and x in preflight for x in ("ROADMAP_STATUS_STAGE83_RU.md", "STAGE83_INVENTORY_TO_SETTLEMENT_RUNTIME_BUILD_REPORT_RU.md", "INVENTORY_SETTLEMENT_RUNTIME_CHECKLIST_STAGE83_RU.md", "tests/inventory_settlement_runtime_acceptance.gd", "tests/stage83_static_test_report.txt")),
    "settlement code remains idempotent at the persistent resource boundary": "settled_expedition_ids.has(requested_run_id)" in state and "echo_dust = clampi(echo_dust + echo_dust_awarded" in state,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    raise SystemExit("STAGE 83 INVENTORY SETTLEMENT REGRESSION FAILED: " + "; ".join(failed))
print(f"STAGE 83 INVENTORY SETTLEMENT REGRESSION PASSED: {len(checks)}/{len(checks)} source guards")
print("Runtime behavior is verified only when the isolated Godot 4.7.2 gate executes inventory_settlement_runtime_acceptance_runner.tscn.")

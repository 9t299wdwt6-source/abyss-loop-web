"""Stage 80 regression: overflow loot converts to persistent base resource once."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
base = (ROOT / "scripts/systems/base_system.gd").read_text(encoding="utf-8")
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
checks = {
    "overflow item conversion depends on rarity, rank, upgrade and power with cap": all(x in inventory for x in ("func get_ejection_echo_dust", '"Реликтовый"', '"Эпический"', '"upgrade_level"', '"power"', "clampi(rarity_value + rank_bonus + upgrade_bonus + power_bonus, 1, 10)")),
    "each ejection increments cumulative conversion value and count even if history is trimmed": all(x in manager for x in ('"inventory_ejections_dust": 0', '"inventory_ejections_count": 0', 'get_ejection_echo_dust(last_inventory_evicted_item)', '"inventory_ejections_dust"] = clampi', '"inventory_ejections_count"] = mini')), 
    "older snapshots without cumulative values derive from legacy ejection records": all(x in manager for x in ("Old saves only keep a bounded list", 'if run_ledger.has("inventory_ejections_dust")', 'migrated_dust = mini', '"inventory_ejections_count"] = clampi')),
    "settlement adds echo dust atomically with summary and checkpoint removal": all(x in state for x in ("var echo_dust: int = 0", 'earned.get("inventory_ejections_dust"', 'echo_dust = clampi(echo_dust + echo_dust_awarded', '"kept_echo_dust": echo_dust_awarded', '"echo_dust": echo_dust', '"settled_expedition_ids": settled_expedition_ids.duplicate(true)')),
    "settlement idempotency returns the committed result when the same run id is retried": all(x in state for x in ("MAX_SETTLED_EXPEDITION_IDS := 1000", 'settled_expedition_ids.has(requested_run_id)', 'already_committed["_already_settled"] = true', 'settled_expedition_ids.append(summary_run_id)')),
    "failed settlement save rolls back dust and settlement identifiers": all(x in state for x in ('var old_echo_dust := echo_dust', 'old_settled_expedition_ids: Array = settled_expedition_ids.duplicate(true)', 'echo_dust = old_echo_dust', 'settled_expedition_ids = old_settled_expedition_ids')),
    "save validation accepts legacy profiles and validates bounded dust/idempotency ledger": all(x in save for x in ('"echo_dust"', '"settled_expedition_ids"', 'settled_ids_value.size() > 1000', 'int(data.get("echo_dust", 0)) > 1000000')),
    "run save validation bounds cumulative overflow resource values": all(x in save for x in ('"inventory_ejections_dust", "inventory_ejections_count"', 'int(ledger[aggregate_key]) > 1000000')),
    "salvage building requires echo dust and generic upgrades roll back on failed save": all(x in registry for x in ('"echo_dust_base": 3', '"echo_dust_step": 2')) and all(x in base for x in ('"echo_dust": int(def.get("echo_dust_base", 0))', 'GameState.echo_dust < dust_cost', 'GameState.echo_dust -= dust_cost', 'if not GameState.save_now():', 'GameState.echo_dust = old_echo_dust')),
    "base screen shows resource and recycler price includes the new cost": all(x in ui for x in ('Пыль утраченных вещей: %d', 'Постоянный ресурс · пыль утраченных вещей', 'cost_text += " · %d пыли"', 'Пыль утраченных вещей", "+%d · всего %d"')),
}
failed = [n for n, ok in checks.items() if not ok]
for name, ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    print("STAGE 80 EJECTION RESOURCE REGRESSION FAILED: " + "; ".join(failed))
    sys.exit(1)
print(f"STAGE 80 EJECTION RESOURCE REGRESSION PASSED: {len(checks)}/{len(checks)} source guards")
print("Static source-level evidence only. Godot 4.7.2 runtime and settlement/save reload must still be tested in-engine.")

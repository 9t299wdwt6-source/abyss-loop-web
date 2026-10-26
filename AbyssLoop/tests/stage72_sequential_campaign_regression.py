"""Source guards for sequential, persistent-equipment eight-floor campaign capture."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
capture = (ROOT / "tests/stage72_sequential_campaign_capture.gd").read_text(encoding="utf-8")
scene = (ROOT / "tests/stage72_sequential_campaign_runner.tscn").read_text(encoding="utf-8")
workflow = (ROOT.parent / ".github/workflows/abyssloop-engine-qa.yml").read_text(encoding="utf-8")
analyzer = (ROOT / "tools/real_run_balance.py").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
game_state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")

checks = {
    "capture exercises all eight ordered floors with three deterministic campaign seeds":
        "FLOOR_NUMBERS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]" in capture and
        "CAMPAIGN_SEEDS: Array[int] = [8676203, 8676211, 8676221]" in capture,
    "new profile reset occurs once per campaign, outside individual floor capture":
        capture.count("GameState.reset_progress()") == 1 and
        "func _capture_campaign(seed_value: int)" in capture and "func _capture_floor(" in capture,
    "campaign can advance only when the production durable unlock frontier permits it":
        "if int(GameState.highest_unlocked_floor) < floor_number:" in capture and
        "GameState.highest_unlocked_floor" in game_state and
        "manager.start_run(\"standard\", seed_value, \"standard\", \"none\", \"standard\", floor_number)" in capture,
    "persistent armory equipment uses production item-power comparison and equip transaction":
        "func _equip_better_armory_items() -> int:" in capture and
        "inventory.item_power(candidate)" in capture and "GameState.equip_item(item_id)" in capture,
    "capture records campaign seed, start gear and armory progression":
        '"capture_group"] = "sequential_campaign"' in capture and
        '"capture_campaign_seed"] = campaign_seed' in capture and
        '"capture_start_loadout_items"] = starting_loadout_count' in capture and
        '"capture_start_armory_items"] = starting_armory_count' in capture and
        '"capture_armory_equips_before_floor"] = armory_equips_before_floor' in capture,
    "capture runs production route, combat, event, perk, and legal placement":
        "manager._tick_route(ROUTE_SCALED_DELTA)" in capture and
        "manager._tick_combat(COMBAT_SCALED_DELTA)" in capture and
        "manager.resolve_event_choice(choice_id)" in capture and
        "manager.choose_perk(perk_id)" in capture and
        "manager.tile_system.can_place(" in capture and
        "manager.tile_system.can_place_world(" in capture,
    "balance harness does not force hero, enemy, or reward stats":
        all(token not in capture for token in [
            'manager.hero["hp"] =', 'manager.hero["attack"] =',
            'manager.enemy["hp"] =', 'fighter["hp"] =',
            'manager.run_ledger["scrap"] ='
        ]),
    "natural defeat ends the campaign without being mislabeled as a harness error":
        'if not final_floor_cleared:' in capture and
        '"not_a_balance_verdict": true' in capture and
        '"not_human_playtest": true' in capture,
    "report separates sequential campaign from isolated cold starts by scenario":
        'capture_group = str(row.get("capture_group", "general"))' in analyzer and
        'row["capture_group"] = capture_group' in analyzer and
        'row["capture_group"]' in analyzer,
    "runner scene loads the campaign harness and CI preserves JSON plus Markdown":
        'path="res://tests/stage72_sequential_campaign_capture.gd"' in scene and
        "res://tests/stage72_sequential_campaign_runner.tscn" in workflow and
        "STAGE72_SEQUENTIAL_CAMPAIGNS.json" in workflow and
        "STAGE72_SEQUENTIAL_CAMPAIGN_REPORT.md" in workflow,
    "production floor settlement remains responsible for completing floors and unlocking next":
        "func _maybe_finish_floor_after_boss()" in manager and
        "highest_unlocked_floor" in manager and "settle_expedition(" in manager,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"[{'PASS' if ok else 'FAIL'}] {name}")
if failed:
    raise SystemExit("STAGE72 SEQUENTIAL CAMPAIGN REGRESSION FAILED: " + ", ".join(failed))
print(f"STAGE72 SEQUENTIAL CAMPAIGN REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Static checks only; in-engine capture results must be inspected before tuning balance.")

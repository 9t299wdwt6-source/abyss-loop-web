"""Regression guards for hidden landscape discoveries and their one-time event payoff."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
registry=(ROOT/"scripts/core/content_registry.gd").read_text(encoding="utf-8")
manager=(ROOT/"scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
event_system=(ROOT/"scripts/systems/expedition_event_system.gd").read_text(encoding="utf-8")
smoke=(ROOT/"tests/smoke_test.gd").read_text(encoding="utf-8")
checks={
    "secret events require explicit per-run discovery flags and resolve once": all(token in registry for token in ('"archive_rift_echo": {','"sealed_brood": {','"requires_flag": "secret_archive_rift_found"','"requires_flag": "secret_nursery_snare_found"','"resolved_flag": "secret_archive_rift_claimed"','"resolved_flag": "secret_nursery_snare_claimed"')),
    "secret events bypass regular random rolls only after discovery": "guaranteed_candidates" in event_system and 'definition.get("guaranteed_when_flag", false)' in event_system and "candidates = guaranteed_candidates" in event_system,
    "landscape secrets require orthogonal neighboring tiles in the same route sector": "LANDSCAPE_SECRET_RECIPES" in manager and "Vector2i(col + 1, row), Vector2i(col, row + 1)" in manager and 'neighbor_tile.get("route_index", -1)) != route_index' in manager,
    "secret flags are saved in the existing expedition ledger, logged to the player and do not replay": 'run_ledger["event_flags"] = flags' in manager and 'bool(flags.get(flag_id, false))' in manager and "ТАЙНА ОБНАРУЖЕНА" in manager,
    "secret event outcomes have distinct risk/reward decisions and named loot": all(token in registry for token in ('"seal_echo"','"follow_echo"','"spare_brood"','"hunt_brood"','"danger_delta": 0.15','"spawn_bonus": 0.16','"grant_item_id": "echo_chart_core"','"grant_item_id": "riftwalker_edge"','"grant_item_id": "brood_shell"','"grant_item_id": "snare_hunter_core")),
    "secret item rewards reach the armory and equip only when stronger": '"grant_item_id", ""' in manager and 'inventory_system.make_secret_relic' in manager and 'GameState.register_item(item)' in manager and 'inventory_system.should_equip(item, current)' in manager,
    "secret relic templates have stable catalog IDs and source metadata": all(token in inventory for token in ('const SECRET_RELIC_TEMPLATES', '"echo_chart_core"', '"riftwalker_edge"', '"brood_shell"', '"snare_hunter_core"', '"rarity": "Тайная"')) and '"Секретные реликвии"' in (ROOT / "tools/content_v1_audit.py").read_text(encoding="utf-8"),
    "Godot smoke tests exercise both secrets and duplicate prevention": all(token in smoke for token in ("archive_secret_event", "brood_secret_event", "secret_unseen_event", "_discover_landscape_secrets(7", "_discover_landscape_secrets(8")),
}
failed=[name for name,passed in checks.items() if not passed]
for name,passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    print("LANDSCAPE SECRET REGRESSION FAILED: "+", ".join(failed))
    sys.exit(1)
print(f"LANDSCAPE SECRET REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Source guards only; Godot smoke verifies the event and discovery path at runtime.")

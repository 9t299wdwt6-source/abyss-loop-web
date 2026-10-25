"""Source-level guards for the Prototype 03 encounter/boss integration."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
checks = {
    "config defines a boss cadence": '"boss_loop_interval": 3' in (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8"),
    "two configurable boss profiles exist": '"warden"' in (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8") and '"harvester"' in (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8"),
    "encounter generator supports groups": "func create_encounter(" in (ROOT / "scripts/systems/enemy_system.gd").read_text(encoding="utf-8"),
    "encounter generator supports boss-only fights": "if boss_encounter:" in (ROOT / "scripts/systems/enemy_system.gd").read_text(encoding="utf-8"),
    "route manager forces boss-node fights": "var is_boss_node := index == 0 and loop_count > 0 and loop_count % boss_interval == 0" in (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8"),
    "all encounter members receive independent attack updates": "for fighter_value in attackers:" in (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8"),
    "boss reward guarantees a drop through the shared loot contract": 'if source == "boss":\n\t\treturn 1.0' in (ROOT / "scripts/systems/loot_system.gd").read_text(encoding="utf-8") and 'get_equipment_drop_chance(drop_source, combat_reward_bonus, echo_charges, pending_drop_bonus)' in (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8"),
    "boss statistics persist": '"total_bosses_defeated": total_bosses_defeated' in (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8"),
    "smoke test covers boss and pack generation": "high_threat_pack" in (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8") and "boss_group" in (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8"),
    "boss encounters retain a distinct map marker": '"Б" if boss_encounter else' in (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8"),
    "elite encounters have a distinct map marker": '"Э" if elite_encounter else' in (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8"),
}
failed = [label for label, passed in checks.items() if not passed]
if failed:
    print("COMBAT ENCOUNTER REGRESSION CHECK FAILED")
    for label in failed:
        print(f"- {label}")
    sys.exit(1)
print("COMBAT ENCOUNTER REGRESSION CHECK PASSED:")
for label in checks:
    print(f"- {label}")
print("Note: source-level guard only; run tests/smoke_test.gd in Godot for runtime validation.")

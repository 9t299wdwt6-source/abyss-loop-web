#!/usr/bin/env python3
"""Regression guards for parse failures reproduced from Godot 4.7.2 output."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
checks: list[tuple[bool, str]] = []

def check(condition: bool, label: str) -> None:
    checks.append((bool(condition), label))

game_state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
lines = game_state.splitlines()
comment_lines = [line for line in lines if "expedition risk still scale separately" in line]
check(len(comment_lines) == 1 and comment_lines[0].lstrip().startswith("#"), "continued prose line in GameState remains a comment")

expedition = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
check('var encounter_value: Variant = snapshot.get("encounter_enemies", [])' in expedition, "snapshot encounter list keeps its Variant source")
check("for encounter_entry in encounter_enemies:" in expedition and "for encounter_value in encounter_enemies:" not in expedition, "snapshot loop does not redeclare encounter_value")

tile_system_bytes = (ROOT / "scripts/systems/tile_system.gd").read_bytes()
leading_tabs = []
for number, raw_line in enumerate(tile_system_bytes.splitlines(), start=1):
    prefix = raw_line[:len(raw_line) - len(raw_line.lstrip(b" \t"))]
    if b"\t" in prefix:
        leading_tabs.append(number)
check(not leading_tabs, "tile_system.gd uses consistent spaces for indentation")

ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
check('route_view.get("hovered_world_cell_id", "")' not in ui, "Object.get is not called with a Dictionary-style default")
check("var run_checkpoint_active: bool = GameState.has_saved_expedition()" in ui, "checkpoint state has an explicit bool type")
check("var equipped: bool = GameState.is_item_equipped(item_id)" in ui, "equipment state has an explicit bool type")
check('var can_afford: bool = GameState.scrap >= int(upgrade_cost.get("scrap", 0))' in ui, "armory affordability has an explicit bool type")

base = (ROOT / "scripts/systems/base_system.gd").read_text(encoding="utf-8")
check("var unlocked: bool = GameState.has_research(research_id)" in base, "research unlock state has an explicit bool type")
check('var can_afford: bool = GameState.scrap >= int(definition.get("scrap_cost", 0))' in base, "research affordability has an explicit bool type")
check("var old_scrap: int = int(GameState.scrap)" in base and "var old_crystals: int = int(GameState.crystals)" in base, "rollback balances use explicit integer types")

smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
check("var configured_boss_group: Array = enemy_system.create_encounter" in smoke, "boss fixture uses unique variable name")
check("var boss_group: Array = enemy_system.create_encounter" not in smoke, "duplicate boss_group declaration is removed")

passed = sum(ok for ok, _ in checks)
for ok, label in checks:
    print(("PASS" if ok else "FAIL") + ": " + label)
print(f"GODOT PARSE HOTFIX REGRESSION: {passed}/{len(checks)}")
sys.exit(0 if passed == len(checks) else 1)

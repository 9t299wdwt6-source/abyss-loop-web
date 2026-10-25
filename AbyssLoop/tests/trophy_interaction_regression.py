"""Stage 71 source guards for biome trophies, persistent bestiary and tile strategy."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
loot = (ROOT / "scripts/systems/loot_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
game_state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
saves = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
checks = {
    "four biome families drop distinct named trophy materials": all(x in loot for x in ('"spore_pollen"', '"prism_fragment"', '"bone_fragment"', '"echo_residue"')) and "func roll_biome_trophy" in loot,
    "matching landscape increases trophy chance with an explicit cap": 'active_tile_ids.has(str(definition.get("tile_id", "")))' in loot and "minf(0.96, chance + 0.22)" in loot,
    "elite drops are more reliable and quantity is bounded": "maxf(chance, 0.86)" in loot and "var amount := 3 if is_boss else (2 if is_elite else 1)" in loot,
    "trophies are stored in run ledger and survive checkpoint export/restore": '"trophy_drops": _empty_trophy_counts()' in manager and 'run_ledger["trophy_drops"] = _normalize_trophy_counts' in manager and '"run_ledger": run_ledger.duplicate(true)' in manager,
    "family trophies provide distinct short-term rewards": all(x in manager for x in ('"spore":', '"crystal":', '"bone":', '"echo":', 'echo_item_charges', 'ТРОФЕЙ')),
    "echo residue increases item chance through the shared formula and a charge is consumed only after a non-boss item drop": 'float(capped_echo_charges) * 0.05' in loot and 'get_equipment_drop_chance(drop_source, combat_reward_bonus, echo_charges, pending_drop_bonus)' in manager and 'if not is_boss and echo_charges > 0' in manager and 'run_ledger["echo_item_charges"] = maxi(0, echo_charges - 1)' in manager,
    "bestiary totals are added during the same settlement transaction as run rewards": 'bestiary_trophies[trophy_id] = mini(100000000' in game_state and 'var old_bestiary_trophies := bestiary_trophies.duplicate(true)' in game_state and 'bestiary_trophies = old_bestiary_trophies' in game_state,
    "older profiles and run checkpoints safely default missing trophy fields": 'saved.get("bestiary_trophies", {})' in game_state and 'run_ledger.get("trophy_drops", {})' in manager and 'if ledger.has("trophy_drops")' in saves,
    "invalid trophy keys/counts and echo charges are rejected by save validation": 'trophy_id not in ["spore_pollen", "prism_fragment", "bone_fragment", "echo_residue"]' in saves and 'int(ledger.get("echo_item_charges", 0)) > 4' in saves,
    "debrief and shelter display run trophies and permanent bestiary totals": 'Бестиарий трофеев' in ui and 'Трофеи за экспедицию' in ui and 'earned_trophies' in ui,
    "four new tile recipes use supported bounded risk, reward and healing effects": all(x in registry for x in ('"spore_archive"', '"crystal_hunt"', '"bone_ward"', '"echo_signal"')),
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    print("TROPHY INTERACTION REGRESSION FAILED: " + ", ".join(failed))
    sys.exit(1)
print(f"TROPHY INTERACTION REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Source-level only. GDScript runtime, visual layout, balance and real save/reload remain separate acceptance gates.")

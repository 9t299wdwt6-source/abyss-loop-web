"""Checks the cartographer shelter building affects real, weighted tile draws."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
registry=(ROOT/"scripts/core/content_registry.gd").read_text(encoding="utf-8")
state=(ROOT/"scripts/core/game_state.gd").read_text(encoding="utf-8")
tile=(ROOT/"scripts/systems/tile_system.gd").read_text(encoding="utf-8")
smoke=(ROOT/"tests/smoke_test.gd").read_text(encoding="utf-8")
checks={
    "cartographer is a regular upgradeable shelter building with clear costs and max level": '"cartographer": {' in registry and '"max_level": 5' in registry and 'Обсерватория картографов' in registry,
    "old saves migrate the new building to a safe zero level": '"cartographer": 0' in state and 'for building_id in DEFAULT_BUILDINGS.keys()' in state,
    "building level provides a bounded rare tile weight multiplier": "func get_rare_tile_weight_multiplier()" in state and 'minf(0.50, float(level) * per_level)' in state,
    "the shared weighted-draft function applies the multiplier to route and field card draws": 'tile_id in ["rift", "signal", "archive", "nursery", "fault_line", "spore_garden", "crystal_hive", "bone_orchard", "echo_obelisk", "lost_convoy", "hunter_marker"]' in tile and 'GameState.get_rare_tile_weight_multiplier()' in tile,
    "Godot smoke compares level-zero and level-five draw counts with fixed seeds": 'base_rare_rng.seed = 7741' in smoke and 'observatory_rng.seed = 7741' in smoke and 'observatory_rare_count > base_rare_count' in smoke,
}
failed=[name for name,ok in checks.items() if not ok]
for name,ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    print("CARTOGRAPHER BUILDING REGRESSION FAILED: "+", ".join(failed))
    sys.exit(1)
print(f"CARTOGRAPHER BUILDING REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Source checks do not replace Godot runtime; smoke checks the actual weighted draw effect.")

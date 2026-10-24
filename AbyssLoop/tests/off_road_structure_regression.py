"""Regression guard for unlockable off-road structures with real sector effects."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
registry=(ROOT/"scripts/core/content_registry.gd").read_text(encoding="utf-8")
tile=(ROOT/"scripts/systems/tile_system.gd").read_text(encoding="utf-8")
smoke=(ROOT/"tests/smoke_test.gd").read_text(encoding="utf-8")
checks={
    "archive and nursery are registered as visible structures": all(token in registry for token in ('"archive": {','"nursery": {','"АРХИВ"','"ПИТОМНИК"')),
    "structures appear only in the rare unlock pool at lower weights": 'choices.append("archive")' in tile and 'choices.append("nursery")' in tile and '"archive": 0.35' in tile and '"nursery": 0.30' in tile,
    "archive produces materials, crystals and reward bonus on sector visits": '"archive":' in tile and 'resource_system.add(ledger, "crystals", 1)' in tile and 'result.reward_bonus = 0.08' in tile and 'archive_result' in smoke,
    "nursery raises encounter chance and enemy strength in exchange for payout": 'result.spawn_bonus = 0.28' in tile and 'result.enemy_bonus = 0.12' in tile and 'result.reward_bonus = 0.25' in tile and 'nursery_result' in smoke,
    "synergy recipes cover both structure planning and dangerous combinations": all(token in registry for token in ('"archive_cache"','"archive_ward"','"nursery_rift"','"nursery_snare"')),
}
failed=[name for name,ok in checks.items() if not ok]
for name,ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    print("OFF-ROAD STRUCTURE REGRESSION FAILED: "+", ".join(failed))
    sys.exit(1)
print(f"OFF-ROAD STRUCTURE REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Source guards only; the existing Godot smoke suite exercises visit effects and weighted discovery.")

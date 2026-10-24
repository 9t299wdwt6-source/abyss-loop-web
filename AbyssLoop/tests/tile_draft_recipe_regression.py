"""Static guards for weighted tile drafting and the expanded route-tile recipe book."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
tile = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "all eight tile types have explicit draw weights": all(f'"{tile_id}":' in tile for tile_id in ("cache", "hunt", "ward", "snare", "rift", "signal", "archive", "nursery")) and "const TILE_DRAW_WEIGHTS" in tile,
    "weighted choice respects rare-tile unlock gate": "if unlock_rift:" in tile and "total_weight" in tile and "roll -= maxf" in tile and "choices.append(\"signal\")" in tile and "choices.append(\"archive\")" in tile and "choices.append(\"nursery\")" in tile,
    "new recipes cover resource, safer ambush and dangerous resonance": all(token in registry for token in ('"cache_hunt"', '"snare_hunt"', '"signal_ward"', '"rift_signal"', '"archive_cache"', '"archive_ward"', '"nursery_rift"', '"nursery_snare"')),
    "real Godot smoke tests bound rare tile frequency with a fixed seed": "tile_draw_rng.seed = 23019" in smoke and "locked_rare_tiles == 0" in smoke and "unlocked_rare_tiles >= 140" in smoke,
    "real Godot smoke tests exercise recipe rewards": all(token in smoke for token in ("cache_hunt_synergy", "snare_hunt_synergy", "rift_signal_synergy", "archive_cache_synergy", "nursery_rift_synergy")),
}
failed=[label for label,passed in checks.items() if not passed]
for label,passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {label}")
if failed:
    print("TILE DRAFT/RECIPE REGRESSION FAILED: "+", ".join(failed))
    sys.exit(1)
print(f"TILE DRAFT/RECIPE REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("These source guards do not replace Godot runtime smoke.")

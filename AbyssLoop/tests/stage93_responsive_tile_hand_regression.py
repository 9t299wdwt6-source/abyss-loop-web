#!/usr/bin/env python3
"""Stage 93 guards for narrow-viewport tile-hand reflow."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "scripts" / "ui" / "ui_controller.gd").read_text(encoding="utf-8")
runtime = (ROOT / "tests" / "expedition_runtime_acceptance.gd").read_text(encoding="utf-8")

checks = {
    "one-column breakpoint is explicit and stable": "return 1 if viewport_width < 360.0 else 2" in ui,
    "initial expedition layout uses the responsive column rule": "tile_hand_grid.columns = _get_tile_hand_columns_for_width(get_viewport_rect().size.x)" in ui,
    "very narrow cards release their fixed minimum width": "Vector2(0 if tile_hand_grid.columns == 1 else 148, 64)" in ui,
    "cards expand horizontally in one-column mode": "button.size_flags_horizontal = Control.SIZE_EXPAND_FILL" in ui,
    "resizing within compact layout can update columns without rebuilding the expedition": "_refresh_tile_hand_layout()\n\t\treturn" in ui and "tile_hand_grid.columns = desired_columns" in ui,
    "tile-hand refresh clears only the card signature before syncing": 'tile_hand_signature = ""\n\t_sync_expedition_view(true)' in ui,
    "the selected tile identity still binds to the existing hand index": 'Callable(self, "_on_tile_selected").bind(i)' in ui,
    "runtime acceptance checks the 320, 360 and 390 pixel boundaries": all(f'"_get_tile_hand_columns_for_width", {width}.0' in runtime for width in (320, 360, 390)),
}
failed = [label for label, passed in checks.items() if not passed]
for label, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + label)
if failed:
    print(f"STAGE 93 RESPONSIVE TILE HAND FAILED: {len(failed)}/{len(checks)}")
    sys.exit(1)
print(f"STAGE 93 RESPONSIVE TILE HAND PASSED: {len(checks)}/{len(checks)} source contracts")
print("Source checks describe layout behavior; visual browser acceptance remains separate.")

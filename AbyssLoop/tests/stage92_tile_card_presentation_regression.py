#!/usr/bin/env python3
"""Stage 92: restrained category styling and unambiguous selection state for tile-hand cards."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "scripts" / "ui" / "ui_controller.gd").read_text(encoding="utf-8")
runtime = (ROOT / "tests" / "expedition_runtime_acceptance.gd").read_text(encoding="utf-8")

checks = {
    "tile cards classify placement with a readable category tooltip": 'button.tooltip_text = "Тип: %s\\n%s%s" % [kind_label' in ui,
    "category names remain readable independently of color": all(f'"{key}": return "{label}"' in ui for key, label in [
        ("economy", "снабжение"), ("danger", "опасность"), ("support", "поддержка"),
        ("control", "контроль"), ("rare", "редкость"), ("knowledge", "знание"),
    ]),
    "economy cards use a restrained earthy palette": '"#302f27"' in ui and '"#827b54"' in ui,
    "danger cards use a muted red-brown palette": '"#342b2a"' in ui and '"#8d6258"' in ui,
    "support cards use a muted moss palette": '"#29352c"' in ui and '"#5d8060"' in ui,
    "control cards use a muted blue-grey palette": '"#293438"' in ui and '"#607d84"' in ui,
    "rare cards use a muted violet palette": '"#302b37"' in ui and '"#817095"' in ui,
    "knowledge cards use a muted slate palette": '"#2a3038"' in ui and '"#647c95"' in ui,
    "selected card uses a single amber border rather than a bright full fill": 'Color("#efc36b") if selected else category_edge' in ui and 'fill.lerp(Color("#efc36b"), 0.10)' in ui,
    "hover, pressed, focus and disabled states use explicit styleboxes": all(f'button.add_theme_stylebox_override("{state}", {style})' in ui for state, style in [
        ("normal", "normal"), ("hover", "hover"), ("pressed", "pressed"),
        ("focus", "focus"), ("disabled", "disabled"),
    ]),
    "high-contrast mode retains a bright readable border": 'Color("#f0f6ef") if high_contrast' in ui and 'Color("#f4f8ee") if high_contrast else Color("#fff2a8")' in ui,
    "existing zone and description remain in the tooltip": '"Размещение: только ландшафт.' in ui and 'str(tile.get("description", ""))' in ui,
    "Godot runtime gate checks neutral and selected tile-card styles": 'idle_card_style.border_width_left == 1' in runtime and 'selected_card_style.border_color == Color("#efc36b")' in runtime,
    "the tile-hand index and selection callback are unchanged": 'Callable(self, "_on_tile_selected").bind(i)' in ui and 'func _on_tile_selected(index: int) -> void:' in ui,
}

failed = [label for label, passed in checks.items() if not passed]
for label, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + label)
if failed:
    print(f"STAGE 92 TILE CARD PRESENTATION FAILED: {len(failed)}/{len(checks)}")
    sys.exit(1)
print(f"STAGE 92 TILE CARD PRESENTATION PASSED: {len(checks)}/{len(checks)} source contracts")
print("Source contracts do not replace Godot runtime or visual acceptance.")

"""Static guard for the first approved pixel-art theme pass; not a Godot runtime test."""
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []
asset = ROOT / "assets/background/abyss_pixel_backdrop.png"
if not asset.is_file() or asset.stat().st_size < 1500:
    errors.append("pixel-art abyss background asset is missing or suspiciously small")
else:
    try:
        data = asset.read_bytes()
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            errors.append("backdrop does not have a valid PNG signature")
        elif len(data) < 24:
            errors.append("backdrop PNG is truncated")
        else:
            width, height = struct.unpack(">II", data[16:24])
            if (width, height) != (480, 300):
                errors.append(f"expected 480x300 low-resolution pixel-art backdrop, got {(width, height)}")
    except Exception as exc:
        errors.append(f"cannot inspect backdrop PNG: {exc}")

ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
route = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
content = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
project = (ROOT / "project.godot").read_text(encoding="utf-8")
localization = (ROOT / "localization/strings_ru.json").read_text(encoding="utf-8")
checks = {
    "UI preloads the approved environment asset": 'preload("res://assets/background/abyss_pixel_backdrop.png")' in ui,
    "UI uses nearest-neighbour scaling for pixel art": "CanvasItem.TEXTURE_FILTER_NEAREST" in ui,
    "route map uses themed background": 'draw_texture_rect(ABYSS_BACKDROP' in route,
    "route markers use blocky rectangular silhouettes": "draw_rect(marker_rect.grow(-3), fill, true)" in route,
    "route tiles have low-resolution type glyphs": "func _draw_pixel_symbol" in route and '"signal":' in route,
    "hero token is independently drawn in original pixel blocks": "Tiny block-built explorer marker" in route,
    "brand label no longer claims neutral theme": "header.brand.subtitle" in ui and "ЭКСПЕДИЦИЯ · ЗАМКНУТЫЙ ПУТЬ · ЭХО ГЛУБИН" in localization and "НЕЙТРАЛЬНЫЙ ПРОТОТИП ROGUELITE" not in ui,
    "themed route cell type names exist": "Каменный уступ" in content and "Светлая ниша" in content,
    "themed creature names exist without changing ids": '"scout": {' in content and '"name": "Щелкун-ползун"' in content,
    "project keeps stable game identity and separately versions the prototype": 'config/name="Abyss Loop"' in project and 'config/version="0.61.0"' in project,
}
for desc, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {desc}")
    if not ok:
        errors.append(desc)
if errors:
    print("THEME ART REGRESSION FAILED:\n- " + "\n- ".join(errors))
    sys.exit(1)
print("THEME ART REGRESSION PASSED. Visual judgment and GDScript compilation still require Godot runtime testing.")

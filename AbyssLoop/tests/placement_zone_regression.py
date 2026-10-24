"""Placement-zone guards for flexible cards and field-only special structures."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
tile = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "all tile types declare their intended zone": all(token in registry for token in ('"name": "Геодезический тайник", "short": "ТАЙНИК", "kind": "economy", "placement_zone": "any"', '"name": "Место следопыта", "short": "СЛЕД", "kind": "danger", "placement_zone": "any"', '"name": "Корневой оберег", "short": "ОБЕРЕГ", "kind": "support", "placement_zone": "any"', '"name": "Глубинный разлом", "short": "РАЗЛОМ", "kind": "danger", "placement_zone": "any"', '"name": "Сеть резонанса", "short": "СЕТЬ", "kind": "control", "placement_zone": "any"', '"name": "Кристалл-резонатор", "short": "КРИСТАЛЛ", "kind": "rare", "placement_zone": "any"', '"name": "Архив старой экспедиции", "short": "АРХИВ", "kind": "knowledge", "placement_zone": "landscape"', '"name": "Питомник бездны", "short": "ПИТОМНИК", "kind": "danger", "placement_zone": "landscape"')),
    "the game and offline content audit validate placement zone values": 'tile.get("placement_zone", "")' in (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8") and 'tile.get("placement_zone") not in {"any", "road", "landscape"}' in (ROOT / "tools/content_v1_audit.py").read_text(encoding="utf-8"),
    "road validator rejects field-only tiles and field validator rejects road-only tiles": 'placement_zone == "landscape"' in tile and 'placement_zone == "road"' in tile and 'can_place(route, placed_tiles, cell_index, tile)' in manager and 'can_place_world(route, world_tiles, cell_id, tile)' in manager,
    "placement previews call the exact same zone-aware validators": 'can_place(route, placed_tiles, index, tile)' in tile and 'can_place_world(route, world_tiles, cell_id, tile)' in tile,
    "hand card tells the player that special structures belong on the field": 'var zone_hint := " · ПОЛЕ"' in ui and "Размещение: только ландшафт." in ui,
    "Godot smoke covers road rejects, field accepts and both previews": all(token in smoke for token in ('can_place(route, {}, 1, {"id": "archive"})', 'can_place_world(route, {}, "2:0", {"id": "archive"})', "archive_road_preview", "archive_field_preview")),
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    print("PLACEMENT ZONE REGRESSION FAILED: " + ", ".join(failed))
    sys.exit(1)
print(f"PLACEMENT ZONE REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Source guards only; Godot smoke covers the live placement methods.")

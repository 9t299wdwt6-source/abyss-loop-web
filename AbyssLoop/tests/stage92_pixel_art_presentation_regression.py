"""Source checks for the Stage92 explorer sprite and equipment-slot pixel glyphs."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
route_view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")

checks = {
    "route character is rendered by a reusable pixel explorer sprite": "func _draw_hero_pixel_sprite(" in route_view and "func _draw_hero_pixel_block(" in route_view,
    "explorer keeps the 24x40-style silhouette and travel hat": "24x40-style proportions" in route_view and "func _draw_hero_pixel_sprite(" in route_view and "hat_light" in route_view,
    "explorer silhouette contains the expected pack, scarf and field lamp": all(token in route_view for token in ["Backpack sits behind the torso", "var scarf :=", "var glow :=", "A brass field lamp"]),
    "hero has four directional facings from the actual route segment": all(direction in route_view for direction in ['return "right" if delta.x > 0 else "left"', 'return "down" if delta.y > 0 else "up"']),
    "walk cycle uses eight deterministic frames and respects reduced motion": "posmod(int(floor(hero_progress * 8.0)), 8)" in route_view and "0 if reduced_motion else" in route_view,
    "equipment icons are generated as small nearest-neighbour pixel textures": "Image.create_empty(ICON_SIZE, ICON_SIZE" in ui and "ImageTexture.create_from_image(image)" in ui and "CanvasItem.TEXTURE_FILTER_NEAREST" in ui,
    "each of the six equipment slots has its own silhouette": all(f'"{slot}":' in ui for slot in ("weapon", "helmet", "armor", "shield", "amulet", "core")),
    "weapon icon variants distinguish bow, spear and curved blades from a sword": all(token in ui for token in ['"precision":', '"wound":', '"siphon", "leech":']),
    "rarity frame colour is drawn independently of the slot silhouette": "_equipment_rarity_color(rarity)" in ui and "rarity_color)" in ui,
    "armory, equipped slots and backpack items carry the underlying item visual data": all(token in ui for token in ['"item_visual": item', '"item_visual": item if not item.is_empty()', "button_data.get(\"item_visual\", {})"]),
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    raise SystemExit("STAGE92 PIXEL ART PRESENTATION REGRESSION FAILED: " + ", ".join(failed))
print(f"STAGE92 PIXEL ART PRESENTATION REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Source-level check only. Inspect the Godot Web/desktop capture for final visual scale and readability.")

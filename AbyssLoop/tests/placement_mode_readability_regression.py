"""Regression for card placement-mode activation, zoning feedback, and map readability."""
from __future__ import annotations
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
tile = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")


def block(source: str, start: str, end: str) -> str:
    first = source.index(start)
    last = source.index(end, first + len(start))
    return source[first:last]


sync = block(ui, "func _sync_expedition_view(rebuild_tiles: bool) -> void:", "func _")
select = block(ui, "func _on_tile_selected(index: int) -> void:", "func _get_tile_placement_block_reason()")
route_draw = block(view, "for i in range(count):", "var hero_point: Vector2")
world_draw = block(view, "func _draw_world_field(route_geometry: Dictionary) -> void:", "func _placement_target_color() -> Color:")
grid_draw = block(view, "func _draw_map_grid(route_geometry: Dictionary) -> void:", "func _visual_biome_for_cell(col: int, row: int) -> int:")

checks = {
    "selected tile passes stable ID, display name, and zone separately":
        'selected_tile_id = str(selected_tile.get("id", ""))' in sync
        and 'selected_tile_name = str(selected_tile.get("name", selected_tile_id))' in sync
        and 'selected_tile_zone = str(selected_tile.get("placement_zone", selected_definition.get("placement_zone", "any")))' in sync
        and 'manager.discovered_world_cells, selected_tile_name, selected_tile_zone)' in sync,
    "placement mode activates only while a selected card has a stable ID":
        'not selected_tile_id.is_empty(), selected_tile_id' in sync
        and 'selected_tile_id = tile_id if allow_placement else ""' in view,
    "selecting the same hand card cancels placement mode":
        'if selected_tile_hand_index == index:\n\t\tselected_tile_hand_index = -1' in select
        and '_sync_expedition_view(true)' in select,
    "road highlights use the selected card's zone-aware validator":
        'var route_probe: Dictionary = {"id": selected_tile_id, "placement_zone": selected_tile_zone}' in route_draw
        and '_placement_rules.can_place(route_cells, placed_tiles, i, route_probe)' in route_draw,
    "landscape highlights use selected tile zone":
        'var placement_probe: Dictionary = {"id": selected_tile_id, "placement_zone": selected_tile_zone}' in world_draw
        and '_placement_rules.can_place_world(route_cells, world_tiles, cell_id, placement_probe, route_shape_id, route_geometry_seed)' in world_draw,
    "valid targets use a zone-specific subdued placement palette":
        'func _placement_target_color() -> Color:' in view
        and '"roadside":' in view and '"landscape":' in view and '"road":' in view
        and 'placement_color.a = 0.72' in route_draw,
    "invalid landscape cells stay muted until hovered":
        'base = Color("#253c32", 0.22)' in world_draw
        and 'outline = Color("#82938a", 0.28)' in world_draw
        and 'base = Color("#c96562", 0.42)' in world_draw
        and 'outline = Color("#ed9d91", 1.0)' in world_draw,
    "landscape status markers only appear on focused cell":
        'if placement_enabled and cell_id == hovered_world_cell_id:' in world_draw
        and 'var status_text := Localization.text("tile.route.status.valid") if world_target_is_valid else Localization.text("tile.route.status.invalid")' in world_draw,
    "passive hover is neutral rather than always green":
        'base = base.lerp(Color("#b9c8b4"), 0.08)' in world_draw
        and 'var hover_color := Color("#a5b2a7")' in route_draw,
    "route and landscape labels are focus-gated":
        'if i == hovered_cell_index or high_contrast:' in route_draw
        and 'if cell_id == hovered_world_cell_id or high_contrast:' in world_draw,
    "terrain grid is quieter outside placement mode":
        'var grid_alpha := 0.20 if placement_enabled else 0.035' in grid_draw
        and '1.25 if placement_enabled else 0.8' in grid_draw,
    "canonical road / roadside / deep-landscape validators remain intact":
        'placement_zone in ["landscape", "roadside"]' in tile
        and 'placement_zone == "roadside" and not world_cell_is_roadside_for_seed' in tile
        and 'placement_zone == "landscape" and is_map_world_cell_id(cell_id) and world_cell_is_roadside_for_seed' in tile,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    raise SystemExit("PLACEMENT MODE READABILITY REGRESSION FAILED: " + "; ".join(failed))


def road_allowed(zone: str, node: int, occupied: bool = False) -> bool:
    return not occupied and node != 0 and zone not in {"roadside", "landscape"}


def world_allowed(zone: str, cell: str, occupied: bool = False) -> bool:
    if occupied or cell == "road":
        return False
    if zone == "road":
        return False
    if zone == "roadside":
        return cell == "roadside"
    if zone == "landscape":
        return cell == "deep"
    return zone == "any" and cell in {"roadside", "deep"}


zone_cases = [
    ("road", "road", 2, True, False),
    ("road", "roadside", 2, False, False),
    ("road", "landscape", 2, False, False),
    ("roadside", "road", 2, False, False),
    ("roadside", "roadside", 2, False, True),
    ("roadside", "landscape", 2, False, False),
    ("landscape", "road", 2, False, False),
    ("landscape", "roadside", 2, False, False),
    ("landscape", "landscape", 2, False, True),
    ("any", "road", 2, True, False),
    ("any", "roadside", 2, True, True),
    ("any", "landscape", 2, True, True),
]
for zone, cell, node, expected_road, expected_world in zone_cases:
    assert road_allowed(zone, node) == expected_road, (zone, cell, "road")
    assert world_allowed(zone, cell) == expected_world, (zone, cell, "world")
assert not road_allowed("road", 0), "starting route node must never accept placement"
assert not road_allowed("road", 2, occupied=True), "occupied road node must never accept placement"
assert not world_allowed("any", "road", occupied=True), "occupied world cell must reject placement"
print(f"PLACEMENT MODE READABILITY REGRESSION PASSED: {len(checks)}/{len(checks)} source checks + {len(zone_cases) + 3} zone truth-table guards")
print("Source/model checks only; live visuals and pointer/touch behavior still require Godot 4.7.2 runtime acceptance.")

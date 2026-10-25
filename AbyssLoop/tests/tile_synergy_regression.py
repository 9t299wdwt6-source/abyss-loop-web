"""Static guard for the data-driven tile-synergy feature. Does not replace Godot runtime tests."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
tile_system = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
route_view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "control and rare tile definitions exist": '"snare": {' in registry and '"signal": {' in registry,
    "new recipes add resource, safety and risk/reward choices": all(token in registry for token in ('"cache_hunt"', '"snare_hunt"', '"signal_ward"', '"rift_signal"', '"archive_cache"', '"archive_ward"', '"nursery_rift"', '"nursery_snare"')) and "cache_hunt_pair" in smoke and "rift_signal_pair" in smoke,
    "synergies have stable ids and effect maps": '"id": "supply_ward"' in registry and '"effects": {"scrap": 4}' in registry,
    "adjacency supports circular route wrapping": "posmod(index - 1, route_size)" in tile_system and "posmod(index + 1, route_size)" in tile_system,
    "neighbor effect types are aggregated": all(key in tile_system for key in ('"scrap"', '"heal"', '"reward_bonus"', '"spawn_bonus"', '"enemy_bonus"')),
    "placement preview provides forecasts and rejection reasons": "func get_placement_preview" in tile_system and 'Localization.text("tile.forecast.route_baseline")' in tile_system and '"reason"' in tile_system,
    "manager applies synergies to actual run state": 'resource_system.add(run_ledger, "scrap", synergy_scrap)' in manager and 'spawn_bonus += float(synergy.get("spawn_bonus", 0.0))' in manager and 'strength_bonus += float(synergy.get("enemy_bonus", 0.0))' in manager,
    "route view reports mouse hover": "signal cell_hovered(cell_index: int)" in route_view and "func _find_closest_cell" in route_view,
    "UI previews selected tile on hovered landscape cell": "_on_world_cell_hovered" in ui and "get_world_placement_preview(manager.route, manager.world_tiles, cell_id, selected_tile, manager.equipment, manager.get_route_shape_id(), manager.get_route_geometry_seed())" in ui,
    "landscape synergies use orthogonal neighbor cells": "get_world_synergy_bonus" in tile_system and "world_cell_neighbors(cell_id)" in tile_system,
    "landscape synergies cannot cross route-sector boundaries": 'int(neighbor_tile.get("route_index", -1)) != int(current.get("route_index", -1))' in tile_system and "cross_sector_bonus" in smoke and "must not jump between distinct route sectors" in smoke,
    "field preview detects combinations whose trigger is the existing neighbor": "get_new_world_synergy_matches(world_tiles, simulated, cell_id)" in tile_system and "_get_world_synergy_matches(after_tiles, affected_cell)" in tile_system,
    "runtime and preview use a shared capped synergy aggregator": "aggregate_world_synergy_matches(_get_world_synergy_matches(world_tiles, cell_id))" in tile_system and "get_world_placement_effect_delta(world_tiles, simulated, cell_id)" in tile_system,
    "synergy caps exist for all five supported effects": all(key in tile_system for key in ('"scrap": [0, 12]', '"heal": [0, 12]', '"reward": [-0.25, 0.50]', '"spawn_bonus": [-0.35, 0.75]', '"enemy_bonus": [-0.15, 0.35]')),
    "preview reports actual marginal sector effects and cap state": '"synergy_sector_deltas"' in tile_system and '"synergy_caps_applied"' in tile_system and "get_world_synergy_bonus_for_route_index(before_tiles, route_index)" in tile_system,
    "GDScript smoke includes a multi-recipe cap fixture": "four supply/ward recipes" in smoke and "synergy scrap must be capped at 12" in smoke and "zero marginal scrap" in smoke,
    "new combination preview names the triggered route sector": 'Localization.text("tile.forecast.world_synergy")' in tile_system,
    "runtime smoke covers known combinations and reverse placement order": "cache next to ward" in smoke and "placement preview must show" in smoke and "placing the neighbor tile last must detect a synergy" in smoke,
}
missing = [name for name, ok in checks.items() if not ok]
if missing:
    print("TILE SYNERGY REGRESSION CHECK FAILED")
    for name in missing:
        print("- " + name)
    sys.exit(1)
print("TILE SYNERGY REGRESSION CHECK PASSED")
for name in checks:
    print("- " + name)
print("Runtime smoke assertions were added but are not executed by this Python check; run them in Godot.")

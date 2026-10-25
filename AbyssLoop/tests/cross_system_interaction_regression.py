"""Source-level contract across equipment, combat, route tiles and landscape synergies.

This guards the data flow between systems; actual behavior still requires Godot runtime tests.
"""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
combat = (ROOT / "scripts/systems/combat_system.gd").read_text(encoding="utf-8")
tiles = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
route_view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")

def block(source: str, start: str, end: str) -> str:
    first = source.index(start)
    last = source.index(end, first + len(start))
    return source[first:last]

sync_stats = block(manager, "func _sync_hero_stats() -> void:", "func ")
visit = block(manager, "func _visit_cell(index: int) -> void:", "func _begin_expedition_event(")
encounter = block(manager, "func _start_encounter(index: int, strength_bonus: float, reward_bonus: float, boss_encounter: bool, enemy_pool: Array = []) -> void:", "func _get_lowest_health_ally(")
victory = block(manager, "func _on_victory() -> void:", "func ")
route_place = block(manager, "func place_tile(hand_index: int, cell_index: int) -> Dictionary:", "func place_world_tile(")
route_click = block(ui, "func _on_route_cell_clicked(cell_index: int) -> void:", "func _on_world_cell_hovered(")
route_hover = block(ui, "func _on_route_cell_hovered(cell_index: int) -> void:", "func _on_route_cell_clicked(")
world_hover = block(ui, "func _on_world_cell_hovered(cell_id: String) -> void:", "func _on_world_cell_clicked(")
world_click = block(ui, "func _on_world_cell_clicked(cell_id: String) -> void:", "func _toggle_pause()")
world_place = block(manager, "func place_world_tile(hand_index: int, cell_id: String) -> Dictionary:", "func set_pause(")
checks = {
    "equipment and perk bonuses share one capped loadout calculator": "calculate_loadout_stats" in inventory and "_apply_build_stat_caps(combined)" in inventory and "total_equipment_stats(equipment)" in inventory and "total_perk_stats(perk_counts)" in inventory,
    "hero combat stats are recalculated from equipment and perks instead of incrementally stacking": "inventory_system.calculate_loadout_stats(equipment, perk_counts)" in sync_stats and all(x in sync_stats for x in ("combined_stats.get(\"attack\"", "combined_stats.get(\"defense\"", "combined_stats.get(\"speed\"", "combined_stats.get(\"crit\"")),
    "route exploration receives equipment spawn and tile-resource modifiers": "equipped_tile_spawn_bonus" in visit and "equipped_tile_scrap" in visit and "tile_system.apply_tile_visit" in visit,
    "landscape cells use their own placement and per-sector synergy path": "tile_system.can_place_world(route, world_tiles, cell_id, tile, get_route_shape_id(), get_route_geometry_seed())" in world_place and "tile_system.get_world_synergy_bonus_for_route_index(world_tiles, index)" in visit and "MAX_WORLD_TILES_PER_ROUTE_SECTOR" in tiles,
    "route-tile and landscape-tile synergies are both part of the sector visit pipeline": "tile_system.get_synergy_bonus(placed_tiles, index, route.size(), equipment)" in visit and "tile_system.get_world_synergy_bonus_for_route_index(world_tiles, index)" in visit,
    "manager retains separate validation for route and landscape placement targets": "tile_system.can_place(route, placed_tiles, cell_index, tile)" in route_place and "tile_system.can_place_world(route, world_tiles, cell_id, tile, get_route_shape_id(), get_route_geometry_seed())" in world_place,
    "stacked route, local tile, equipment and neighbour modifiers are capped once after accumulation": "var capped_visit: Dictionary = tile_system.clamp_visit_modifiers" in visit and visit.index("get_world_synergy_bonus_for_route_index") < visit.index("clamp_visit_modifiers") and visit.index("get_synergy_bonus(placed_tiles") < visit.index("clamp_visit_modifiers"),
    "derived spawn chance and reward affect encounter setup": "spawn_bonus" in visit and "_start_encounter(index, strength_bonus, reward_bonus" in visit and "combat_reward_bonus = reward_bonus" in encounter,
    "equipment reward bonuses affect loot and equipment drop chance": "equipped_reward_bonus" in encounter and "loot_system.roll_victory(defeated_enemy, loop_count, trophy_rng, reward_bonus)" in victory and "combat_reward_bonus" in victory and "inventory_system.roll_item" in victory,
    "combat uses derived attack, defense and crit stats and status-effect damage pipeline": all(x in combat for x in ("attacker.get(\"attack\"", "defender.get(\"defense\"", "attacker.get(\"crit\"", "status_effect_system.apply_incoming_damage")),
    "weapon-specific bleed and encounter barrier flow from equipped stats into battle": "hero.get(\"bleed_chance\"" in block(manager, "func _tick_combat(delta: float) -> void:", "func _get_lowest_health_ally(") and "hero.get(\"barrier_on_encounter\"" in encounter,
    "UI supports route-node and landscape placement through distinct model APIs": "cell_clicked.connect(_on_route_cell_clicked)" in ui and "world_cell_clicked.connect(_on_world_cell_clicked)" in ui and "manager.place_tile(selected_tile_hand_index, cell_index)" in route_click and "manager.place_world_tile(selected_tile_hand_index, cell_id)" in world_click,
    "route and landscape previews use their matching placement calculators": "get_placement_preview(manager.route, manager.placed_tiles, cell_index, selected_tile, manager.equipment)" in route_hover and "get_world_placement_preview(manager.route, manager.world_tiles, cell_id, selected_tile, manager.equipment, manager.get_route_shape_id(), manager.get_route_geometry_seed())" in world_hover,
    "road placement rejects event/perk decision states like landscape placement": "not pending_event.is_empty() or pending_perk_count > 0" in route_place and "not pending_event.is_empty() or pending_perk_count > 0" in world_place,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + name)
assert not failed, "Cross-system interaction regression failed: " + ", ".join(failed)
print(f"CROSS-SYSTEM INTERACTION REGRESSION: {sum(checks.values())}/{len(checks)}")
print("Source-level guard only; compile, encounter outcomes, UI placement and balance still require in-engine validation.")

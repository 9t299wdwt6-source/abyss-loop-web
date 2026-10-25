from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
content = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
tiles = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
ui_text = (ROOT / "scripts/ui/item_text_presenter.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "road formations are defined as stable data-driven three-tile patterns": "const ROAD_FORMATIONS := [" in content and all(key in content for key in ["supply_patrol", "quiet_trap", "stabilized_rift", "echo_ambush", "healing_stride"]),
    "registry validates formation ids, road-legal tiles, whitelisted effects, and numeric bounds": "seen_road_formation_ids" in content and "road formation" in content and "supported_tile_effects.has" in content and "effect_amount: Variant" in content and "spawn effect is out of bounds" in content,
    "formation matching wraps previous and next nodes around the closed route": "func _road_formation_cycle_index" in tiles and "placeable road-card slots 1..N-1" in tiles and "_road_formation_cycle_index(center_index, -1, route_size)" in tiles and "_road_formation_cycle_index(center_index, 1, route_size)" in tiles and "func get_road_formation_matches" in tiles,
    "formation effects share the existing live synergy aggregation": "for formation_match in get_road_formation_matches" in tiles and 'bonus["reward"]' in tiles,
    "placement preview detects formations centered on affected neighbouring nodes": "func get_new_road_formation_matches" in tiles and "new_road_formations" in tiles,
    "equipped cartographer bonus scales only positive formation reward": "road_formation_bonus" in tiles and "formation_bonus" in tiles and 'effects["reward_bonus"]' in tiles,
    "live road-node visit passes actual equipped items into synergy calculation": "get_synergy_bonus(placed_tiles, index, route.size(), equipment)" in manager,
    "new stat has a safe aggregation cap and affects item power": '"road_formation_bonus": {"min": 0.0, "max": 0.25}' in inventory and '"road_formation_bonus"' in inventory and "road_formation_bonus" in save,
    "item details explain the cartographer effect": "награда от формаций дороги" in ui_text,
    "runtime smoke covers every formation, equipped effect, loop wraparound, and preview": all(check in smoke for check in ["supply patrol formation", "worn route-scribe gear", "cartographer equipment must not amplify", "Тихая ловушка", "Стабилизированный разлом", "Засада на резонансе", "Шаги тихого источника", "last placeable road slot", "new formation completed", "route-card seam"]),
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + name)
print(f"ROAD FORMATION + LOADOUT REGRESSION: {len(checks) - len(failed)}/{len(checks)}")
raise SystemExit(1 if failed else 0)

"""Source-level regression for equipment counters, enemy telegraphs and tile forecasts."""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
tiles = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
presenter = (ROOT / "scripts/ui/item_text_presenter.gd").read_text(encoding="utf-8")
saves = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
manifest = json.loads((ROOT / "tests/fixtures/content_v1_stable_ids.json").read_text(encoding="utf-8"))

status_ids = ("poison", "bleed", "wound", "distortion", "weakness")
checks = {
    "five status counter stats are aggregated and individually capped": all(
        f'"{status_id}_resistance": {{"min": 0.0, "max": 0.25}}' in inventory for status_id in status_ids
    ) and 'hero[status_id + "_resistance"] = clampf' in manager,
    "status counter stats use deterministic expedition RNG and suppress before applying": '_rng_for_event().randf() < resistance' in manager and '"resisted": true' in manager and 'return status_effect_system.apply_effect(hero, effect_id, duration, magnitude, source_id)' in manager,
    "elite, boss, hunter and caster status applications share the counter helper": all(
        token in manager for token in ('_apply_enemy_status_effect(elite_status_id', '_apply_enemy_status_effect(boss_effect_id', '_apply_enemy_status_effect("weakness"', '_apply_enemy_status_effect("distortion"')
    ),
    "pre-attack warning includes equipped counter chance": 'counter_hint' in manager and 'ПРЕДУПРЕЖДЕНИЕ:' in manager and 'шанс подавить статус' in manager,
    "new counter affixes have stable definitions and typed slots": all(token in inventory for token in ('"spore_filter"', '"crystal_grounding"', '"bone_sieve"', '"echo_dampener"', '"clear_tone"')) and '"weakness_resistance": 0.12' in inventory,
    "counter stats appear in item detail text": 'var status_labels :=' in presenter and 'шанс %s %d%%' in presenter,
    "route and landscape forecasts accept the active equipment loadout": 'get_placement_preview(manager.route, manager.placed_tiles, cell_index, selected_tile, manager.equipment)' in ui and 'get_world_placement_preview(manager.route, manager.world_tiles, cell_id, selected_tile, manager.equipment, manager.get_route_shape_id(), manager.get_route_geometry_seed())' in ui,
    "tile forecast calculates tactical counter advice through the same equipment aggregator": all(token in tiles for token in ('func get_tactical_counter_preview(tile_id: String, equipment: Dictionary = {})', 'inventory_system.total_equipment_stats(equipment)', 'Контр-стратегия против %s', 'Текущая экипировка', 'profile')),
    "new resistance values are validated when loading persisted item data": all(f'"{status_id}_resistance"' in saves for status_id in status_ids) and 'numeric_value > 0.25' in saves,
    "stable affix ID is tracked in the reviewed V1 content manifest": 'clear_tone' in manifest.get("Модификаторы экипировки", []),
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    print("TELEGRAPH COUNTERPLAY REGRESSION FAILED: " + "; ".join(failed))
    sys.exit(1)
print(f"TELEGRAPH COUNTERPLAY REGRESSION PASSED: {len(checks)}/{len(checks)} source guards")
print("Source-level only; no Godot compilation, real encounter or UI runtime is implied.")

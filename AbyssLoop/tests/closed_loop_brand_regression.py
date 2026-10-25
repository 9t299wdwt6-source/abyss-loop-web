"""Abyss Loop core-design guard. Static only; Godot runtime remains separate."""
from pathlib import Path
import sys
import json

ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
route = (ROOT / "scripts/systems/route_system.gd").read_text(encoding="utf-8")
generation = (ROOT / "scripts/systems/procedural_generation.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
project = (ROOT / "project.godot").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
catalog = json.loads((ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"))
combat_sources = "\n".join(p.read_text(encoding="utf-8") for p in (ROOT / "scripts/systems").glob("*.gd"))

checks = {
    "official title is Abyss Loop in project metadata": 'config/name="Abyss Loop' in project,
    "visible UI brand is ABYSS LOOP": '_label("ABYSS LOOP"' in ui,
    "route advances and previous node lookup use modular wraparound": 'posmod(index + 1, cell_count)' in route and 'posmod(index - 1, cell_count)' in route,
    "generated routes are normalized into explicit closed-loop topology": 'bind_closed_loop(ProceduralGenerationScript.generate_route' in route and '"loop_closed"] = true' in route,
    "each node stores previous and next modulo-linked node ids": '"previous_index"] = posmod(i - 1, count)' in route and '"next_index"] = posmod(i + 1, count)' in route,
    "previous snapshots are normalized when an expedition resumes": 'route = route_system.bind_closed_loop(saved_route)' in manager,
    "square road draws and hit-tests the last perimeter tile back to the first": 'road_cells[(index + 1) % road_cells.size()]' in view and 'return result' in view[view.index("func _get_road_grid_coordinates()") : view.index("func _get_world_display_cell_map")],
    "map visually marks the loop as continuous": 'Localization.text("route.header")' in view and "НЕПРЕРЫВНЫЙ МАРШРУТ" in catalog.get("route.header", "") and 'func _draw_route_chevron' in view,
    "hero moves between route nodes; no tower combat implementation": 'hero_progress_for_draw' in manager and not any(token in combat_sources.lower() for token in ('tower_attack', 'tower_damage', 'turret_attack', 'tower_projectile', 'tower_combat')),
    "runtime smoke test covers wraparound and loop counters": 'route_system.is_closed_loop(live_loop)' in smoke and 'route_progress_after_wrap' in smoke,
    "procedural generator remains seed-driven and not an open-end route": 'static func generate_route(seed_value: int, cell_count: int, safe_intro_nodes: int = 3)' in generation,
}
failures = []
for label, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
    if not ok:
        failures.append(label)
if failures:
    print("CLOSED-LOOP / BRAND REGRESSION FAILED:\n- " + "\n- ".join(failures))
    sys.exit(1)
print(f"CLOSED-LOOP / BRAND REGRESSION PASSED: {len(checks)} checks. This is source-level evidence, not a Godot runtime test.")

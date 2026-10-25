#!/usr/bin/env python3
"""Source-level contracts for Stage 89 map discovery, legacy snapshot migration, and save/reload runtime gate."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
runner = (ROOT / "tests" / "expedition_runtime_acceptance.gd").read_text(encoding="utf-8")
runner_scene = (ROOT / "tests" / "expedition_runtime_acceptance_runner.tscn").read_text(encoding="utf-8")
manager = (ROOT / "scripts" / "systems" / "expedition_manager.gd").read_text(encoding="utf-8")
save_system = (ROOT / "scripts" / "core" / "save_system.gd").read_text(encoding="utf-8")
workflow_path = ROOT / ".github" / "workflows" / "abyssloop-web.yml"
workflow = workflow_path.read_text(encoding="utf-8") if workflow_path.is_file() else (ROOT.parent / ".github" / "workflows" / "abyssloop-web.yml").read_text(encoding="utf-8")

checks = {
    "Godot runtime acceptance imports the real TileSystem": 'const TileSystemType = preload("res://scripts/systems/tile_system.gd")' in runner,
    "new expedition asserts a positive persisted geometry seed": 'active_geometry_seed > 0' in runner and 'get_route_geometry_seed()' in runner,
    "runtime acceptance checks initial discovery coverage": 'not initial_discovery.is_empty()' in runner and 'starting landscape around its first road node' in runner,
    "runtime acceptance validates discovery IDs and road exclusion": 'is_map_world_cell_id(discovered_id)' in runner and 'active_road_ids.has(discovered_id)' in runner,
    "runtime acceptance checks visit-driven reveal expands the mask": '_reveal_world_cells_near_route_index(int(manager.route.size() / 2))' in runner and 'expanded_discovery.size() > initial_discovery_count' in runner,
    "save checkpoint stores discovery mask and active contour seed": 'saved_snapshot.get("discovered_world_cells", {}) == manager.discovered_world_cells' in runner and 'saved_snapshot.get("route_geometry_seed", 0)' in runner,
    "save/restore compares discovery mask and geometry seed exactly": 'restored.discovered_world_cells == manager.discovered_world_cells' in runner and 'restored.get_route_geometry_seed()' in runner,
    "legacy snapshot migration is tested through real manager restore": 'legacy_snapshot.erase("discovered_world_cells")' in runner and 'legacy_restored.restore_saved_run()' in runner,
    "legacy migration expects every off-road cell": 'MAP_COLUMNS * TileSystemType.MAP_ROWS - active_road_ids.size()' in runner,
    "manager restores missing discovery mask as fully discovered off-road map": 'discovered_world_cells = _get_all_offroad_cells_discovered()' in manager,
    "map snapshot validator still bounds discovery mask and rejects invalid cells": 'discovered_world_cells' in save_system and 'discovery_value.size() > 232' in save_system and 'int(snapshot.get("field_schema", 1)) < 3' in save_system,
    "CI runs the autoload-aware real gameplay acceptance runner": 'res://tests/expedition_runtime_acceptance_runner.tscn' in workflow and 'Run Godot gameplay acceptance' in workflow,
    "runner scene points to the acceptance script": 'res://tests/expedition_runtime_acceptance.gd' in runner_scene,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL") + ": " + name)
if failed:
    raise SystemExit("Stage 89 map runtime gate regression failed: " + "; ".join(failed))
print(f"STAGE 89 MAP RUNTIME GATE REGRESSION PASSED: {len(checks)}/{len(checks)} source contracts")
print("Source-level contracts only; runtime not confirmed: actual Godot acceptance still must execute the runner in CI.")

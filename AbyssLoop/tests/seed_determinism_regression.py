"""Static checks for deterministic per-floor generation and the eight-floor campaign."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
reg = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
gen = (ROOT / "scripts/systems/procedural_generation.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
enemy = (ROOT / "scripts/systems/enemy_system.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "campaign defines exactly eight progression floors": 'const FLOOR_COUNT: int = 8' in reg and 'const FLOOR_DEFS: Array[Dictionary]' in reg and 'FLOOR_DEFS.size() != FLOOR_COUNT' in reg,
    "selected floor and optional route modifier are passed into run creation": 'requested_floor_number: int = 1' in manager and 'floor_number = clampi(requested_floor_number, 1, ContentRegistry.FLOOR_COUNT)' in manager and 'manager.start_run("standard", requested_seed, selected_modifier_id, selected_contract_id, "standard", selected_floor_number)' in ui,
    "floor number is persisted and restored with legacy default one": '"floor_number": floor_number' in manager and 'snapshot.get("floor_number", 1)' in manager,
    "custom seed reproduces its floor-specific route and RNG stream": 'run_seed = ProceduralGenerationScript.create_seed() if requested_seed <= 0 else requested_seed' in manager and 'func _get_floor_seed(base_seed: int, requested_floor: int)' in manager and 'route_system.create_route(floor_seed' in manager and 'run_rng.seed = floor_seed' in manager and 'generate_route(seed_value: int' in gen,
    "each floor passes its enemy pool and preferred guardian to production encounters": 'floor_config.get("enemy_pool", [])' in manager and 'preferred_boss_id' in manager and 'create_boss(loop_count, danger + strength_bonus, rng, preferred_boss_id)' in enemy,
    "encounter composition supports modifiers without adding difficulty choices": 'extra_group_members: int = 0' in enemy and 'pack_size + maxi(0, extra_group_members)' in enemy and 'func _on_modifier_selected(index: int)' in ui and 'floor_option.item_selected.connect(_on_floor_selected)' in ui,
    "floor choice, route modifier and custom seed are available before starting": 'floor_option.item_selected.connect(_on_floor_selected)' in ui and 'modifier_option.item_selected.connect(_on_modifier_selected)' in ui and 'Seed (0 = случайный)' in ui and 'Seed: %d' in ui,
    "the preparation screen has no selectable difficulty or long-mode controls": 'difficulty_option' not in ui and 'expedition_mode_option' not in ui and 'selected_difficulty_id' not in ui and 'selected_expedition_mode_id' not in ui,
    "runtime smoke checks hundreds of deterministic seeded routes": 'for seed_value in range(500)' in smoke and 'route_a == route_b' in smoke,
}
missing = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"[{'PASS' if ok else 'FAIL'}] {name}")
if missing:
    raise SystemExit("FLOOR SEED DETERMINISM REGRESSION FAILED: " + ", ".join(missing))
print(f"FLOOR SEED DETERMINISM REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Static evidence only; route repeatability and floor combat still require Godot runtime testing.")

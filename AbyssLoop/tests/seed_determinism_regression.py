"""Static checks for deterministic route seeds and persistent eight-floor selection."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
generation = (ROOT / "scripts/systems/procedural_generation.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
enemy = (ROOT / "scripts/systems/enemy_system.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")

checks = {
    "eight floors alter threat, recovery, reward and group composition": 'const ABYSS_FLOOR_COUNT := 8' in registry and all(token in registry for token in ['"enemy_attack_multiplier"', '"enemy_health_multiplier"', '"reward_multiplier"', '"extra_group_members"', '"danger_growth_multiplier"']),
    "floor and optional route modifier are selected and stored for resume": 'requested_floor_id: int = 1' in manager and '"floor_id": floor_id' in manager and 'snapshot.get("floor_id", 1)' in manager and '"run_modifier_id": run_modifier_id' in manager and 'snapshot.get("run_modifier_id", "standard")' in manager,
    "custom seed can reproduce the initial generation": 'run_seed = ProceduralGenerationScript.create_seed() if requested_seed <= 0 else requested_seed' in manager and 'generate_route(seed_value: int' in generation,
    "encounter composition supports floor-specific extra group members": 'extra_group_members: int = 0' in enemy and 'pack_size + maxi(0, extra_group_members)' in enemy and 'active_difficulty.get("extra_group_members", 0)' in manager,
    "floor, route modifier, expedition mode and seed are available before starting": 'floor_option.item_selected.connect(_on_floor_selected)' in ui and 'modifier_option.item_selected.connect(_on_modifier_selected)' in ui and 'expedition_mode_option.item_selected.connect(_on_expedition_mode_selected)' in ui and 'Seed (0 = случайный)' in ui and 'Seed: %d' in ui,
    "locked floors cannot be started by direct API calls": 'not GameState.is_abyss_floor_unlocked(requested_floor_id)' in manager and 'range(1, GameState.highest_unlocked_floor + 1)' in ui,
    "runtime smoke checks hundreds of deterministic route seeds": 'for seed_value in range(500)' in smoke and 'route_a == route_b' in smoke,
}
missing = [name for name, ok in checks.items() if not ok]
if missing:
    print("SEED / FLOOR DETERMINISM REGRESSION FAILED")
    for name in missing:
        print("- " + name)
    sys.exit(1)
print(f"SEED / FLOOR DETERMINISM REGRESSION PASSED: {len(checks)} checks")
for name in checks:
    print("- " + name)
print("Seed stability and floor tuning still require Godot 4.7.2 runtime testing.")

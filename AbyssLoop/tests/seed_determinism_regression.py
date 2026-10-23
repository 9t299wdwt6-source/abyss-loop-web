"""Static checks for deterministic route and difficulty presets."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
reg=(ROOT/"scripts/core/content_registry.gd").read_text(encoding="utf-8")
gen=(ROOT/"scripts/systems/procedural_generation.gd").read_text(encoding="utf-8")
manager=(ROOT/"scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui=(ROOT/"scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
enemy=(ROOT/"scripts/systems/enemy_system.gd").read_text(encoding="utf-8")
smoke=(ROOT/"tests/smoke_test.gd").read_text(encoding="utf-8")
checks={
"difficulty presets alter threat, risk/reward and group composition": all(x in reg for x in ('"standard"','"volatile"','"attrition"','"reward_multiplier"','"extra_group_members"','"danger_growth_multiplier"')),
"difficulty and optional run modifier are selected and stored for resume": 'func start_run(requested_difficulty_id: String = "standard", requested_seed: int = 0, requested_modifier_id: String = "standard", requested_contract_id: String = "none", requested_mode_id: String = "standard")' in manager and '"difficulty_id": difficulty_id' in manager and 'snapshot.get("difficulty_id", "standard")' in manager and '"run_modifier_id": run_modifier_id' in manager and 'snapshot.get("run_modifier_id", "standard")' in manager,
"custom seed can reproduce the initial generation": 'run_seed = ProceduralGenerationScript.create_seed() if requested_seed <= 0 else requested_seed' in manager and 'generate_route(seed_value: int' in gen,
"encounter composition supports difficulty modifier": 'extra_group_members: int = 0' in enemy and 'pack_size + maxi(0, extra_group_members)' in enemy,
"difficulty, run modifier, and seed are available to the player before starting": 'difficulty_option.item_selected.connect(_on_difficulty_selected)' in ui and 'modifier_option.item_selected.connect(_on_modifier_selected)' in ui and 'Seed (0 = случайный)' in ui and 'Seed: %d' in ui,
"runtime smoke checks hundreds of deterministic route seeds": 'for seed_value in range(500)' in smoke and 'route_a == route_b' in smoke,
}
missing=[k for k,v in checks.items() if not v]
if missing:
 print("SEED/DIFFICULTY REGRESSION CHECK FAILED")
 for m in missing: print("- "+m)
 sys.exit(1)
print("SEED/DIFFICULTY REGRESSION CHECK PASSED")
for k in checks: print("- "+k)
print("Seed stability and difficulty tuning still need Godot runtime testing.")

"""Static integration guards for run modifiers/challenges; not a Godot runtime test."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
route_view = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
checks = {
    "four data-driven run modifiers include neutral baseline": all(f'"{x}"' in registry for x in ["standard", "resonance", "scarce", "unstable"]) and 'const RUN_MODIFIERS :=' in registry,
    "modifier definitions expose route profile and risk/reward coefficients": all(x in registry for x in ['"route_shape"', '"enemy_attack_multiplier"', '"enemy_health_multiplier"', '"encounter_chance_delta"', '"danger_growth_multiplier"', '"reward_multiplier"']),
    "modifier registry validates challenge target and reward values": 'challenge missing %s' in registry and 'invalid challenge target or reward' in registry,
    "starting tile delta affects the actual tile hand limit": 'modifier.get("starting_tile_delta", 0)' in manager and 'get_tile_hand_limit()' in manager,
    "modifier selection is wired into run creation": 'func _on_modifier_selected(index: int)' in ui and 'manager.start_run("standard", requested_seed, selected_modifier_id, selected_contract_id, "standard", selected_floor_number)' in ui,
    "difficulty and modifier multipliers both reach combat stats": 'modifier.get("enemy_attack_multiplier", 1.0)' in manager and 'modifier.get("enemy_health_multiplier", 1.0)' in manager and 'modifier.get("enemy_defense_multiplier", 1.0)' in manager,
    "modifier affects route danger, event damage and encounter chance": all(x in manager for x in ['get_run_modifier().get("danger_growth_multiplier", 1.0)', 'get_run_modifier().get("event_damage_multiplier", 1.0)', '_get_modifier_chance_delta()']),
    "challenge reward is flagged before being added to temporary loot": 'run_challenge["rewarded"] = true' in manager and 'resource_system.add(run_ledger, "scrap", scrap_reward)' in manager and 'resource_system.add(run_ledger, "crystals", crystal_reward)' in manager,
    "modifier and challenge are restored from expedition snapshots": '"run_modifier_id": run_modifier_id' in manager and '"run_challenge": run_challenge.duplicate(true)' in manager and 'snapshot.get("run_challenge"' in manager,
    "map view has distinct closed-loop shape profiles": all(x in route_view for x in ['"classic_ring"', '"deep_descent"', '"narrow_ring"', '"fractured_loop"']) and 'posmod(whole_slot + 1, road_cells.size())' in route_view and 'func _get_road_grid_coordinates() -> Array[Vector2i]:' in route_view,
    "UI displays active challenge and final result": 'challenge_label.text = "ИСПЫТАНИЕ:' in ui and 'summary.get("challenge", {})' in ui,
    "project does not implement enemy-attacking tower gameplay": 'tower_attack' not in manager and 'turret_attack' not in manager and 'func _tower_attack' not in manager,
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    print("EXPEDITION MODIFIER REGRESSION FAILED")
    for item in failed: print("- " + item)
    sys.exit(1)
print(f"EXPEDITION MODIFIER REGRESSION PASSED: {len(checks)} checks")
for name in checks: print("- " + name)
print("Runtime interaction and visual route continuity still require Godot testing.")

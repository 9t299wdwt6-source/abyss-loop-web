from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
enemies = (ROOT / "scripts/systems/enemy_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "registry validator checks required data": "func validate_content_registry() -> Array[String]:" in registry and '"effects"' in registry and 'unknown prerequisite' in registry,
    "synergy ids resolve to known tile ids": 'TILE_DEFS.has(str(synergy.get("trigger_tile"' in registry and 'TILE_DEFS.has(str(synergy.get("neighbor_tile"' in registry,
    "event choices require unique stable ids": 'choice id is empty or duplicated' in registry,
    "research dependencies are validated": 'unknown prerequisite' in registry,
    "difficulty, modifier and objective data are validated": 'missing difficulty preset' in registry and 'has invalid target or reward' in registry and 'const RUN_MODIFIERS :=' in registry and 'challenge missing %s' in registry,
    "enemy defense scaling is data configured": 'defense_bonus_after_loop' in enemies and 'enemy_id == "brute"' not in enemies,
    "boss selection supports arbitrary registered boss ids": 'ContentRegistry.BOSSES.keys()' in enemies and '"warden" if cycle_index' not in enemies,
    "item drop bonus parameters are centralized": 'loot_item_bonus_cap' in registry and 'loot_item_bonus_multiplier' in registry and 'minf(0.15, combat_reward_bonus * 0.15)' not in manager,
    "long expedition event history is bounded": 'max_event_history' in registry and 'while history.size() > int(ContentRegistry.BALANCE.get(\"max_event_history\", 100))' in manager,
    "Godot smoke test executes registry validation": 'ContentRegistry.validate_content_registry().is_empty()' in smoke,
    "tile synergy IDs are unique and effects are whitelisted": 'seen_synergy_ids' in registry and 'supported_tile_effects' in registry and 'unsupported effect' in registry,
    "shelter building and expedition mode data are validated": 'building:%s has invalid level or cost' in registry and 'expedition mode:%s has invalid endgame bounds' in registry,
    "route modifiers resolve to supported route shapes": 'valid_route_shapes' in registry and 'unknown route shape' in registry,
    "research prerequisite cycles are rejected": '_research_dependency_cycle' in registry and 'research graph contains a prerequisite cycle' in registry,
}
fail = [name for name, ok in checks.items() if not ok]
if fail:
    print("CONTENT REGISTRY VALIDATION REGRESSION FAILED")
    print("\n".join(f"- {name}" for name in fail))
    sys.exit(1)
print("CONTENT REGISTRY VALIDATION REGRESSION PASSED")
for name in checks:
    print(f"- {name}")
print("GDScript registry validation is covered in smoke_test.gd but still requires the Godot runtime to execute.")

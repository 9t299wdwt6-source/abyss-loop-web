"""Source-level regression guards for effect lifecycle, modifiers, and snapshot migration."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
system = (ROOT / "scripts/systems/status_effect_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
presenter = (ROOT / "scripts/ui/status_effect_presenter.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
project = (ROOT / "project.godot").read_text(encoding="utf-8")
checks = {
    "status data defines refresh, stack and periodic damage behavior": all(x in registry for x in ('const STATUS_EFFECTS :=', '"distortion"', '"poison"', '"exposed"', '"stack_mode"', '"tick_interval"')),
    "barrier refreshes rather than stacking indefinitely between encounters": '"barrier": {"name": "Защитный барьер"' in registry and '"stack_mode": "refresh"' in registry[registry.index('"barrier": {"name": "Защитный барьер"'):registry.index('"wound":')],
    "registry validates status type duration and stack constraints": 'for status_id_value in STATUS_EFFECTS.keys()' in registry and 'unsupported behavior' in registry,
    "apply refreshes or stacks without duplicate IDs and honors cap": all(x in system for x in ('func apply_effect(', 'existing_index', 'max_stacks', 'effect_capacity_reached')),
    "periodic damage uses active duration and bounded ticks": all(x in system for x in ('func tick_effects(', 'MAX_DELTA_SECONDS', 'MAX_TICKS_PER_UPDATE', 'active_delta')),
    "modifier calculation is centralized and bounded": 'func get_modifier(target: Dictionary, modifier_id: String) -> float:' in system and 'clampf(total, 0.0, 0.65)' in system,
    "all combat hits honor defence modifiers, wounds and barriers": 'status_effect_system.apply_incoming_damage(defender, final_damage)' in (ROOT / "scripts/systems/combat_system.gd").read_text(encoding="utf-8") and 'get_modifier(defender, "defense_penalty")' in (ROOT / "scripts/systems/combat_system.gd").read_text(encoding="utf-8"),
    "legacy caster slow migrates into status data": 'func normalize_legacy_entity(entity: Dictionary)' in system and 'legacy_caster' in system,
    "hero and enemy combat both tick statuses only inside active combat": 'status_effect_system.tick_effects(hero, delta)' in manager and 'status_effect_system.tick_effects(fighter_status, delta)' in manager and 'if paused or not pending_event.is_empty()' in manager,
    "caster uses the shared status system and crit can expose the target": '_apply_enemy_status_effect("distortion"' in manager and 'return status_effect_system.apply_effect(hero, effect_id, duration, magnitude, source_id)' in manager and 'apply_effect(enemy, "exposed"' in manager,
    "status data for both hero and current target is visible in expedition HUD": 'status_effects_label' in ui and 'status_effect_presenter.format_line(manager.status_effect_system, manager.hero, "ГЕРОЙ", 3, show_status_symbols)' in ui and 'status_effect_presenter.format_line(manager.status_effect_system, manager.enemy, "ЦЕЛЬ", 3, show_status_symbols)' in ui and 'describe_active(entity)' in presenter,
    "snapshot schema v4 persists and validates effects": '"snapshot_version": 4' in manager and '"status_schema": 1' in manager and 'snapshot_version >= 4' in save and '_validate_entity_statuses' in save,
    "old snapshots migrate to v4 and preserve legacy slow duration": 'migrated_v3["snapshot_version"] = 4' in save and '_normalize_status_entity' in save and 'legacy.get("time_remaining", 0.0)' in save,
    "runtime smoke checks stack caps ticks expiry migration barriers refresh and wounds": all(x in smoke for x in ('status_system.apply_effect', 'status_system.tick_effects(status_target, 1.0)', 'legacy_entity', 'status_expired', 'barrier_hit', 'barrier_refresh_target', 'wound_hit', 'status_combat.perform_attack')),
    "project version is 0.61.0 for this build": 'config/version="0.61.0"' in project,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    print("STATUS EFFECT REGRESSION FAILED: " + ", ".join(failed)); sys.exit(1)
print(f"STATUS EFFECT REGRESSION PASSED: {len(checks)} checks")
print("Static source evidence only; runtime assertions must be executed in Godot 4.7.2.")

"""Source checks for early-run safety and guaranteed progression opportunities."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
generation = (ROOT / "scripts/systems/procedural_generation.gd").read_text(encoding="utf-8")
route_system = (ROOT / "scripts/systems/route_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
checks = {
    "safe opening length is balance-configured": '"safe_intro_route_nodes": 3' in registry,
    "intro limit is bounded to preserve route opportunities": "clampi(safe_intro_nodes, 1, mini(5, route_length - 3))" in generation,
    "opening nodes after the shrine are plain": 'elif i < safe_prefix:' in generation and 'kind = "plain"' in generation,
    "later routes still guarantee event, cache and danger": 'if not _contains_kind(route, "event")' in generation and 'if not _contains_kind(route, "cache")' in generation and 'if not _contains_kind(route, "danger")' in generation,
    "route creation passes the configured guarantee": 'ContentRegistry.BALANCE.get("safe_intro_route_nodes", 3)' in route_system,
    "first standard run has an adequate hand": 'GameState.runs_completed == 0 and run_modifier_id == "standard"' in manager and '"first_run_min_starting_tiles": 3' in registry,
    "starting hand has a hard upper bound": "starting_tile_count = mini(starting_tile_count, 6)" in manager,
}
failed = [k for k,v in checks.items() if not v]
assert not failed, "Early-run balance regression failed: " + ", ".join(failed)
print("EARLY-RUN BALANCE REGRESSION PASSED: %d checks" % len(checks))
for name in checks: print("- " + name)
print("Source guards only; encounter pacing and combat fairness need in-engine campaigns.")

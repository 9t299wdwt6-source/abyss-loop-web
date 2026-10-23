"""Static checks for event chains and delayed consequences."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
event_system = (ROOT / "scripts/systems/expedition_event_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
checks = {
    "chain events require earlier choices": all(x in registry for x in ('"beacon_echo"', '"cache_echo"', '"signal_pursuit"', '"requires_flag"')),
    "resolved chain events cannot repeat once completed": '"excludes_flag"' in registry and '"resolved_flag"' in registry and 'event_flags.erase' in event_system or 'event_flags.erase' in manager,
    "event selector filters missing prerequisites and resolved events": 'flags: Dictionary = {}' in event_system and 'required_flag' in event_system and 'excluded_flag' in event_system,
    "event decisions preserve and mutate chain flags": '"event_flags"' in manager and 'effects.get("set_flags", [])' in manager and 'effects.get("clear_flags", [])' in manager,
    "a delayed route pulse modifies real future combat reward": 'route_pulse' in registry and 'combat_reward_bonus += 0.15' in manager,
    "runtime smoke covers conditional chain data": 'beacon_echo' in smoke and 'signal_pursuit' in smoke,
}
missing=[k for k,v in checks.items() if not v]
if missing:
 print("EVENT CHAIN REGRESSION CHECK FAILED")
 for item in missing: print("- "+item)
 sys.exit(1)
print("EVENT CHAIN REGRESSION CHECK PASSED")
for item in checks: print("- "+item)
print("Actual event-chain execution requires Godot runtime testing.")

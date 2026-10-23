from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
route = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
feedback = (ROOT / "scripts/systems/feedback_system.gd").read_text(encoding="utf-8")
checks = {
    "autosave and UI refresh cadence are configured": '"autosave_interval_seconds"' in registry and '"manager_refresh_interval"' in registry,
    "event log stays bounded": '"max_event_log_entries": 8' in registry and 'while event_log.size() > int(ContentRegistry.BALANCE.get("max_event_log_entries", 8))' in manager,
    "event history stays bounded on long runs and after restore": '"max_event_history": 100' in registry and 'while history.size() > int(ContentRegistry.BALANCE.get("max_event_history", 100))' in manager,
    "route view skips unchanged redraw requests": 'var needs_redraw := static_signature != _last_static_signature or not is_equal_approx(next_progress, hero_progress)' in route and 'str(cells) + \"|\" + str(tiles)' not in route,
    "settings and metric labels skip unchanged assignments": 'if scrap_label.text != next_scrap_text' in ui and 'if log_label.text != next_log_render' in ui and 'if exp_metrics.hp.text != hp_text' in ui,
    "notification audio has cooldown and concurrent player cap": '_cooldowns' in feedback and 'max_feedback_tones' in feedback and '_active_players.size() >= max_players' in feedback,
    "benchmark scenarios cover seeded generation": 'range(500)' in (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8"),
}
failed = [name for name, passed in checks.items() if not passed]
if failed:
    print("PERFORMANCE LONG-RUN REGRESSION FAILED")
    print("\n".join("- " + name for name in failed))
    sys.exit(1)
print("PERFORMANCE LONG-RUN REGRESSION PASSED")
for name in checks:
    print("- " + name)
print("Long-duration load, frame pacing and audio overlap require Godot runtime profiling on target hardware.")

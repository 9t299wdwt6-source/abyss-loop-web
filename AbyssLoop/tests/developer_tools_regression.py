"""Stage 50: developer diagnostics stay read-only and debug-build-only."""
from pathlib import Path
import subprocess
import sys
import json

ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
reporter = (ROOT / "scripts/ui/developer_diagnostics_report.gd").read_text(encoding="utf-8")
tool = (ROOT / "tools/developer_diagnostics.py").read_text(encoding="utf-8")
catalog = json.loads((ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"))
report_block = reporter.split("func build_report(manager: Variant, screen_mode: String) -> String:", 1)[1].split("func format_debug_effects", 1)[0]
checks = {
    "developer button is only created in a debug build": 'if OS.is_debug_build():' in ui and '_t("header.button.diagnostics")' in ui and catalog.get("header.button.diagnostics") == "Диагностика · F9",
    "F9 shortcut refuses release builds": 'if key_event.keycode == KEY_F9:' in ui and 'if not OS.is_debug_build():' in ui,
    "diagnostics overlay uses bounded scrolling": 'func _open_developer_tools()' in ui and 'ScrollContainer.new()' in ui,
    "diagnostic report has a dedicated helper preloaded and delegated to": "res://scripts/ui/developer_diagnostics_report.gd" in ui and "developer_diagnostics_report.build_report(manager, screen_mode)" in ui and "extends RefCounted" in reporter,
    "diagnostic report includes seed and closed-loop status": 'manager.run_seed' in report_block and 'manager.route_system.is_closed_loop(manager.route)' in report_block,
    "diagnostic report includes combat and status effects": 'manager.encounter_enemies' in report_block and 'format_debug_effects' in report_block,
    "diagnostic report invokes content registry validation": 'ContentRegistry.validate_content_registry()' in report_block,
    "diagnostic report includes objectives, contracts and snapshot": 'manager.run_objective' in report_block and 'manager.run_contract' in report_block and 'GameState.saved_expedition' in report_block,
    "clipboard action is a direct user action": 'DisplayServer.clipboard_set(report)' in ui and 'func _copy_developer_report()' in ui,
    "diagnostic component documents read-only behavior": 'не меняет seed, бой, контент или сохранение' in reporter and "without owning UI controls or mutating game state" in reporter,
    "diagnostic report helper has no gameplay mutation calls": not any(token in report_block for token in ("GameState.upgrade_", "GameState.salvage_", "GameState.reset_", "GameState.save_")),
    "offline diagnostics tool reuses content validator": 'validate_catalogs(catalogs)' in tool and 'inspect_resource_paths(root)' in tool,
    "offline diagnostics does not modify game saves": 'SaveSystem' not in tool and 'GameState' not in tool,
}
failures = [label for label, ok in checks.items() if not ok]
# Run the offline tool and check that it writes a report without requiring Godot.
proc = subprocess.run([sys.executable, str(ROOT / "tools/developer_diagnostics.py")], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=25)
checks["offline diagnostics CLI exits successfully"] = proc.returncode == 0
checks["offline diagnostics report is written"] = (ROOT / "tests/reports/DEVELOPER_DIAGNOSTICS_RU.md").is_file()
if proc.returncode != 0:
    failures.append("offline diagnostics CLI exits successfully\n" + proc.stdout)
if not (ROOT / "tests/reports/DEVELOPER_DIAGNOSTICS_RU.md").is_file():
    failures.append("offline diagnostics report is written")
if failures:
    print("DEVELOPER TOOLS REGRESSION FAILED")
    print("\n".join("- " + x for x in failures))
    sys.exit(1)
print("DEVELOPER TOOLS REGRESSION PASSED")
for label in checks:
    print("- " + label)
print("Note: source-level UI assertions do not replace the Godot 4.7.2 compile/runtime check.")

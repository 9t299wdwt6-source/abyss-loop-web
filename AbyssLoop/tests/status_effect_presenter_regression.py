"""Stage 65B: status-effect HUD formatting stays read-only and accessible."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
presenter_path = ROOT / "scripts/ui/status_effect_presenter.gd"
presenter = presenter_path.read_text(encoding="utf-8")

checks = {
    "presenter is a small standalone RefCounted component": "extends RefCounted" in presenter and len(presenter.splitlines()) < 100,
    "presenter reads active statuses from shared status-effect system": "status_effect_system.describe_active(entity)" in presenter,
    "presenter formats stack counts and remaining duration": '" ×%d" % stacks' in presenter and "float(status_value.get(\"duration\", 0.0))" in presenter,
    "presenter limits visible effects and reports hidden count": "mini(max_visible, active_statuses.size())" in presenter and 'status_parts.append("+%d"' in presenter,
    "empty status list has explicit text": 'нет активных эффектов' in presenter,
    "symbols are optional and status text stays descriptive": "if show_symbols else \"\"" in presenter and 'str(status_value.get("name", "Эффект"))' in presenter,
    "each known status effect has its own stable non-colour marker": all(text in presenter for text in ('return "[P] "', 'return "[B] "', 'return "[W] "', 'return "[#] "', 'return "[+] "', 'return "[~] "', 'return "[-] "', 'return "[!] "')),
    "HUD uses component for hero and current target": all(text in ui for text in ('status_effect_presenter.format_line(manager.status_effect_system, manager.hero', 'status_effect_presenter.format_line(manager.status_effect_system, manager.enemy')),
    "HUD respects saved status-symbol setting": 'bool(GameState.settings.get("status_symbols", true))' in ui and "show_status_symbols" in ui,
    "component does not tick, apply, or remove status effects": not any(token in presenter for token in ("apply_effect(", "tick_effects(", "remove_effect(", "GameState.")),
    "UI preloads dedicated presenter": 'preload("res://scripts/ui/status_effect_presenter.gd")' in ui,
}
failed = [label for label, ok in checks.items() if not ok]
for label, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
if failed:
    print("STATUS EFFECT PRESENTER REGRESSION FAILED: " + "; ".join(failed))
    sys.exit(1)
print(f"STATUS EFFECT PRESENTER REGRESSION PASSED: {len(checks)} checks")
print("Static source checks only; GDScript compilation and visual behavior must be checked in Godot.")

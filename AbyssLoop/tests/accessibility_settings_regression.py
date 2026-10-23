"""Source-level regression checks for Prototype 52 accessibility and settings; guarded in the current release."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
project = (ROOT / "project.godot").read_text(encoding="utf-8")
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
presenter = (ROOT / "scripts/ui/status_effect_presenter.gd").read_text(encoding="utf-8")
route = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
packager = (ROOT / "tools/package_release.py").read_text(encoding="utf-8")
catalog = json.loads((ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"))

checks = {
    "project is versioned 0.61.0 without changing its stable name": 'config/name="Abyss Loop"' in project and 'config/version="0.61.0"' in project,
    "settings defaults include display, contrast, motion and symbol preferences": all(key in state for key in ['"ui_scale": 1.0', '"window_mode": "windowed"', '"high_contrast": false', '"status_symbols": true', '"animation_speed": 1.0']),
    "legacy profiles receive defaults and all settings are normalized": "settings = DEFAULT_SETTINGS.duplicate(true)" in state and "func _normalize_settings()" in state and "settings[\"ui_scale\"] = clampf" in state,
    "save validator bounds scale and animation speed": '"ui_scale", "animation_speed"' in save and "float(setting_value) < minimum" in save and '"windowed", "fullscreen"' in save,
    "volume controls only update recognized audio buses": 'if not ["master_volume", "music_volume", "effects_volume"].has(key):' in ui,
    "UI scale applies immediately through Window content scaling": "func _on_ui_scale_selected(index: int)" in ui and "window.content_scale_factor =" in ui,
    "windowed and fullscreen modes apply and persist": "Window.MODE_FULLSCREEN" in ui and "Window.MODE_WINDOWED" in ui and 'GameState.settings["window_mode"]' in ui,
    "reduced motion snaps the route marker and limits feedback": "var fraction := 0.0 if reduced_motion" in route and "feedback_time = 0.75 if reduced_motion else 1.35" in route,
    "animation speed affects only UI feedback timing": "feedback_time - delta * animation_speed" in route and "не скорость боя" in catalog.get("settings.animation.description", "").lower() and "animation_speed" not in (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8"),
    "high contrast updates text, panels and button outlines": "func _apply_contrast_to_tree(node: Node)" in ui and 'Color("#e0eee4")' in ui and 'Color("#d2e8d9")' in ui,
    "state effects have redundant non-colour text prefixes": "func accessibility_prefix(status_id: String) -> String:" in presenter and 'return "[!] "' in presenter and 'return "[+] "' in presenter and "status_effect_presenter.format_line" in ui,
    "route feedback receives accessibility settings without affecting combat state": "func _apply_accessibility_settings()" in ui and "route_view.configure_accessibility(" in ui and "var animation_speed: float = 1.0" in route,
    "Prototype 52 accessibility manual runtime checklist is still included in release": '"ACCESSIBILITY_SETTINGS_RUNTIME_CHECKLIST_Prototype52.md"' in packager,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL") + ": " + name)
assert not failed, "Accessibility/settings regression failed: " + ", ".join(failed)
print(f"ACCESSIBILITY SETTINGS REGRESSION: {len(checks)}/{len(checks)}")
print("Note: source-level checks only; Godot compilation, real window changes and visual contrast require runtime acceptance.")

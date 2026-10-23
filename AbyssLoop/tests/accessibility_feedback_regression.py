"""Static checks for configurable visual/audio feedback and accessibility."""
from pathlib import Path
import sys
import json
ROOT=Path(__file__).resolve().parents[1]
ui=(ROOT/"scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
view=(ROOT/"scripts/ui/route_view.gd").read_text(encoding="utf-8")
feedback=(ROOT/"scripts/systems/feedback_system.gd").read_text(encoding="utf-8")
state=(ROOT/"scripts/core/game_state.gd").read_text(encoding="utf-8")
manager=(ROOT/"scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
smoke=(ROOT/"tests/smoke_test.gd").read_text(encoding="utf-8")
catalog=json.loads((ROOT/"localization/strings_ru.json").read_text(encoding="utf-8"))
checks={
"accessibility settings default and migrate safely": '"reduced_motion": false' in state and '"reduce_flashes": true' in state,
"settings toggle options have live handlers": '_on_accessibility_setting_changed' in ui and all(key in catalog for key in ("settings.accessibility.reduced_motion", "settings.accessibility.reduce_flashes", "settings.accessibility.high_contrast", "settings.accessibility.status_symbols")) and 'toggle.toggled.connect(_on_accessibility_setting_changed.bind(str(accessibility_option.get("key", ""))))' in ui,
"visual feedback supports reduced motion and low-flash colors": 'func show_feedback' in view and 'if reduced_motion or reduce_flashes' in view and 'configure_accessibility' in view,
"generated one-shot tones use a dedicated SFX bus": 'AudioStreamWAV.FORMAT_16_BITS' in feedback and 'player.bus = "SFX"' in feedback and 'player.finished.connect(_on_player_finished.bind(player))' in feedback and '_on_player_finished' in feedback,
"important manager events emit feedback categories": all(x in manager for x in ('_request_feedback("damage"','_request_feedback("event"','_request_feedback("loot"','_request_feedback("level"','_request_feedback("boss"','_request_feedback("objective"')),
"UI connects feedback bus and route visualization": 'manager.feedback_requested.connect(_on_feedback_requested)' in ui and 'route_view.show_feedback(kind, message)' in ui,
"runtime smoke asserts feedback settings": 'reduced_motion' in smoke and 'reduce_flashes' in smoke,
}
missing=[k for k,v in checks.items() if not v]
if missing:
 print("ACCESSIBILITY FEEDBACK REGRESSION FAILED")
 for m in missing: print("- "+m)
 sys.exit(1)
print("ACCESSIBILITY FEEDBACK REGRESSION PASSED")
for k in checks: print("- "+k)
print("Audio rendering and visual timing must be checked in Godot on target hardware.")

"""Static regression for Stage66C: enemy role, tile and status readability."""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
route = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
presenter = (ROOT / "scripts/ui/status_effect_presenter.gd").read_text(encoding="utf-8")
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
catalog = json.loads((ROOT / "localization/strings_ru.json").read_text(encoding="utf-8"))
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")

roles = {
    "fast": "СКОР.",
    "tank": "БРОН.",
    "caster": "МАГ",
    "support": "ПОДД.",
    "hunter": "ОХОТ.",
    "boss": "БОСС",
    "unknown": "РОЛЬ?",
}
checks = {
    "all enemy role labels are localized and non-empty": all(catalog.get(f"enemy.role.{key}") == value for key, value in roles.items()),
    "combat HUD resolves each registered role through localization": all(f'_t("enemy.role.{role}")' in ui for role in roles),
    "enemy behavior hint remains available as HUD tooltip": 'fight_status_label.tooltip_text = behavior_hint' in ui and '"behavior_hint"' in registry,
    "elite role is shown alongside the elite label": '[ЭЛИТА · %s]' in ui and 'current_enemy_role' in ui,
    "boss and elite telegraphs remain visible after role labeling": '" · ГОТОВИТ УДАР"' in ui and '"is_boss"' in ui and '"is_elite"' in ui,
    "route map uses explicit boss and elite markers rather than colour alone": 'var badge_text := "Б" if boss_encounter else ("Э" if elite_encounter else "!")' in route,
    "route and landscape tile icons remain shape-drawn from tile IDs": 'func _draw_pixel_symbol(center: Vector2, symbol_id: String)' in route and '"cache"' in route and '"hunt"' in route and '"ward"' in route and '"rift"' in route,
    "known statuses have distinct non-colour prefixes": all(f'return "{prefix}"' in presenter for prefix in ("[P] ", "[B] ", "[W] ", "[#] ", "[+] ", "[~] ", "[-] ", "[!] ")),
    "status names, stacks, and durations remain visible": 'str(status_value.get("name", "Эффект"))' in presenter and 'stacks_suffix' in presenter and 'float(status_value.get("duration", 0.0))' in presenter,
    "status presentation does not change combat rules": not any(token in presenter for token in ("apply_effect(", "tick_effects(", "remove_effect(")) and 'func _tick_combat' in manager,
}
failed = [label for label, ok in checks.items() if not ok]
for label, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
if failed:
    print("STAGE66C READABILITY REGRESSION FAILED: " + "; ".join(failed))
    sys.exit(1)
print(f"STAGE66C READABILITY REGRESSION: {len(checks)}/{len(checks)}")
print("Static/source checks only; GDScript compilation, font coverage and HUD fit require Godot runtime acceptance.")

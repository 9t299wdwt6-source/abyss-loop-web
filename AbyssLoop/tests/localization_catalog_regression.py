"""Static regression checks for the reviewed text catalog and its UI references."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
catalog_path = ROOT / "localization/strings_ru.json"
catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
localizer = (ROOT / "scripts/core/localization.gd").read_text(encoding="utf-8")
route = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
tile_system = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
project = (ROOT / "project.godot").read_text(encoding="utf-8")
report_tool = (ROOT / "tools/localization_audit.py").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")

literal_refs = set(re.findall(r'_t\("([a-z0-9_.]+)"\)', ui))
literal_refs.update(re.findall(r'Localization\.text\("([a-z0-9_.]+)"\)', route))
literal_refs.update(re.findall(r'Localization\.text\("([a-z0-9_.]+)"\)', tile_system))
dynamic_keys = {key for key in catalog if key.startswith("tutorial.") or key.startswith("settings.volume.")}
placeholders = re.compile(r"%(?:\d+)?(?:\.\d+)?[dsif]")

checks = {
    "reference catalog has at least 100 reviewed Russian UI strings": len(catalog) >= 100,
    "localization service is an autoload": 'Localization="*res://scripts/core/localization.gd"' in project and "func text(key: String) -> String:" in localizer,
    "all literal UI localization keys exist": literal_refs <= set(catalog),
    "tutorial pages use catalog-backed keys": all(f'"title_key": "tutorial.{i}.title"' in ui for i in range(1, 6)) and all({f"tutorial.{i}.{part}" for part in ("title", "body", "tip")} <= set(catalog) for i in range(1, 6)),
    "settings volume keys are assembled from three catalog entries": '"settings.volume." + str(entry.key).trim_suffix("_volume")' in ui and all(f"settings.volume.{key}" in catalog for key in ("master", "music", "effects")),
    "all catalog entries are non-empty strings": all(isinstance(value, str) and value.strip() for value in catalog.values()),
    "format strings keep expected numeric/string placeholders": all(placeholders.search(catalog[key]) for key in ("base.statistics.expeditions", "base.statistics.elites_bosses", "base.button.history", "modal.button.continue_tutorial_step", "expedition.controls.speed")),
    "localization audit tool is included": "def build_report()" in report_tool and "strings_ru.json" in report_tool,
    "runtime smoke verifies catalog loading and help content": all(term in smoke for term in ("Localization.catalog_size() >= 100", 'Localization.has_key("base.hero.title")', 'Localization.text("help.body")')),
    "fixed tutorial prose is no longer embedded in TUTORIAL_STEPS": "Герой автоматически движется по кругу." not in ui and "tutorial.1.body" in ui,
    "placement tutorial describes both road and landscape targets": "узел дороги или клетку ландшафта" in catalog["tutorial.2.body"] and "На самой дороге карты не размещаются." not in catalog["tutorial.2.body"],
    "tile-system preview templates are catalog-backed": all(key in catalog and f'Localization.text("{key}")' in tile_system for key in ("tile.forecast.route_baseline", "tile.forecast.world_sector", "tile.forecast.world_synergy", "tile.forecast.no_change")),
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL") + ": " + name)
assert not failed, "Localization catalog regression failed: " + ", ".join(failed)
print(f"LOCALIZATION CATALOG REGRESSION: {sum(checks.values())}/{len(checks)}")
print("Source-level checks only; GDScript import and visual text fitting require Godot 4.7.2.")

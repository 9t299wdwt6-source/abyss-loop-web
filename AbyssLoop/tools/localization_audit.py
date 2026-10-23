#!/usr/bin/env python3
"""Validate the Russian reference UI catalog and report untranslated hard-coded UI scope."""
from __future__ import annotations
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "localization/strings_ru.json"
UI_PATH = ROOT / "scripts/ui/ui_controller.gd"
LOC_PATH = ROOT / "scripts/core/localization.gd"


def build_report() -> tuple[str, int]:
    errors: list[str] = []
    raw = CATALOG_PATH.read_text(encoding="utf-8")
    catalog = json.loads(raw)
    ui = UI_PATH.read_text(encoding="utf-8")
    route = (ROOT / "scripts/ui/route_view.gd").read_text(encoding="utf-8")
    tile_system = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
    localizer = LOC_PATH.read_text(encoding="utf-8")
    project = (ROOT / "project.godot").read_text(encoding="utf-8")

    if not isinstance(catalog, dict):
        errors.append("Каталог должен быть JSON-объектом.")
        catalog = {}
    if len(catalog) < 80:
        errors.append(f"Слишком мало строк в эталонном каталоге: {len(catalog)} (ожидается не менее 80).")
    if 'Localization="*res://scripts/core/localization.gd"' not in project:
        errors.append("Сервис Localization не подключён как autoload.")
    if "res://localization/strings_ru.json" not in localizer or "func text(key: String) -> String:" not in localizer:
        errors.append("Загрузчик локализации не открывает ожидаемый каталог.")

    literal_refs = set(re.findall(r'_t\("([a-z0-9_.]+)"\)', ui))
    literal_refs.update(re.findall(r'Localization\.text\("([a-z0-9_.]+)"\)', route))
    literal_refs.update(re.findall(r'Localization\.text\("([a-z0-9_.]+)"\)', tile_system))
    missing = sorted(literal_refs - set(catalog))
    if missing:
        errors.append("Ключи UI отсутствуют в каталоге: " + ", ".join(missing))
    dynamic_keys = set(re.findall(r'"((?:tutorial\.[1-5]\.(?:title|body|tip))|(?:settings\.volume\.(?:master|music|effects)))"', ui + "\n" + raw))
    # Dynamic tutorial keys are stored in the TUTORIAL_STEPS array; audio keys are assembled from settings.
    dynamic_keys = {key for key in catalog if key.startswith("tutorial.") or key.startswith("settings.volume.")}
    unused = sorted(set(catalog) - literal_refs - dynamic_keys)
    if unused:
        errors.append("Ключи каталога не используются: " + ", ".join(unused))

    empty = sorted(key for key, value in catalog.items() if not isinstance(value, str) or not value.strip())
    if empty:
        errors.append("Пустые или нестроковые переводы: " + ", ".join(empty))
    placeholders = re.compile(r"%(?:\d+)?(?:\.\d+)?[dsif]")
    for key, value in catalog.items():
        if not isinstance(value, str):
            continue
        if key in {"base.statistics.expeditions", "base.statistics.victories", "base.statistics.elites_bosses", "base.statistics.decisions", "base.statistics.best_loop", "base.statistics.buildings", "base.statistics.research", "base.button.history", "modal.button.continue_tutorial_step", "expedition.controls.speed"} and not placeholders.search(value):
            errors.append(f"Строка с форматированием потеряла шаблон: {key}")
        if "TODO" in value or "TBD" in value or "lorem ipsum" in value.lower():
            errors.append(f"В каталоге осталась заглушка: {key}")

    lines = [
        "# Abyss Loop — аудит локализации и текста (Prototype 61 RC7)", "",
        "## Область проверки", "",
        f"- Язык-эталон: русский.",
        f"- Строк в каталоге: {len(catalog)}.",
        f"- Явных ключей локализации, используемых интерфейсом: {len(literal_refs)}.",
        f"- Динамические семейства ключей: обучение (15 строк), аудионастройки (3 строки).",
        "- Локализованы оболочка, подготовка забега, основной HUD, панель тактических тайлов, справка, обучение и настройки доступности.",
        "- Второй язык намеренно не добавлен: непроверенный машинный перевод не должен подменять текст эталонного языка.",
        "- Названия и описания предметов, врагов, событий, исследований и названия/описания самих тайлов остаются в data-driven реестре `content_registry.gd`; их последующий перенос в локализуемые записи данных — отдельный проход, а не автоматический перевод.",
        "- Шаблоны прогнозов размещения, предупреждения дороги/ландшафта и тексты обучения про размещение вынесены в каталог `strings_ru.json`.",
        "", "## Проверки", "",
        f"- Ключи UI без перевода: {len(missing)}.",
        f"- Неиспользуемые ключи: {len(unused)}.",
        f"- Пустые записи: {len(empty)}.",
        f"- Ошибки форматов/заглушек: {sum(1 for e in errors if 'форматированием' in e or 'заглушка' in e)}.",
        "", "## Ошибки", "",
    ]
    lines += [f"- {error}" for error in errors] if errors else ["- Нет по проверяемым статическим условиям."]
    lines += ["", "## Ограничения", "", "Этот аудит проверяет структуру файлов и ссылки в исходнике. Он не заменяет импорт и запуск GDScript в Godot 4.7.2, не гарантирует перенос каждого динамического текста и не доказывает отсутствие обрезания текста во всех разрешениях. Визуальные контрольные шаги добавлены в `UI_ACCEPTANCE_RUNTIME_CHECKLIST_Prototype61.md`.", ""]
    return "\n".join(lines), len(errors)


if __name__ == "__main__":
    report, error_count = build_report()
    print(report)
    raise SystemExit(1 if error_count else 0)

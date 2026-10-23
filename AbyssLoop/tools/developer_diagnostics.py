#!/usr/bin/env python3
"""Read-only offline diagnostics for Abyss Loop's authored data and project references.

This tool reports source-level issues only. It does not claim to compile GDScript,
run the Godot scene, or validate visual/UI behavior.
"""
from __future__ import annotations
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from content_v1_audit import read_catalogs, stable_ids_snapshot, validate_catalogs

RESOURCE_RE = re.compile(r'res://[A-Za-z0-9_./ -]+')


def inspect_resource_paths(root: Path) -> list[str]:
    issues: list[str] = []
    suffixes = {".gd", ".tscn", ".tres", ".godot", ".gdshader", ".import"}
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix not in suffixes or ".godot/" in path.as_posix():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for raw in RESOURCE_RE.findall(text):
            ref = raw.rstrip(".,:;]")
            if not ref or " " in ref or "${" in ref:
                continue
            target = root / ref.removeprefix("res://")
            if not target.exists():
                issues.append(f"{path.relative_to(root)}: unresolved resource path {ref}")
    return issues


def build_report(root: Path = ROOT) -> tuple[str, dict[str, object]]:
    catalogs = read_catalogs(root)
    content_issues = validate_catalogs(catalogs)
    stable_manifest = root / "tests/fixtures/content_v1_stable_ids.json"
    actual_ids = stable_ids_snapshot(catalogs)
    stable_issues: list[str] = []
    if not stable_manifest.is_file():
        stable_issues.append("missing tests/fixtures/content_v1_stable_ids.json")
    else:
        expected = json.loads(stable_manifest.read_text(encoding="utf-8"))
        if expected != actual_ids:
            stable_issues.append("stable ID snapshot differs from the authored manifest")
    resource_issues = inspect_resource_paths(root)
    category_counts = {row["category"]: len(row["items"]) for row in catalogs["categories"]}
    all_ids = [item["id"] for row in catalogs["categories"] for item in row["items"]]
    duplicate_ids = sorted(key for key, count in Counter(all_ids).items() if count > 1)
    # Cross-category reuse can be legitimate. Report it separately instead of treating
    # identical text IDs in unrelated typed namespaces as fatal registry duplicates.
    lines = [
        "# Abyss Loop — диагностика разработчика (read-only)", "",
        f"Корень проекта: `{root.name}/`", "",
        "> Отчёт проверяет исходные данные и ссылки из файлов. Он не подтверждает компиляцию GDScript или работу сцены в Godot.", "",
        "## Сводка", "",
        f"- Категорий контента: {len(category_counts)}",
        f"- Записей контента: {sum(category_counts.values())}",
        f"- Ошибок схемы контента: {len(content_issues)}",
        f"- Ошибок стабильного ID-манифеста: {len(stable_issues)}",
        f"- Не найденных буквальных res:// ссылок: {len(resource_issues)}",
        f"- Совпадающих ID в разных типизированных категориях (информационно): {len(duplicate_ids)}",
        "", "## Покрытие категорий", "", "| Категория | Записей |", "|---|---:|",
    ]
    for category, count in category_counts.items():
        lines.append(f"| {category} | {count} |")
    lines += ["", "## Ошибки схемы контента", ""]
    lines += [f"- {issue}" for issue in content_issues] or ["- Нет."]
    lines += ["", "## Ошибки стабильных ID", ""]
    lines += [f"- {issue}" for issue in stable_issues] or ["- Нет."]
    lines += ["", "## Неразрешённые ресурсные ссылки", ""]
    lines += [f"- {issue}" for issue in resource_issues] or ["- Нет среди проверенных буквальных ссылок."]
    lines += ["", "## Интерпретация", "", "- Диагностика не запускает и не изменяет сохранения.", "- Ссылки, собранные из кода регулярным выражением, могут требовать ручной проверки, если путь формируется динамически.", "- Для завершения приёмки всё ещё нужен реальный Godot 4.7.2 import/headless smoke, затем визуальный прогон.", ""]
    report = "\n".join(lines)
    result = {
        "categories": category_counts,
        "content_records": sum(category_counts.values()),
        "content_issues": content_issues,
        "stable_id_issues": stable_issues,
        "resource_issues": resource_issues,
        "duplicate_ids_cross_category": duplicate_ids,
    }
    return report, result


if __name__ == "__main__":
    report, result = build_report()
    output = ROOT / "tests/reports/DEVELOPER_DIAGNOSTICS_RU.md"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(report, encoding="utf-8")
    print("ABYSS LOOP DEVELOPER DIAGNOSTICS — read-only")
    print(f"Content records: {result['content_records']} / categories: {len(result['categories'])}")
    print(f"Content issues: {len(result['content_issues'])}; stable ID issues: {len(result['stable_id_issues'])}; resource path issues: {len(result['resource_issues'])}")
    print(f"Report: {output.relative_to(ROOT)}")
    sys.exit(1 if result['content_issues'] or result['stable_id_issues'] or result['resource_issues'] else 0)

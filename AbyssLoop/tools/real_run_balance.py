#!/usr/bin/env python3
"""Offline analysis of real Abyss Loop expedition history exported from the local save.

This tool reads files only, writes a Markdown report, and never edits a save or sends data
anywhere. It does not simulate combat and never labels a small sample as a balance verdict.
"""
from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

OUTCOMES = {"return", "defeat"}
REQUIRED_INT_FIELDS = (
    "loops", "hero_level", "victories", "bosses_defeated", "elites_defeated",
    "events_resolved", "earned_scrap", "earned_crystals", "kept_scrap",
    "kept_crystals", "lost_scrap", "lost_crystals",
)
OPTIONAL_INT_FIELDS = (
    "seed", "timestamp_unix", "run_elapsed_seconds", "start_hp", "start_max_hp",
    "start_attack", "start_defense", "start_profile_scrap", "start_profile_crystals",
    "contract_scrap_cost", "contract_crystal_cost", "end_hp", "end_max_hp",
    "end_attack", "end_defense", "road_placements", "world_placements",
    "route_cells", "processed_steps", "telemetry_schema",
)
OPTIONAL_NUMBER_FIELDS = ("danger",)


def _is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def load_input(path: Path) -> tuple[dict[str, Any], list[Any], str]:
    """Return metadata, candidate run rows and the detected input shape."""
    try:
        parsed = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"Не удалось прочитать JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ValueError("Корень JSON должен быть объектом.")

    metadata_value = parsed.get("metadata", {})
    metadata = metadata_value if isinstance(metadata_value, dict) else {}
    if isinstance(parsed.get("runs"), list):
        return metadata, parsed["runs"], "exported runs"
    data_value = parsed.get("data")
    if isinstance(data_value, dict) and isinstance(data_value.get("expedition_history"), list):
        return metadata, data_value["expedition_history"], "Godot save envelope"
    if isinstance(parsed.get("expedition_history"), list):
        return metadata, parsed["expedition_history"], "profile payload"
    raise ValueError("Не найден массив runs или expedition_history. Нужен локальный save Abyss Loop или JSON-экспорт истории.")


def normalize_runs(raw_rows: list[Any]) -> tuple[list[dict[str, Any]], list[str], int, int]:
    valid: list[dict[str, Any]] = []
    warnings: list[str] = []
    invalid_count = 0
    duplicate_count = 0
    seen_ids: set[str] = set()
    for index, raw in enumerate(raw_rows):
        if not isinstance(raw, dict):
            invalid_count += 1
            warnings.append(f"Строка {index + 1}: запись не является JSON-объектом и исключена.")
            continue
        row = dict(raw)
        run_id = str(row.get("run_id", "")).strip()
        outcome = str(row.get("outcome", "")).strip().lower()
        version = str(row.get("game_version", "unknown")).strip() or "unknown"
        difficulty = str(row.get("difficulty_id", "standard")).strip() or "standard"
        mode = str(row.get("expedition_mode_id", "standard")).strip() or "standard"
        modifier = str(row.get("modifier_id", row.get("modifier_name", "unknown"))).strip() or "unknown"
        if not run_id or len(run_id) > 100 or outcome not in OUTCOMES:
            invalid_count += 1
            warnings.append(f"Строка {index + 1}: отсутствует run_id/неподдерживаемый outcome; запись исключена.")
            continue
        if run_id in seen_ids:
            duplicate_count += 1
            warnings.append(f"Повтор run_id `{run_id}` исключён из подсчёта.")
            continue
        bad_metric = False
        for key in REQUIRED_INT_FIELDS:
            value = row.get(key, 1 if key == "hero_level" else 0)
            if not _is_int(value) or value < 0:
                bad_metric = True
                break
        for key in OPTIONAL_INT_FIELDS:
            if key in row and (not _is_int(row[key]) or row[key] < 0):
                bad_metric = True
                break
        for key in OPTIONAL_NUMBER_FIELDS:
            if key in row and (isinstance(row[key], bool) or not isinstance(row[key], (int, float)) or row[key] < 0):
                bad_metric = True
                break
        if bad_metric:
            invalid_count += 1
            warnings.append(f"Строка {index + 1} (`{run_id}`): отрицательная или нецелочисленная метрика; запись исключена.")
            continue
        row["run_id"] = run_id
        row["outcome"] = outcome
        row["game_version"] = version
        row["difficulty_id"] = difficulty
        row["expedition_mode_id"] = mode
        row["modifier_id"] = modifier
        for key in REQUIRED_INT_FIELDS + OPTIONAL_INT_FIELDS:
            row.setdefault(key, 1 if key == "hero_level" else 0)
        for key in OPTIONAL_NUMBER_FIELDS:
            row.setdefault(key, 0.0)
        seen_ids.add(run_id)
        valid.append(row)

    if not valid:
        warnings.append("Нет пригодных записей. Проверьте формат, наличие завершённых экспедиций и run_id.")
    return valid, warnings, invalid_count, duplicate_count


def _median(rows: list[dict[str, Any]], field: str) -> float | int | None:
    values = [row[field] for row in rows if _is_int(row.get(field))]
    if not values:
        return None
    value = statistics.median(values)
    return int(value) if float(value).is_integer() else round(value, 1)


def _fmt(value: Any) -> str:
    return "—" if value is None else str(value)


def _group_key(row: dict[str, Any]) -> tuple[str, str, str, str]:
    return row["game_version"], row["difficulty_id"], row["modifier_id"], row["expedition_mode_id"]


def _group_table(rows: list[dict[str, Any]], minimum_repeats: int) -> list[str]:
    if not rows:
        return ["Нет пригодных забегов.", ""]
    grouped: dict[tuple[str, str, str, str], list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        grouped[_group_key(row)].append(row)
    lines = [
        "| Сборка | Сложность | Модификатор | Режим | N | Seed | Возврат | Медиана циклов | Медиана боссов | Материалы получены / сохранены | Кристаллы получены / сохранены | Медиана времени, сек. | Оценка выборки |",
        "|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|",
    ]
    for key, group in sorted(grouped.items()):
        returned = sum(1 for row in group if row["outcome"] == "return")
        seeds = {row["seed"] for row in group if row["seed"] > 0}
        times = [row["run_elapsed_seconds"] for row in group if row["telemetry_schema"] >= 1 and row["run_elapsed_seconds"] > 0]
        n = len(group)
        if n < minimum_repeats:
            sample_label = f"Мало данных (<{minimum_repeats})"
        elif len(seeds) < 3:
            sample_label = "Мало разных seed"
        else:
            sample_label = "Начальный сигнал; не вердикт"
        kept_scrap = _median(group, "kept_scrap")
        earned_scrap = _median(group, "earned_scrap")
        kept_crystals = _median(group, "kept_crystals")
        earned_crystals = _median(group, "earned_crystals")
        lines.append(
            "| %s | %s | %s | %s | %d | %d | %d/%d (%.0f%%) | %s | %s | %s / %s | %s / %s | %s | %s |" % (
                key[0], key[1], key[2], key[3], n, len(seeds), returned, n,
                (returned / n * 100.0), _fmt(_median(group, "loops")),
                _fmt(_median(group, "bosses_defeated")), _fmt(earned_scrap), _fmt(kept_scrap),
                _fmt(earned_crystals), _fmt(kept_crystals),
                _fmt(int(statistics.median(times)) if times else None), sample_label,
            )
        )
    lines.append("")
    return lines


def build_report(metadata: dict[str, Any], rows: list[dict[str, Any]], warnings: list[str],
                 invalid_count: int, duplicate_count: int, input_shape: str,
                 label: str, godot_version: str, source_fingerprint: str, minimum_repeats: int) -> str:
    versions = sorted({row["game_version"] for row in rows})
    legacy = sum(1 for row in rows if int(row.get("telemetry_schema", 0)) < 1)
    seeds = {row["seed"] for row in rows if row["seed"] > 0}
    lines = [
        "# Abyss Loop — анализ реальных забегов (Stage64B)", "",
        "## Паспорт данных", "",
        f"- Источник: {input_shape} (локальный/offline анализ).",
        f"- Метка сборки: {label or str(metadata.get('build_label', 'не указана'))}.",
        f"- Версия Godot: {godot_version or str(metadata.get('godot_version', 'не указана'))}.",
        f"- Source fingerprint: {source_fingerprint or str(metadata.get('source_fingerprint', 'не указан'))}.",
        f"- Версии игры в данных: {', '.join(versions) if versions else 'нет'}.",
        f"- Пригодных забегов: {len(rows)}; уникальных seed: {len(seeds)}; исключено невалидных: {invalid_count}; дубликатов run_id: {duplicate_count}.",
        f"- Записей без новой телеметрии Stage68B: {legacy}.",
        "- Анализатор читает файлы локально, ничего не отправляет и не изменяет входное сохранение.",
        "",
        "## Сводка", "",
    ]
    if rows:
        returns = sum(1 for row in rows if row["outcome"] == "return")
        losses = len(rows) - returns
        lines.extend([
            f"- Возвращений: {returns}/{len(rows)} ({returns / len(rows) * 100:.1f}%). Поражений: {losses}/{len(rows)}.",
            f"- Медиана циклов: {_fmt(_median(rows, 'loops'))}; медиана побед: {_fmt(_median(rows, 'victories'))}; медиана событий: {_fmt(_median(rows, 'events_resolved'))}.",
            f"- Медиана потерянных материалов: {_fmt(_median(rows, 'lost_scrap'))}; кристаллов: {_fmt(_median(rows, 'lost_crystals'))}.",
            f"- Медиана размещений: дорога {_fmt(_median(rows, 'road_placements'))}, ландшафт {_fmt(_median(rows, 'world_placements'))}.",
            "",
        ])
    else:
        lines.extend(["Нет строк для итоговой статистики.", ""])
    lines.extend(["## По сопоставимым группам", ""])
    lines.extend(_group_table(rows, minimum_repeats))
    lines.extend([
        "## Интерпретация и ограничения", "",
        "- Это наблюдения реальных забегов из локальной истории профиля, но не автоматическое решение об изменении баланса.",
        f"- Группа считается достаточно заполненной только для первичного просмотра при N≥{minimum_repeats} и минимум 3 разных seed. Даже такая группа не доказывает статистическую значимость.",
        "- Сравнивать следует одинаковую версию игры, сложность, модификатор и режим. Если эти условия различаются, строки намеренно разделены.",
        "- Время прохождения доступно только для телеметрии схемы 1. Старые записи не дополняются выдуманными значениями.",
        "- Баланс не оценён автоматически: решение требует гипотезы, повторов на одинаковых настройках и проверки соседнего диапазона сложности.",
        "",
    ])
    if warnings:
        lines.extend(["## Предупреждения", ""])
        for warning in warnings[:100]:
            lines.append(f"- {warning}")
        if len(warnings) > 100:
            lines.append(f"- Ещё предупреждений: {len(warnings) - 100}.")
        lines.append("")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Локальный save JSON или экспорт runs/expedition_history")
    parser.add_argument("--output", required=True, type=Path, help="Путь для Markdown-отчёта; не должен совпадать с входным файлом")
    parser.add_argument("--label", default="", help="Понятная метка тестируемого ZIP/build")
    parser.add_argument("--godot-version", default="", help="Версия движка при прохождении забегов")
    parser.add_argument("--source-fingerprint", default="", help="SHA-256 исходников, если известен")
    parser.add_argument("--minimum-repeats", type=int, default=5, help="N для первичного просмотра (по умолчанию 5)")
    args = parser.parse_args(argv)
    source = args.input.expanduser().resolve()
    output = args.output.expanduser().resolve()
    if source == output:
        parser.error("output не должен перезаписывать входное сохранение")
    if args.minimum_repeats < 2 or args.minimum_repeats > 100:
        parser.error("minimum-repeats должен быть в диапазоне 2..100")
    if args.source_fingerprint and not re.fullmatch(r"[0-9a-fA-F]{64}", args.source_fingerprint):
        parser.error("source-fingerprint должен содержать 64 hex-символа")
    try:
        metadata, raw_rows, input_shape = load_input(source)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    rows, warnings, invalid_count, duplicate_count = normalize_runs(raw_rows)
    report = build_report(metadata, rows, warnings, invalid_count, duplicate_count, input_shape,
                          args.label, args.godot_version, args.source_fingerprint.lower(), args.minimum_repeats)
    try:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(report, encoding="utf-8")
    except OSError as exc:
        print(f"ERROR: Не удалось записать отчёт: {exc}", file=sys.stderr)
        return 3
    print(f"Отчёт: {output}")
    print(f"Пригодных забегов: {len(rows)}; исключено: {invalid_count}; дубликатов: {duplicate_count}.")
    print("Статистика описательная; автоматический вердикт о балансе не формируется.")
    return 0 if rows else 2


if __name__ == "__main__":
    raise SystemExit(main())

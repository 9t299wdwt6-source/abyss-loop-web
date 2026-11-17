"""Compare clean-start and loot-generated prepared engine runs on floors 5-8.

The prepared loadout is synthetic but uses the production InventorySystem drop
generator with prior-floor loop/hero-level context. This remains automated QA,
not a player-history replay, manual playtest, or statistically final balance verdict.
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


def read_capture(path: Path, expected_prepared: bool) -> dict[int, list[dict[str, Any]]]:
    try:
        payload = json.loads(path.expanduser().resolve().read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{path}: {exc}") from exc
    if not isinstance(payload, dict) or not isinstance(payload.get("runs"), list):
        raise ValueError(f"{path}: expected a JSON object with a runs array")
    metadata = payload.get("metadata", {})
    if not isinstance(metadata, dict) or metadata.get("capture_kind") != "automated_engine_run":
        raise ValueError(f"{path}: capture is not labelled automated_engine_run")
    if bool(metadata.get("prepared_loadout_run", False)) != expected_prepared:
        raise ValueError(f"{path}: prepared_loadout_run metadata does not match expected mode")
    expected_seeds = metadata.get("fixed_seeds", [])
    if expected_seeds != [91001, 91003, 91007]:
        raise ValueError(f"{path}: expected the three matched Stage92 seeds")
    grouped: dict[int, list[dict[str, Any]]] = defaultdict(list)
    seen: set[str] = set()
    for row in payload["runs"]:
        if not isinstance(row, dict):
            raise ValueError(f"{path}: a run row is not an object")
        floor_id = row.get("floor_id")
        run_id = str(row.get("run_id", ""))
        if not isinstance(floor_id, int) or isinstance(floor_id, bool) or floor_id not in range(1, 9):
            raise ValueError(f"{path}: invalid Abyss floor ID in a run row")
        # The clean-start capture covers all eight floors; the paired comparison
        # intentionally uses only the shared high-floor range 5..8.
        if floor_id < 5:
            if expected_prepared:
                raise ValueError(f"{path}: prepared capture unexpectedly contains floor {floor_id}")
            continue
        if not run_id or run_id in seen:
            raise ValueError(f"{path}: missing or duplicate run ID")
        if row.get("capture_kind") != "automated_engine_run" or row.get("outcome") not in {"return", "defeat"}:
            raise ValueError(f"{path}: invalid automated run result")
        if expected_prepared:
            loadout = row.get("capture_equipped_loadout", {})
            if not isinstance(loadout, dict) or set(loadout) != {"weapon", "helmet", "armor", "shield", "amulet", "core"}:
                raise ValueError(f"{path}: floor {floor_id} row lacks a complete six-slot loadout")
            if int(row.get("capture_loadout_completed_slots", 0)) != 6:
                raise ValueError(f"{path}: floor {floor_id} loadout slot count is not six")
        seen.add(run_id)
        grouped[floor_id].append(row)
    missing = [floor_id for floor_id in (5, 6, 7, 8) if not grouped[floor_id]]
    if missing:
        raise ValueError(f"{path}: high floors without captures: {missing}")
    for floor_id in (5, 6, 7, 8):
        seeds = sorted(int(row.get("capture_seed", -1)) for row in grouped[floor_id])
        if seeds != expected_seeds:
            raise ValueError(f"{path}: floor {floor_id} seed set {seeds} does not match {expected_seeds}")
    return grouped


def median(rows: list[dict[str, Any]], key: str) -> str:
    values = [
        row[key] for row in rows
        if isinstance(row.get(key), (int, float)) and not isinstance(row.get(key), bool)
    ]
    return str(round(statistics.median(values), 1)) if values else "—"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-input", required=True, type=Path)
    parser.add_argument("--prepared-input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    if output in {args.base_input.expanduser().resolve(), args.prepared_input.expanduser().resolve()}:
        parser.error("output must not overwrite a capture input")
    try:
        base = read_capture(args.base_input, expected_prepared=False)
        prepared = read_capture(args.prepared_input, expected_prepared=True)
        for floor_id in (5, 6, 7, 8):
            base_seeds = sorted(int(row.get("capture_seed", -1)) for row in base[floor_id])
            prepared_seeds = sorted(int(row.get("capture_seed", -1)) for row in prepared[floor_id])
            if base_seeds != prepared_seeds:
                raise ValueError(f"floor {floor_id}: bare/prepared seeds differ: {base_seeds} vs {prepared_seeds}")
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    lines = [
        "# Abyss Loop — Stage92: поздние этажи с подготовленной экипировкой",
        "",
        "## Метод",
        "",
        "- Сравниваются одинаковые этажи 5–8 и одинаковые фиксированные seed из основной матрицы.",
        "- Базовый вариант начинает с чистого профиля без постоянной экипировки.",
        "- Подготовленный вариант создаёт по одному предмету для каждого из шести слотов штатной функцией InventorySystem.roll_item, затем регистрирует и надевает предметы штатными API GameState.register_item/equip_item.",
        "- Для синтетической экипировки использован контекст предыдущего этажа: 6 завершённых циклов, уровень героя 7, предыдущий этаж как источник ранга. Формулы характеристик, урон и враги после генерации не изменяются.",
        "- Это scripted engine QA, не реальная история игрока и не ручной playtest. Небольшая выборка не даёт статистически окончательного вердикта о балансе.",
        "",
        "## Сравнение результатов",
        "",
        "| Этаж | N | Возвраты без экипировки | Возвраты с экипировкой | Медиана циклов: без / с | Победы: без / с | Стартовая атака с экипировкой | Стартовая защита с экипировкой | Сила 6 предметов | Ранг предметов |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for floor_id in (5, 6, 7, 8):
        base_rows = base[floor_id]
        prepared_rows = prepared[floor_id]
        base_returns = sum(1 for row in base_rows if row["outcome"] == "return")
        prepared_returns = sum(1 for row in prepared_rows if row["outcome"] == "return")
        lines.append("| %d | %d | %d/%d | %d/%d | %s / %s | %s / %s | %s | %s | %s | %s–%s |" % (
            floor_id,
            min(len(base_rows), len(prepared_rows)),
            base_returns, len(base_rows),
            prepared_returns, len(prepared_rows),
            median(base_rows, "loops"), median(prepared_rows, "loops"),
            median(base_rows, "victories"), median(prepared_rows, "victories"),
            median(prepared_rows, "start_attack"),
            median(prepared_rows, "start_defense"),
            median(prepared_rows, "capture_equipment_power"),
            min(int(row.get("capture_loadout_rank_min", 0)) for row in prepared_rows),
            max(int(row.get("capture_loadout_rank_max", 0)) for row in prepared_rows),
        ))
    prepared_metadata = json.loads(args.prepared_input.read_text(encoding="utf-8-sig")).get("metadata", {})
    lines.extend([
        "",
        "## Профиль тестовой экипировки",
        "",
        f"- Версия игры: {prepared_metadata.get('game_version', 'не указана')}.",
        f"- Версия Godot: {prepared_metadata.get('godot_version', 'не указана')}.",
        f"- Забегов с подготовленной экипировкой: {sum(len(rows) for rows in prepared.values())}.",
        f"- Seed: {', '.join(str(seed) for seed in prepared_metadata.get('fixed_seeds', []))}.",
        "- Генератор предметов и сохранение экипировки — производственные игровые функции; seed раздачи отделён от seed маршрута.",
        "",
        "## Интерпретация",
        "",
        "- Если результат с экипировкой заметно лучше, это подтверждает важность постоянного арсенала и прогрессии между этажами; это не означает, что голый старт должен быть столь же успешен.",
        "- Если подготовленный вариант также регулярно завершается поражением до первого цикла, нужно отдельно исследовать стартовый риск, восстановление, обычные группы и силу экипировки.",
        "- Небольшое число автоматизированных прогонов не заменяет ручные прохождения с разными билдами, проверку боссов и тесты нескольких уровней улучшения.",
        "",
    ])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")
    print(f"Report: {output}")
    print("Prepared high-floor sample validated; automated evidence only, no automatic balance verdict.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

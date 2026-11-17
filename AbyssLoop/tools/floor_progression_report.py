"""Offline report for Stage92's eight-floor automated engine sample."""
from __future__ import annotations
import argparse
import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    source, output = args.input.expanduser().resolve(), args.output.expanduser().resolve()
    if source == output:
        parser.error("output must not overwrite input")
    try:
        payload = json.loads(source.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    if not isinstance(payload, dict) or not isinstance(payload.get("runs"), list):
        print("ERROR: expected JSON object with runs array", file=sys.stderr)
        return 2
    metadata = payload.get("metadata", {})
    if not isinstance(metadata, dict) or metadata.get("capture_kind") != "automated_engine_run":
        print("ERROR: capture source must be automated_engine_run", file=sys.stderr)
        return 2
    grouped: dict[int, list[dict]] = defaultdict(list)
    seen: set[str] = set()
    invalid = 0
    for row in payload["runs"]:
        if not isinstance(row, dict):
            invalid += 1
            continue
        floor_id, run_id = row.get("floor_id"), str(row.get("run_id", ""))
        if not isinstance(floor_id, int) or isinstance(floor_id, bool) or floor_id not in range(1, 9):
            invalid += 1
            continue
        if not run_id or run_id in seen or row.get("capture_kind") != "automated_engine_run" or row.get("outcome") not in {"return", "defeat"}:
            invalid += 1
            continue
        seen.add(run_id)
        grouped[floor_id].append(row)
    missing = [floor_id for floor_id in range(1, 9) if not grouped[floor_id]]
    if invalid or missing:
        print(f"ERROR: invalid rows={invalid}; floors without samples={missing}", file=sys.stderr)
        return 1
    def median(rows: list[dict], key: str) -> str:
        values = [r[key] for r in rows if isinstance(r.get(key), (int, float)) and not isinstance(r.get(key), bool)]
        return str(round(statistics.median(values), 1)) if values else "—"
    lines = [
        "# Abyss Loop — Stage92: восемь этажей",
        "",
        "## Паспорт",
        "",
        f"- Версия игры: {metadata.get('game_version', 'не указана')}",
        f"- Версия Godot: {metadata.get('godot_version', 'не указана')}",
        f"- Забегов: {len(seen)}; seed: {len({r.get('seed') for group in grouped.values() for r in group})}.",
        "- Источник: automated_engine_run — скриптовые прогоны production ExpeditionManager, не ручное прохождение.",
        "- Это сравнительная проверка связности восьми этажей, а не статистически достаточная выборка для окончательного решения о балансе.",
        "",
        "## Поэтажная сводка",
        "",
        "| Этаж | Название | N | Возвраты | Медиана циклов | Медиана побед | Материалы | Кристаллы | Попадания карт этажа в отдельной тестовой раздаче |",
        "|---:|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for floor_id in range(1, 9):
        rows = grouped[floor_id]
        returned = sum(1 for r in rows if r["outcome"] == "return")
        lines.append("| %d | %s | %d | %d/%d | %s | %s | %s | %s | %s |" % (
            floor_id, str(rows[0].get("floor_name", f"Этаж {floor_id}")), len(rows), returned, len(rows),
            median(rows, "loops"), median(rows, "victories"), median(rows, "earned_scrap"),
            median(rows, "earned_crystals"), median(rows, "floor_card_pool_hits")
        ))
    lines.extend([
        "",
        "## Ограничения",
        "",
        "- Прогоны используют production route/combat/event/perk/settlement методы и фиксированные seed.",
        "- Отдельная тестовая раздача проверяет достижимость карт заданного этажа, но не заменяет частоты карт на длинном ручном прохождении.",
        "- Формулы здоровья, атаки, защиты, выпадения и наград не форсировались.",
        "- Автоматизированные решения и малое N не заменяют ручной playtest, сравнение билдов экипировки и проверку соседних диапазонов сложности.",
        "",
    ])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")
    print(f"Report: {output}")
    print(f"Valid runs: {len(seen)}; all eight floors represented.")
    print("Automated QA only; no automatic balance verdict.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

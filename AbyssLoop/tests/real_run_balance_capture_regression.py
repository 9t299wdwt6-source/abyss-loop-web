"""Regression tests for the local-only Stage64B real-run balance capture analyzer."""
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = ROOT / "tools" / "real_run_balance.py"
spec = importlib.util.spec_from_file_location("real_run_balance", TOOL_PATH)
if spec is None or spec.loader is None:
    raise SystemExit("unable to import tools/real_run_balance.py")
real_run_balance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(real_run_balance)


def sample(run_id: str = "r1", *, outcome: str = "return", seed: int = 42,
           version: str = "0.61.0", loops: int = 2, mode: str = "standard",
           modifier: str = "standard", schema: int = 1,
           capture_kind: str | None = None, contract_id: str = "none",
           challenge_id: str = "none") -> dict:
    row = {
        "run_id": run_id, "outcome": outcome, "seed": seed, "game_version": version,
        "difficulty_id": "standard", "modifier_id": modifier, "expedition_mode_id": mode,
        "loops": loops, "hero_level": 2, "victories": 4, "bosses_defeated": 1,
        "elites_defeated": 0, "events_resolved": 1, "earned_scrap": 20,
        "earned_crystals": 2, "kept_scrap": 20 if outcome == "return" else 8,
        "kept_crystals": 2 if outcome == "return" else 0, "lost_scrap": 0 if outcome == "return" else 12,
        "lost_crystals": 0 if outcome == "return" else 2, "telemetry_schema": schema,
        "run_elapsed_seconds": 80, "start_hp": 30, "start_max_hp": 30,
        "end_hp": 15, "end_max_hp": 40, "road_placements": 2,
        "world_placements": 1, "danger": 2.2,
        "contract_id": contract_id, "challenge_id": challenge_id,
    }
    if capture_kind is not None:
        row["capture_kind"] = capture_kind
    return row


checks: dict[str, bool] = {}
with tempfile.TemporaryDirectory(prefix="abyss_real_balance_test_") as temp_dir:
    temp = Path(temp_dir)
    raw_profile = {"version": 3, "envelope_version": 2, "data": {"expedition_history": [sample()]}}
    profile_path = temp / "profile.json"
    profile_path.write_text(json.dumps(raw_profile), encoding="utf-8")
    metadata, rows, shape = real_run_balance.load_input(profile_path)
    checks["Godot save envelope exposes bounded expedition history"] = len(rows) == 1 and shape == "Godot save envelope"

    export_path = temp / "export.json"
    export_path.write_text(json.dumps({
        "metadata": {"build_label": "QA", "capture_kind": "automated_engine_run"},
        "runs": [sample()],
    }), encoding="utf-8")
    export_meta, export_rows, export_shape = real_run_balance.load_input(export_path)
    checks["standalone runs JSON export is accepted"] = len(export_rows) == 1 and export_meta.get("build_label") == "QA" and export_shape == "exported runs"
    checks["export-level capture kind is propagated to rows without an override"] = export_rows[0].get("capture_kind") == "automated_engine_run"

    try:
        real_run_balance.load_input(temp / "does-not-exist.json")
    except ValueError:
        checks["missing/malformed input fails closed"] = True
    else:
        checks["missing/malformed input fails closed"] = False

runs, warnings, invalid_count, duplicate_count = real_run_balance.normalize_runs([
    sample("a"), sample("a"), sample("bad-outcome", outcome="quit"),
    {**sample("negative"), "loops": -1}, "not a record", sample("b", outcome="defeat", seed=43),
])
checks["duplicate run IDs are excluded without double counting"] = len(runs) == 2 and duplicate_count == 1
checks["unsupported outcome is rejected"] = invalid_count >= 1 and any("outcome" in warning for warning in warnings)
checks["negative metric and non-object rows are rejected"] = invalid_count == 3
checks["float danger remains valid while integer metrics are strict"] = any(row["run_id"] == "a" and row["danger"] == 2.2 for row in runs)

mixed, mixed_warnings, _, _ = real_run_balance.normalize_runs([
    sample("a", version="0.61.0", mode="standard"),
    sample("b", version="0.61.0", mode="long_expedition", seed=43),
    sample("c", version="0.62.0", modifier="glass_cannon", seed=44),
    sample("auto", capture_kind="automated_engine_run", seed=45),
])
report = real_run_balance.build_report({}, mixed, mixed_warnings, 0, 0, "exported runs", "test label", "4.7.2.stable", "", 5)
checks["comparison groups separate build, floor, modifier, contract, challenge, and capture source"] = (
    report.count("| 0.61.0 | 1/8 | Этаж 1 | standard | none | none | profile_history | 1 |") == 1
    and report.count("| 0.61.0 | 1/8 | Этаж 1 | standard | none | none | automated_engine_run | 1 |") == 1
    and "2/8" in report and "glass_cannon" in report
)

contract_rows, contract_warnings, contract_invalid, contract_duplicates = real_run_balance.normalize_runs([
    sample("bounty", seed=51, contract_id="bounty_hunter"),
    sample("events", seed=52, contract_id="event_archive"),
    sample("resonance", seed=53, modifier="resonance", challenge_id="resonance_boss"),
])
contract_report = real_run_balance.build_report({}, contract_rows, contract_warnings, contract_invalid, contract_duplicates, "exported runs", "test label", "4.7.2.stable", "", 3)
checks["contract and modifier challenge variants remain distinct comparison groups"] = (
    "bounty_hunter" in contract_report and "event_archive" in contract_report
    and "resonance_boss" in contract_report and len(contract_rows) == 3
)
checks["report explicitly distinguishes scripted engine QA from player history"] = "not human" in report.lower() or "а не человеческое прохождение" in report
checks["small samples are explicitly marked insufficient"] = "Мало данных (<5)" in report
checks["report does not invent automatic balance verdict"] = "Баланс не оценён автоматически" in report and "Баланс подтверждён" not in report and "дисбаланс обнаружен" not in report
checks["legacy entries are counted and never assigned fabricated duration"] = "без новой телеметрии Stage68B: 0" in report
legacy_rows, _, _, _ = real_run_balance.normalize_runs([sample("legacy", schema=0)])
legacy_report = real_run_balance.build_report({}, legacy_rows, [], 0, 0, "exported runs", "", "", "", 5)
checks["duration requires telemetry schema 1"] = "Медиана времени, сек. |" in legacy_report and "| — | Мало данных" in legacy_report
checks["run report contains no local input file path"] = str(profile_path) not in report
checks["new capture schema includes duration and baseline metrics"] = all(token in (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8") for token in ["run_elapsed_seconds", "run_baseline", '"start_hp"', '"end_hp"', '"road_placements"', '"world_placements"'])
checks["run history normalization preserves telemetry but remains bounded"] = all(token in (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8") for token in ['"run_elapsed_seconds": maxi(0, int(source.get', '"start_loadout_ids": start_loadout_ids', 'const MAX_EXPEDITION_HISTORY := 50'])
checks["save validation caps supported telemetry schema and validates metrics"] = 'int(history_entry.get("telemetry_schema", 0)) > 1' in (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8") and '"run_elapsed_seconds"' in (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
checks["tool explicitly documents local-only/no-network behavior"] = "never edits a save or sends data" in TOOL_PATH.read_text(encoding="utf-8")
checks["capture source labels are normalized to a bounded allowlist"] = all(token in TOOL_PATH.read_text(encoding="utf-8") for token in ['"automated_engine_run"', '"manual_playtest"', '"unknown_source"'])

failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"[{ 'PASS' if passed else 'FAIL' }] {name}")
if failed:
    raise SystemExit(f"REAL-RUN BALANCE CAPTURE REGRESSION FAILED: {len(failed)} checks: {failed}")
print(f"REAL-RUN BALANCE CAPTURE REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("Tests use synthetic fixtures only; no real-run data or balance verdict is claimed.")

#!/usr/bin/env python3
"""Run Python static/regression checks in parallel and retain a machine-readable report.
This suite is intentionally separate from Godot's GDScript smoke test.
"""
from __future__ import annotations
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
import os
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.test_process_runner import run_command
TEST_DIR = ROOT / "tests"
REPORT_DIR = TEST_DIR / "reports"
REPORT_DIR.mkdir(parents=True, exist_ok=True)
REPORT_PATH = REPORT_DIR / "STATIC_TEST_REPORT.txt"
EXCLUDED = {"run_static_suite.py"}
TIMEOUT_SECONDS = 75
DEFAULT_MAX_WORKERS = 4
MAX_ALLOWED_WORKERS = 4


def configured_workers() -> int:
    """Allow callers to lower concurrency while retaining the original parallel default."""
    raw = os.environ.get("ABYSS_LOOP_TEST_WORKERS", str(DEFAULT_MAX_WORKERS))
    try:
        requested = int(raw)
    except ValueError:
        requested = DEFAULT_MAX_WORKERS
    return max(1, min(MAX_ALLOWED_WORKERS, requested))


MAX_WORKERS = configured_workers()
scripts = sorted(path for path in TEST_DIR.glob("*.py") if path.name not in EXCLUDED)
results_by_name: dict[str, tuple[str, str, float, str]] = {}
start_all = time.monotonic()


def run_one(script: Path) -> tuple[str, str, float, str]:
    start = time.monotonic()
    try:
        return_code, stdout, timed_out = run_command(
            [sys.executable, str(script)], cwd=ROOT, env=os.environ.copy(),
            timeout=TIMEOUT_SECONDS,
        )
        duration = time.monotonic() - start
        output = stdout.strip()
        if timed_out:
            status = "TIMEOUT"
            output = f"timeout after {TIMEOUT_SECONDS}s; process tree terminated\n{output}".strip()
        else:
            status = "PASS" if return_code == 0 else "FAIL"
            if return_code != 0:
                output = f"exit code {return_code}\n{output}"
        return (script.name, status, duration, output)
    except OSError as exc:
        duration = time.monotonic() - start
        return (script.name, "FAIL", duration, f"could not start test process: {exc}")


def ordered_results() -> list[tuple[str, str, float, str]]:
    return [results_by_name[script.name] for script in scripts if script.name in results_by_name]


def write_report() -> None:
    results = ordered_results()
    failures_now = [row for row in results if row[1] != "PASS"]
    total_now = time.monotonic() - start_all
    lines = [
        "ABYSS LOOP — STATIC TEST REPORT",
        f"UTC: {datetime.now(timezone.utc).isoformat()}",
        f"Root: {ROOT.name}/ (portable project root)",
        f"Checks discovered: {len(scripts)}; checks completed: {len(results)}; passed: {len(results) - len(failures_now)}; failed/timed out: {len(failures_now)}",
        f"Duration so far: {total_now:.2f}s",
        f"Execution: {min(MAX_WORKERS, max(1, len(scripts)))} worker(s); each subprocess has a {TIMEOUT_SECONDS}s timeout and timeout cleanup kills its process tree.",
        "NOTE: This report does not establish successful Godot/GDScript compilation or in-engine behavior.",
        "",
    ]
    for name, status, duration, output in results:
        lines.extend([f"[{status}] {name} ({duration:.2f}s)", output, ""])
    REPORT_PATH.write_text("\n".join(lines), encoding="utf-8")


print(f"ABYSS LOOP STATIC TEST SUITE — {len(scripts)} checks", flush=True)
print(f"Scope: Python static/regression tests only; {min(MAX_WORKERS, max(1, len(scripts)))} worker(s); GDScript runtime is separate.", flush=True)
with ThreadPoolExecutor(max_workers=min(MAX_WORKERS, max(1, len(scripts)))) as pool:
    future_map = {pool.submit(run_one, script): script for script in scripts}
    for completed, future in enumerate(as_completed(future_map), start=1):
        name, status, duration, output = future.result()
        results_by_name[name] = (name, status, duration, output)
        print(f"[{completed}/{len(scripts)}] [{status}] {name} ({duration:.2f}s)", flush=True)
        if output:
            for line in output.splitlines():
                print(f"    {line}", flush=True)
        write_report()  # durable checkpoint as each test finishes

results = ordered_results()
failures = [row for row in results if row[1] != "PASS"]
write_report()
total = time.monotonic() - start_all
print(f"\nREPORT: {REPORT_PATH.relative_to(ROOT)}", flush=True)
print(f"SUMMARY: {len(results) - len(failures)}/{len(scripts)} passed in {total:.2f}s", flush=True)
print("Godot runtime smoke remains separate: godot --headless --path . --script res://tests/smoke_test.gd", flush=True)
sys.exit(1 if failures or len(results) != len(scripts) else 0)

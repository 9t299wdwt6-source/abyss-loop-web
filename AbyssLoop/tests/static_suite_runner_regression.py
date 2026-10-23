#!/usr/bin/env python3
"""Regression tests for reliable, bounded static-suite subprocess execution."""
from __future__ import annotations

from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.test_process_runner import run_command  # noqa: E402

runner_source = (ROOT / "tests" / "run_static_suite.py").read_text(encoding="utf-8")
release_batch = (ROOT / "RUN_RELEASE_GATE_WINDOWS.bat").read_text(encoding="utf-8")
tests_batch = (ROOT / "RUN_TESTS_WINDOWS.bat").read_text(encoding="utf-8")

assert "ABYSS_LOOP_TEST_WORKERS" in runner_source, "worker count must be configurable"
assert "DEFAULT_MAX_WORKERS = 4" in runner_source, "parallel default must remain bounded and performant"
assert "MAX_ALLOWED_WORKERS = 4" in runner_source, "parallel worker count must have a hard cap"
assert "timeout cleanup kills its process tree" in runner_source, "report must describe timeout cleanup"
assert "ABYSS_LOOP_TEST_WORKERS" in release_batch and "ABYSS_LOOP_TEST_WORKERS" in tests_batch, "Windows QA launchers must choose deterministic worker settings"
print("PASS: static suite keeps the four-worker default and bounds optional concurrency")
print("PASS: both Windows QA launchers set a deterministic default")

# Verify the subprocess helper captures normal output and returns the status.
code, output, timed_out = run_command(
    [sys.executable, "-c", "print('runner regression ok')"],
    cwd=ROOT,
    timeout=5,
)
assert code == 0 and not timed_out and "runner regression ok" in output, (code, timed_out, output)
print("PASS: normal process returns captured output and exit status")

# The grandchild inherits stdout. On timeout, process-tree cleanup must close
# that pipe too; otherwise communicate() can hang after killing only the parent.
parent_code = (
    "import subprocess,sys,time; "
    "subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)']); "
    "print('grandchild-started', flush=True); time.sleep(30)"
)
started = time.monotonic()
code, output, timed_out = run_command(
    [sys.executable, "-c", parent_code],
    cwd=ROOT,
    timeout=2.5,
)
elapsed = time.monotonic() - started
assert timed_out and elapsed < 8, f"timeout cleanup was not bounded: timed_out={timed_out}, elapsed={elapsed:.2f}s"
assert "grandchild-started" in output, f"expected captured child output, got: {output!r}"
print(f"PASS: timed-out process tree is terminated without a hanging output pipe ({elapsed:.2f}s)")
print("STATIC SUITE RUNNER REGRESSION PASSED: 3 functional checks plus launcher/config guards")

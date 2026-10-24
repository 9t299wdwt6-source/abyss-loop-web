#!/usr/bin/env python3
"""Functional regression for process-tree cleanup in runtime release-gate steps."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from run_runtime_gate import run_step  # noqa: E402

normal = run_step(
    "Runner normal exit",
    [sys.executable, "-c", "print('runtime gate runner normal output')"],
    ROOT, os.environ.copy(), timeout=5,
)
assert normal["status"] == "PASS" and "runtime gate runner normal output" in normal["output"], normal
print("PASS: runtime-gate step captures normal output and exit status")

failed = run_step(
    "Runner nonzero exit",
    [sys.executable, "-c", "import sys; print('expected controlled failure'); sys.exit(7)"],
    ROOT, os.environ.copy(), timeout=5,
)
assert failed["status"] == "FAIL" and failed["returncode"] == "7", failed
assert "expected controlled failure" in failed["output"], failed
print("PASS: runtime-gate step preserves nonzero exit status and diagnostic output")

# The child inherits stdout; killing only its parent would leave that pipe open.
parent_code = (
    "import subprocess,sys,time; "
    "subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)']); "
    "print('runtime-gate-grandchild-started', flush=True); time.sleep(30)"
)
started = time.monotonic()
timed_out = run_step(
    "Runner timeout cleanup",
    [sys.executable, "-c", parent_code],
    ROOT, os.environ.copy(), timeout=2.5,
)
elapsed = time.monotonic() - started
assert timed_out["status"] == "TIMEOUT" and timed_out["returncode"] == "timeout", timed_out
assert "runtime-gate-grandchild-started" in timed_out["output"], timed_out
assert elapsed < 8, f"timed-out process tree was not cleaned up promptly ({elapsed:.2f}s)"
print(f"PASS: runtime-gate timeout terminates the process tree without hanging ({elapsed:.2f}s)")

runner_source = (ROOT / "tools" / "run_runtime_gate.py").read_text(encoding="utf-8")
assert "from test_process_runner import run_command" in runner_source
assert "timed_out" in runner_source and "process group" in runner_source
assert 'res://tests/save_system_regression_runner.tscn' in runner_source, "save regression must run as a scene so project autoload singletons are initialized"
assert '--script", "res://tests/save_system_regression.gd' not in runner_source, "save regression must not bypass project autoload initialization"
print("RUNTIME GATE PROCESS CLEANUP REGRESSION PASSED: 3 functional checks and shared cleanup guard")

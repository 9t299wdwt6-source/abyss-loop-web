#!/usr/bin/env python3
"""Run a subprocess with a timeout that also cleans up spawned descendants."""
from __future__ import annotations

import os
import signal
import subprocess
from pathlib import Path
from typing import Mapping, Sequence


def _kill_process_tree(proc: subprocess.Popen[str]) -> None:
    """Terminate the whole isolated process group/tree, not only its parent."""
    if os.name == "nt":
        try:
            subprocess.run(
                ["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=5,
            )
        except (OSError, subprocess.TimeoutExpired):
            try:
                proc.kill()
            except OSError:
                pass
        return

    try:
        # Popen was started with start_new_session=True, so PID is also its
        # process-group ID. Killing the group closes inherited stdout pipes.
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    except OSError:
        try:
            proc.kill()
        except OSError:
            pass


def run_command(
    command: Sequence[str],
    *,
    cwd: Path,
    env: Mapping[str, str] | None = None,
    timeout: float,
) -> tuple[int, str, bool]:
    """Return ``(return_code, combined_output, timed_out)`` safely.

    A timed-out child can leave grandchildren holding the captured output pipe.
    ``subprocess.run(timeout=...)`` may then wait while draining that pipe. This
    helper isolates each command in its own process group and kills the group
    before collecting the final output.
    """
    kwargs: dict[str, object] = {
        "cwd": str(cwd),
        "env": dict(env) if env is not None else None,
        "text": True,
        "stdout": subprocess.PIPE,
        "stderr": subprocess.STDOUT,
    }
    if os.name == "nt":
        kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        kwargs["start_new_session"] = True

    proc: subprocess.Popen[str] = subprocess.Popen(list(command), **kwargs)  # type: ignore[arg-type]
    try:
        output, _ = proc.communicate(timeout=timeout)
        return int(proc.returncode or 0), output or "", False
    except subprocess.TimeoutExpired:
        _kill_process_tree(proc)
        try:
            output, _ = proc.communicate(timeout=10)
        except subprocess.TimeoutExpired as exc:
            # Final fallback: don't permit a broken taskkill implementation to
            # freeze the QA suite. This still guarantees the direct child exits.
            try:
                proc.kill()
            except OSError:
                pass
            output, _ = proc.communicate(timeout=5)
            if not output and exc.stdout:
                output = exc.stdout.decode(errors="replace") if isinstance(exc.stdout, bytes) else exc.stdout
        return int(proc.returncode if proc.returncode is not None else -9), output or "", True

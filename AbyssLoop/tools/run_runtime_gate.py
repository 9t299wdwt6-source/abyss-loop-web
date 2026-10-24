#!/usr/bin/env python3
"""Run clean, isolated Godot 4.7.2 release checks without touching the player's save profile."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import sys

from release_integrity import project_fingerprint
from release_preflight import DEFAULT_VERSION, audit_project
from test_process_runner import run_command

ROOT = Path(__file__).resolve().parents[1]
REPORT_DIR = ROOT / "tests" / "reports"
PASS_REPORT = REPORT_DIR / "RUNTIME_GATE_REPORT_RU.md"
FAIL_REPORT = REPORT_DIR / "RUNTIME_GATE_FAILURE_REPORT_RU.md"
TIMEOUT_SECONDS = 120


def run_step(label: str, command: list[str], cwd: Path, env: dict[str, str], timeout: int = TIMEOUT_SECONDS) -> dict[str, str]:
    """Run a gate in an isolated process group and always clean up on timeout.

    This intentionally shares the same process-tree cleanup implementation as
    the static suite. Godot or a smoke-test child must not keep inherited output
    handles open and stall the release gate after the configured timeout.
    """
    rendered_command = redact_local_paths(subprocess.list2cmdline(command))
    try:
        return_code, output, timed_out = run_command(
            command, cwd=cwd, env=env, timeout=timeout,
        )
        if timed_out:
            return {"label": label, "status": "TIMEOUT", "returncode": "timeout",
                    "command": rendered_command, "output": redact_local_paths(output.strip())}
        return {"label": label, "status": "PASS" if return_code == 0 else "FAIL",
                "returncode": str(return_code), "command": rendered_command,
                "output": redact_local_paths(output.strip())}
    except OSError as exc:
        return {"label": label, "status": "FAIL", "returncode": "spawn-error",
                "command": rendered_command, "output": redact_local_paths(str(exc))}


def redact_local_paths(value: str) -> str:
    text = value
    candidates = [
        str(ROOT), str(ROOT).replace("\\", "/"),
        str(Path.home()), str(Path.home()).replace("\\", "/"),
        tempfile.gettempdir(), tempfile.gettempdir().replace("\\", "/"),
    ]
    for candidate in sorted({item for item in candidates if item}, key=len, reverse=True):
        text = text.replace(candidate, "<LOCAL_PATH>")
    return text


def report_text(result: str, fingerprint: str, godot_version: str, build_version: str, steps: list[dict[str, str]], note: str) -> str:
    lines = [
        "# Abyss Loop — отчёт runtime release gate Prototype 61 RC7",
        "",
        f"UTC: {datetime.now(timezone.utc).isoformat()}",
        f"Result: {result}",
        f"Godot version: {godot_version or 'NOT VERIFIED'}",
        f"Build version: {build_version or 'NOT VERIFIED'}",
        f"Source fingerprint: {fingerprint}",
        "",
        "## Gates",
        "",
    ]
    for step in steps:
        lines.append(f"- {step['label']}: {step['status']}")
        lines.append(f"  - Exit: {step['returncode']}")
        lines.append(f"  - Command: `{step['command']}`")
        lines.append("  - Output:")
        lines.append("```text")
        output_lines = step["output"].splitlines()
        if len(output_lines) > 100:
            output_lines = ["… output truncated; last 100 lines shown …"] + output_lines[-100:]
        lines.extend(output_lines if output_lines else ["(no output)"])
        lines.append("```")
        lines.append("")
    lines.extend(["## Interpretation", "", note, ""])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="Full Godot executable path or executable name")
    parser.add_argument("--package-output", required=True, type=Path, help="Runtime-tested ZIP destination outside project root")
    args = parser.parse_args()

    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    # A gate pass from an earlier revision must never validate changed sources.
    PASS_REPORT.unlink(missing_ok=True)
    FAIL_REPORT.unlink(missing_ok=True)
    fingerprint = project_fingerprint(ROOT)
    project_text = (ROOT / "project.godot").read_text(encoding="utf-8")
    build_match = re.search(r'^config/version="([^"]+)"$', project_text, re.M)
    build_version = build_match.group(1) if build_match else ""
    steps: list[dict[str, str]] = []
    godot_version = ""
    success = False
    note = "A successful gate verifies static checks, headless runtime and save regression. Visual review and a full manual expedition still require a human on the target Windows machine."

    static_step = run_step("Static/regression suite", [sys.executable, str(ROOT / "tests" / "run_static_suite.py")], ROOT, os.environ.copy(), timeout=240)
    steps.append(static_step)
    if static_step["status"] != "PASS":
        note = "Static/regression suite failed; Godot runtime checks were not started and no runtime-tested archive was created."
    else:
        preflight_checks = audit_project(ROOT, DEFAULT_VERSION, require_static_report=True)
        preflight_failures = [check for check in preflight_checks if not check.passed]
        if preflight_failures:
            static_step["status"] = "FAIL"
            static_step["output"] += "\nIndependent release preflight FAILED: " + "; ".join(f"{check.name}: {check.detail}" for check in preflight_failures)
            note = "Static checks were green but independent release preflight failed; Godot gates were not started and no runtime-tested archive was created."
        else:
            static_step["output"] += f"\nIndependent release preflight: PASS ({len(preflight_checks)} checks)."
        # Static suite/preflight regenerate reports, so fingerprint only after both pass.
        fingerprint = project_fingerprint(ROOT)
        if preflight_failures:
            version_step = {"label": "Godot version", "status": "FAIL", "returncode": "preflight-blocked", "command": "not run", "output": "Blocked because independent release preflight failed."}
            steps.append(version_step)
        else:
            version_step = run_step("Godot version", [args.godot, "--version"], ROOT, os.environ.copy(), timeout=20)
            steps.append(version_step)
        if version_step["status"] == "PASS":
            godot_version = version_step["output"].strip().splitlines()[-1] if version_step["output"].strip() else ""
        if version_step["status"] != "PASS" or not re.search(r"^4\.7\.2\.stable(?:\.official(?:\.[A-Za-z0-9_-]+)?)?$", godot_version):
            note = "Required Godot version 4.7.2 could not be verified; no runtime-tested archive was created."
        else:
            ignore = shutil.ignore_patterns(".git", ".godot", "__pycache__", ".venv", "venv", "node_modules", "*.zip", "*.pyc", "*.pyo", "*.tmp", "*.bak")
            with tempfile.TemporaryDirectory(prefix="AbyssLoop_RuntimeQA_") as tmp:
                sandbox = Path(tmp) / "project"
                shutil.copytree(ROOT, sandbox, ignore=ignore)
                project_file = sandbox / "project.godot"
                project_text = project_file.read_text(encoding="utf-8")
                project_text = re.sub(r'^config/name=.*$', 'config/name="Abyss Loop — Runtime QA Isolated"', project_text, count=1, flags=re.M)
                project_file.write_text(project_text, encoding="utf-8")
                env = os.environ.copy()
                env["ABYSS_LOOP_DISABLE_LEGACY_PROFILE_IMPORT"] = "1"
                env["ABYSS_LOOP_RUNTIME_QA"] = "1"
                steps.append(run_step("Editor/import preflight", [args.godot, "--headless", "--editor", "--path", str(sandbox), "--quit"], sandbox, env))
                if steps[-1]["status"] == "PASS":
                    steps.append(run_step("Clean main-scene launch", [args.godot, "--headless", "--path", str(sandbox), "--quit-after", "12"], sandbox, env))
                if steps and all(step["status"] == "PASS" for step in steps):
                    steps.append(run_step("Gameplay smoke", [args.godot, "--headless", "--path", str(sandbox), "--script", "res://tests/smoke_test.gd"], sandbox, env))
                if steps and all(step["status"] == "PASS" for step in steps):
                    steps.append(run_step("Save-system regression", [args.godot, "--headless", "--path", str(sandbox), "res://tests/save_system_regression_runner.tscn"], sandbox, env))
                if steps and all(step["status"] == "PASS" for step in steps):
                    steps.append(run_step("Expedition integration audit", [args.godot, "--headless", "--path", str(sandbox), "--script", "res://tests/expedition_integration_audit.gd"], sandbox, env))
                success = bool(steps) and all(step["status"] == "PASS" for step in steps) and len(steps) == 7
                if success:
                    note = "All seven runtime gates passed against a temporary copy with a distinct project name. The test harness disables legacy-profile import in this sandbox; save and expedition integration tests preserve/restore QA-owned save files. The player's real save directory was not used. Visual acceptance and a complete manual expedition remain separate requirements."

    text = report_text("PASS" if success else "FAIL", fingerprint, godot_version, build_version, steps, note)
    if not success:
        FAIL_REPORT.write_text(text, encoding="utf-8")
        print(text)
        print("FAILED: release gate did not pass; no runtime-tested ZIP was created.")
        return 1

    PASS_REPORT.write_text(text, encoding="utf-8")
    FAIL_REPORT.unlink(missing_ok=True)
    output = args.package_output.expanduser().resolve()
    package_step = run_step("Runtime-tested ZIP packaging", [sys.executable, str(ROOT / "tools" / "package_release.py"), "--output", str(output), "--require-runtime-gate"], ROOT, os.environ.copy(), timeout=120)
    if package_step["status"] != "PASS":
        PASS_REPORT.unlink(missing_ok=True)
        steps.append(package_step)
        fail_text = report_text("FAIL", fingerprint, godot_version, build_version, steps, "Runtime checks passed, but final package creation/validation failed. No runtime-tested ZIP should be used.")
        FAIL_REPORT.write_text(fail_text, encoding="utf-8")
        print(fail_text)
        return 5
    print(text)
    print(package_step["output"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

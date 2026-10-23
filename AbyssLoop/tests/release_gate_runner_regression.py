"""Guard release-gate order, isolation and fail-fast packaging."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
batch = ROOT / "RUN_RELEASE_GATE_WINDOWS.bat"
runner = ROOT / "tools" / "run_runtime_gate.py"
packager = ROOT / "tools" / "package_release.py"
assert batch.is_file() and runner.is_file() and packager.is_file(), "release gate components are missing"
batch_text = batch.read_text(encoding="utf-8")
runner_text = runner.read_text(encoding="utf-8")
packager_text = packager.read_text(encoding="utf-8")
required_batch = [
    "tools\\run_runtime_gate.py",
    "tools\\release_preflight.py",
    "AbyssLoop_Godot_Prototype_61_RUNTIME_TESTED.zip",
    "if errorlevel 1",
    "No runtime-tested ZIP should be distributed",
]
missing = [item for item in required_batch if item not in batch_text]
assert not missing, "Windows release gate misses guards: " + ", ".join(missing)
for needed in [
    '"Static/regression suite"', '"Godot version"', r'4\.7\.2',
    '"Editor/import preflight"', '"Clean main-scene launch"', '"Gameplay smoke"',
    '"Save-system regression"', '"ABYSS_LOOP_DISABLE_LEGACY_PROFILE_IMPORT"',
    'config/name="Abyss Loop — Runtime QA Isolated"', 'TemporaryDirectory',
    'RUNTIME_GATE_FAILURE_REPORT_RU.md', 'Source fingerprint:',
    '--require-runtime-gate',
    "from test_process_runner import run_command",
    "timed_out",
]:
    assert needed in runner_text, f"runtime gate misses safeguard: {needed}"
assert runner_text.index('"Static/regression suite"') < runner_text.index('"Godot version"') < runner_text.index('"Editor/import preflight"') < runner_text.index('"Clean main-scene launch"') < runner_text.index('"Gameplay smoke"') < runner_text.index('"Save-system regression"'), "runtime checks must run in deterministic fail-fast order"
assert "project_fingerprint(root)" in packager_text and "runtime gate report is stale" in packager_text, "packager must reject stale runtime evidence"
assert "Godot 4.7.2" in packager_text and "--require-runtime-gate" in packager_text, "runtime-tested ZIP must require configured Godot runtime"
assert "audit_archive" in packager_text and "audit_project" in packager_text, "release packaging must run independent source/archive preflight"
assert "build_versions != [read_project_version(root)]" in packager_text and "--release-candidate" in packager_text, "packager must separate RC and runtime-tested evidence"
print("RELEASE GATE RUNNER REGRESSION PASSED: static, exact engine, isolated import/launch/smoke/save, source fingerprint and fail-fast packaging")
print("This is source-level evidence; the release gate itself must be executed with Godot 4.7.2 on Windows.")

assert "tests/runtime_gate_process_cleanup_regression.py" in packager_text, "runtime gate process cleanup regression must ship with the package"
print("PASS: runtime gate timeout process-tree regression is included in the package")

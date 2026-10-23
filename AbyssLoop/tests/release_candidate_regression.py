"""Prototype 61 RC7 reproducibility, hygiene, and fail-closed runtime packaging regression."""
from __future__ import annotations
from hashlib import sha256
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "package_release.py"
project = (ROOT / "project.godot").read_text(encoding="utf-8")
manifest = (ROOT / "RELEASE_MANIFEST_RU.md").read_text(encoding="utf-8")
checklist = (ROOT / "RELEASE_CANDIDATE_CHECKLIST_Prototype61.md").read_text(encoding="utf-8")
release_bat = (ROOT / "RUN_RELEASE_GATE_WINDOWS.bat").read_text(encoding="utf-8")
tests_bat = (ROOT / "RUN_TESTS_WINDOWS.bat").read_text(encoding="utf-8")
packager = TOOL.read_text(encoding="utf-8")
runtime_gate = (ROOT / "tools" / "run_runtime_gate.py").read_text(encoding="utf-8")
integrity = (ROOT / "tools" / "release_integrity.py").read_text(encoding="utf-8")

checks = {
    "project uses stable identity and current 0.61.0 version": 'config/name="Abyss Loop"' in project and 'config/version="0.61.0"' in project,
    "manifest labels build RC7 and runtime remains unverified until gate report": "RELEASE CANDIDATE 7" in manifest and "runtime не подтверждён" in manifest,
    "release checklist distinguishes automated runtime gates from manual acceptance": "Автоматические проверки" in checklist and "Ручная приёмка" in checklist,
    "Windows release gate names the Prototype 61 runtime-tested output": "AbyssLoop_Godot_Prototype_61_RUNTIME_TESTED.zip" in release_bat,
    "Windows test launcher uses the matching output": "AbyssLoop_Godot_Prototype_61_RUNTIME_TESTED.zip" in tests_bat,
    "Windows scripts have no stale Prototype 34/36/55/56/57 runtime output": all(x not in release_bat + tests_bat for x in ["Prototype_34_RUNTIME_TESTED", "Prototype_36_RUNTIME_TESTED", "AbyssLoop_Godot_Prototype_55_RUNTIME_TESTED.zip", "AbyssLoop_Godot_Prototype_56_RUNTIME_TESTED.zip", "AbyssLoop_Godot_Prototype_57_RUNTIME_TESTED.zip"]),
    "Windows test launchers set conservative deterministic worker default": all("ABYSS_LOOP_TEST_WORKERS" in t for t in [release_bat, tests_bat]),
    "runtime report validation requires the current version and fingerprint": "build_versions != [read_project_version(root)]" in packager and "runtime gate report is stale" in packager,
    "all seven gate labels are explicitly required": all(x in packager for x in ["Static/regression suite", "Godot version", "Editor/import preflight", "Clean main-scene launch", "Gameplay smoke", "Save-system regression", "Expedition integration audit"]),
    "symlinks are rejected before package inclusion": "path.is_symlink()" in integrity and "symbolic links are not allowed" in integrity,
    "local credential and secret artifacts are filtered from release members": "credentials.json" in integrity and "name.startswith(\".env.\")" in integrity and ".pem" in integrity,
    "stage-60 atomic gameplay-cycle regression is included": "tests/gameplay_cycle_regression.py" in packager and "GAMEPLAY_CYCLE_RUNTIME_CHECKLIST_Prototype60.md" in packager,
    "stage-61 UI acceptance and modal regression ship in RC7": "UI_ACCEPTANCE_RUNTIME_CHECKLIST_Prototype61.md" in packager and "tests/ui_modal_responsiveness_regression.py" in packager and "ROADMAP_CONTINUATION_STAGES29-61_RU.md" in packager,
    "stage-62 QA runner cleanup and both process-tree regressions ship in RC7 hotfix": "tools/test_process_runner.py" in packager and "tests/static_suite_runner_regression.py" in packager and "tests/runtime_gate_process_cleanup_regression.py" in packager and "ROADMAP_CONTINUATION_STAGES29-62_RU.md" in packager,
    "RC7 packager includes artifact-hygiene, UI and runtime-report tests": "tests/release_artifact_hygiene_regression.py" in packager and "tests/runtime_gate_report_validation_regression.py" in packager,
    "packager requires RC7 project version and manifest status": "--release-candidate" in packager and 'read_project_version(ROOT) != "0.61.0"' in packager and "RELEASE CANDIDATE 7" in packager,
    "Stage68A resource graph audit and acceptance documents are mandatory package inputs": all(x in packager for x in ["ROADMAP_STATUS_STAGE68A_RU.md", "STAGE68A_BUILD_REPORT_RU.md", "FINAL_REGRESSION_RUNTIME_CHECKLIST_STAGE68A_RU.md", "tests/resource_graph_regression.py", "tests/reports/RESOURCE_GRAPH_AUDIT_STAGE68A_RU.md", "tests/reports/STAGE68A_PREFLIGHT_REPORT_RU.txt"]),
    "independent preflight enforces Stage68A evidence": all(x in (ROOT / "tools" / "release_preflight.py").read_text(encoding="utf-8") for x in ["ROADMAP_STATUS_STAGE68A_RU.md", "tests/resource_graph_regression.py", "tests/reports/RESOURCE_GRAPH_AUDIT_STAGE68A_RU.md"]),
    "Stage68B local balance capture tool, tests and guide are mandatory package inputs": all(x in packager for x in ["ROADMAP_STATUS_STAGE68B_RU.md", "STAGE68B_BUILD_REPORT_RU.md", "REAL_RUN_BALANCE_CAPTURE_GUIDE_STAGE68B_RU.md", "REAL_RUN_BALANCE_RUNTIME_CHECKLIST_STAGE68B_RU.md", "tools/real_run_balance.py", "tests/real_run_balance_capture_regression.py", "tests/reports/REAL_RUN_BALANCE_CAPTURE_AUDIT_STAGE68B_RU.md", "tests/reports/STAGE68B_PREFLIGHT_REPORT_RU.txt"]),
    "independent preflight enforces Stage68B evidence": all(x in (ROOT / "tools" / "release_preflight.py").read_text(encoding="utf-8") for x in ["ROADMAP_STATUS_STAGE68B_RU.md", "tools/real_run_balance.py", "tests/reports/REAL_RUN_BALANCE_CAPTURE_AUDIT_STAGE68B_RU.md"]),
    "RC7 package includes Stage64B automated engine capture with source labels": all(x in packager for x in ["tests/stage64b_engine_run_capture.gd", "tests/stage64b_engine_run_capture_runner.tscn", "tests/stage64b_engine_run_capture_regression.py", "tests/reports/STAGE64B_AUTOMATED_ENGINE_RUN_CAPTURE_GUIDE_RU.md"]),
    "independent preflight enforces Stage64B automated capture evidence": all(x in (ROOT / "tools" / "release_preflight.py").read_text(encoding="utf-8") for x in ["tests/stage64b_engine_run_capture.gd", "tests/stage64b_engine_run_capture_regression.py", "STAGE64B_AUTOMATED_ENGINE_RUN_CAPTURE_GUIDE_RU.md"]),
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
assert not failed, "RC7 checks failed: " + ", ".join(failed)

# Two release candidates from an identical tree must be byte reproducible.
with tempfile.TemporaryDirectory(prefix="abyssloop_rc61_repro_") as temp:
    temp_path = Path(temp)
    # Freeze one tree snapshot first; other parallel regression tests may
    # regenerate report files in the working tree while this test is running.
    snapshot = temp_path / "source_snapshot" / "AbyssLoop"
    ignore = shutil.ignore_patterns(".git", ".godot", "__pycache__", ".venv", "venv", "node_modules", "*.zip", "*.pyc", "*.pyo", "*.tmp", "*.bak")
    shutil.copytree(ROOT, snapshot, ignore=ignore)
    frozen_tool = snapshot / "tools" / "package_release.py"
    archives = [temp_path / "candidate_a.zip", temp_path / "candidate_b.zip"]
    for archive_path in archives:
        proc = subprocess.run([sys.executable, str(frozen_tool), "--release-candidate", "--output", str(archive_path)], cwd=snapshot, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=25)
        assert proc.returncode == 0, "RC7 package failed:\n" + proc.stdout
        assert archive_path.is_file(), "RC7 package output is missing"
    hashes = [sha256(p.read_bytes()).hexdigest() for p in archives]
    assert hashes[0] == hashes[1], f"RC7 archive is not byte-reproducible: {hashes}"
    with zipfile.ZipFile(archives[0]) as archive:
        assert archive.testzip() is None, "ZIP CRC error"
        names = set(archive.namelist())
        roots = {Path(n).parts[0] for n in names if Path(n).parts}
        assert roots == {"AbyssLoop"}, f"wrong archive root: {roots}"
        assert "AbyssLoop/RELEASE_CANDIDATE_CHECKLIST_Prototype61.md" in names and "AbyssLoop/UI_ACCEPTANCE_RUNTIME_CHECKLIST_Prototype61.md" in names
        assert "AbyssLoop/POST_RUN_DEBRIEF_RUNTIME_CHECKLIST_Prototype58.md" in names
        assert "AbyssLoop/ROADMAP_CONTINUATION_STAGES29-56_RU.md" in names
        assert "AbyssLoop/ROADMAP_CONTINUATION_STAGES29-57_RU.md" in names
        assert "AbyssLoop/ROADMAP_CONTINUATION_STAGES29-59_RU.md" in names
        assert "AbyssLoop/ROADMAP_CONTINUATION_STAGES29-60_RU.md" in names
        assert "AbyssLoop/ROADMAP_CONTINUATION_STAGES29-61_RU.md" in names
        assert "AbyssLoop/tests/ui_modal_responsiveness_regression.py" in names
        assert "AbyssLoop/tools/test_process_runner.py" in names
        assert "AbyssLoop/tests/static_suite_runner_regression.py" in names
        assert "AbyssLoop/tests/runtime_gate_process_cleanup_regression.py" in names
        assert "AbyssLoop/ROADMAP_CONTINUATION_STAGES29-62_RU.md" in names
        assert "AbyssLoop/GAMEPLAY_CYCLE_RUNTIME_CHECKLIST_Prototype60.md" in names
        assert "AbyssLoop/tests/gameplay_cycle_regression.py" in names
        assert "AbyssLoop/tests/run_debrief_regression.py" in names
        assert "AbyssLoop/tools/release_preflight.py" in names
        assert "AbyssLoop/tests/release_preflight_regression.py" in names
        assert "AbyssLoop/tests/release_artifact_hygiene_regression.py" in names
        assert "AbyssLoop/tests/runtime_gate_report_validation_regression.py" in names
        assert "AbyssLoop/ROADMAP_STATUS_STAGE68A_RU.md" in names
        assert "AbyssLoop/STAGE68A_BUILD_REPORT_RU.md" in names
        assert "AbyssLoop/FINAL_REGRESSION_RUNTIME_CHECKLIST_STAGE68A_RU.md" in names
        assert "AbyssLoop/tests/resource_graph_regression.py" in names
        assert "AbyssLoop/tests/reports/RESOURCE_GRAPH_AUDIT_STAGE68A_RU.md" in names
        assert "AbyssLoop/tests/reports/STAGE68A_PREFLIGHT_REPORT_RU.txt" in names
        assert "AbyssLoop/ROADMAP_STATUS_STAGE68B_RU.md" in names
        assert "AbyssLoop/STAGE68B_BUILD_REPORT_RU.md" in names
        assert "AbyssLoop/REAL_RUN_BALANCE_CAPTURE_GUIDE_STAGE68B_RU.md" in names
        assert "AbyssLoop/REAL_RUN_BALANCE_RUNTIME_CHECKLIST_STAGE68B_RU.md" in names
        assert "AbyssLoop/tools/real_run_balance.py" in names
        assert "AbyssLoop/tests/real_run_balance_capture_regression.py" in names
        assert "AbyssLoop/tests/reports/REAL_RUN_BALANCE_CAPTURE_AUDIT_STAGE68B_RU.md" in names
        assert "AbyssLoop/tests/reports/STAGE68B_PREFLIGHT_REPORT_RU.txt" in names
        assert "AbyssLoop/tests/reports/RUNTIME_GATE_REPORT_RU.md" not in names
        assert not any(any(part in {".godot", ".git", "__pycache__", "node_modules", "__MACOSX"} for part in Path(n).parts) for n in names)
        assert not any(Path(n).name.lower().startswith(".env") or Path(n).suffix.lower() in {".pyc", ".pyo", ".tmp", ".bak", ".zip", ".log", ".pem", ".key", ".p12", ".pfx", ".swp", ".swo"} for n in names)
        assert 'config/version="0.61.0"' in archive.read("AbyssLoop/project.godot").decode("utf-8")
    print(f"PASS: deterministic RC7 ZIP ({hashes[0]})")

# Ensure a clean tree cannot be promoted to runtime-tested without a current report.
with tempfile.TemporaryDirectory(prefix="abyssloop_rc61_gate_rail_") as temp:
    sandbox = Path(temp) / "AbyssLoop"
    ignore = shutil.ignore_patterns(".git", ".godot", "__pycache__", ".venv", "venv", "node_modules", "*.zip", "*.pyc", "*.pyo", "*.tmp", "*.bak")
    shutil.copytree(ROOT, sandbox, ignore=ignore)
    report = sandbox / "tests" / "reports" / "RUNTIME_GATE_REPORT_RU.md"
    report.unlink(missing_ok=True)
    out = Path(temp) / "must_not_exist_RUNTIME_TESTED.zip"
    proc = subprocess.run([sys.executable, str(sandbox / "tools" / "package_release.py"), "--require-runtime-gate", "--output", str(out)], cwd=sandbox, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
    assert proc.returncode != 0 and not out.exists(), "runtime-tested package must fail with missing runtime report"
    assert "runtime gate report is missing" in proc.stdout, proc.stdout
    print("PASS: runtime-tested packaging rejects a missing report")

print(f"RELEASE CANDIDATE RC7 REGRESSION PASSED: {len(checks)} source assertions, deterministic ZIP and fail-closed gate")
print("Source-level only; the actual Godot runtime gate still has to run on Windows.")

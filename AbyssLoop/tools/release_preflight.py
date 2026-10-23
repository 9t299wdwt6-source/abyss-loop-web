#!/usr/bin/env python3
"""Independent, fail-closed preflight for Abyss Loop release candidates.

This tool is intentionally source-level. It checks version/manifest consistency,
required handoff documents, completed static evidence (when requested), and
exact archive-to-source correspondence. It does not execute Godot or establish
runtime acceptance.
"""
from __future__ import annotations
import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import zipfile

from release_integrity import iter_project_files

DEFAULT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_VERSION = "0.61.0"
REQUIRED_FILES = (
    "ROADMAP_STATUS_STAGE68A_RU.md",
    "STAGE68A_BUILD_REPORT_RU.md",
    "FINAL_REGRESSION_RUNTIME_CHECKLIST_STAGE68A_RU.md",
    "tests/resource_graph_regression.py",
    "tests/reports/RESOURCE_GRAPH_AUDIT_STAGE68A_RU.md",
    "tests/reports/STAGE68A_PREFLIGHT_REPORT_RU.txt",
    "ROADMAP_STATUS_STAGE68B_RU.md",
    "STAGE68B_BUILD_REPORT_RU.md",
    "REAL_RUN_BALANCE_CAPTURE_GUIDE_STAGE68B_RU.md",
    "REAL_RUN_BALANCE_RUNTIME_CHECKLIST_STAGE68B_RU.md",
    "tools/real_run_balance.py",
    "tests/real_run_balance_capture_regression.py",
    "tests/reports/REAL_RUN_BALANCE_CAPTURE_AUDIT_STAGE68B_RU.md",
    "tests/reports/STAGE68B_PREFLIGHT_REPORT_RU.txt",
    "tests/stage64b_engine_run_capture.gd",
    "tests/stage64b_engine_run_capture_runner.tscn",
    "tests/stage64b_engine_run_capture_regression.py",
    "tests/reports/STAGE64B_AUTOMATED_ENGINE_RUN_CAPTURE_GUIDE_RU.md",
    "ROADMAP_STATUS_STAGE68C_RU.md",
    "STAGE68C_BUILD_REPORT_RU.md",
    "WEB_EXPORT_RUNTIME_CHECKLIST_STAGE68C_RU.md",
    "README_WEB_RU.md",
    "export_presets.cfg",
    ".github/workflows/abyssloop-web.yml",
    "tools/export_web.sh",
    "tools/web_export_preflight.py",
    "tools/web_browser_smoke_test.py",
    "tools/web_gameplay_browser_acceptance.py",
    "tests/web_gameplay_browser_acceptance_regression.py",
    "tools/serve_web_export.py",
    "tests/web_export_readiness_regression.py",
    "tests/reports/WEB_EXPORT_READINESS_AUDIT_STAGE68C_RU.md",
    "tests/reports/WEB_EXPORT_PREFLIGHT_STAGE68C_RU.txt",
    "ROADMAP_STATUS_STAGE67_RU.md",
    "STAGE67_BUILD_REPORT_RU.md",
    "FIRST_HOUR_GUIDANCE_RUNTIME_CHECKLIST_STAGE67_RU.md",
    "tests/first_hour_guidance_regression.py",
    "tests/reports/FIRST_HOUR_GUIDANCE_AUDIT_STAGE67_RU.md",
    "tests/reports/LOCALIZATION_AUDIT_STAGE67_RU.md",
    "tests/reports/STAGE67_PREFLIGHT_REPORT_RU.txt",
    "ROADMAP_STATUS_STAGE66B_RU.md",
    "STAGE66B_BUILD_REPORT_RU.md",
    "CARD_PLACEMENT_AUDIT_STAGE66B_RU.md",
    "CARD_PLACEMENT_RUNTIME_ACCEPTANCE_STAGE66B_RU.md",
    "tests/stage66b_readability_localization_regression.py",
    "tests/reports/CARD_PLACEMENT_AUDIT_STAGE66B_RU.md",
    "tests/reports/LOCALIZATION_AUDIT_STAGE66B_RU.md",
    "tests/reports/STAGE66B_PREFLIGHT_REPORT_RU.txt",
    "tests/reports/STATIC_TEST_REPORT.txt",
    "tests/tutorial_regression.py",
    "project.godot",
    "scenes/main.tscn",
    "scripts/core/content_registry.gd",
    "scripts/core/game_state.gd",
    "scripts/core/save_system.gd",
    "scripts/systems/expedition_manager.gd",
    "scripts/systems/route_system.gd",
    "scripts/ui/ui_controller.gd",
    "scripts/ui/item_text_presenter.gd",
    "tests/item_text_presenter_regression.py",
    "ROADMAP_STATUS_STAGE65D_RU.md",
    "STAGE65D_BUILD_REPORT_RU.md",
    "tests/smoke_test.gd",
    "tests/save_system_regression.gd",
    "tests/save_integrity_regression.py",
    "tests/expedition_integration_audit.gd",
    "tools/package_release.py",
    "tools/run_runtime_gate.py",
    "tools/release_integrity.py",
    "tools/release_preflight.py",
    "tests/release_preflight_regression.py",
    "tests/run_debrief_regression.py",
    "tools/test_process_runner.py",
    "tests/static_suite_runner_regression.py",
    "tests/runtime_gate_process_cleanup_regression.py",
    "ROADMAP_CONTINUATION_STAGES29-62_RU.md",
    "RELEASE_MANIFEST_RU.md",
    "README_RU.md",
    "BUILD_REPORT_RU.md",
    "ROADMAP_STATUS_RU.md",
    "RELEASE_CANDIDATE_CHECKLIST_Prototype60.md",
    "RELEASE_CANDIDATE_CHECKLIST_Prototype61.md",
    "UI_ACCEPTANCE_RUNTIME_CHECKLIST_Prototype61.md",
    "tests/ui_modal_responsiveness_regression.py",
    "SAVE_INTEGRITY_RUNTIME_CHECKLIST_Prototype59.md",
    "POST_RUN_DEBRIEF_RUNTIME_CHECKLIST_Prototype58.md",
    "ROADMAP_CONTINUATION_STAGES29-57_RU.md",
    "ROADMAP_CONTINUATION_STAGES29-59_RU.md",
    "ROADMAP_CONTINUATION_STAGES29-60_RU.md",
    "ROADMAP_CONTINUATION_STAGES29-61_RU.md",
    "GAMEPLAY_CYCLE_RUNTIME_CHECKLIST_Prototype60.md",
    "tests/gameplay_cycle_regression.py",
    "RUN_RELEASE_GATE_WINDOWS.bat",
    "RUN_TESTS_WINDOWS.bat",
)

@dataclass(frozen=True)
class Check:
    name: str
    passed: bool
    detail: str


def read_version(root: Path) -> str:
    project = root / "project.godot"
    if not project.is_file():
        return ""
    match = re.search(r'^config/version="([^\"]+)"$', project.read_text(encoding="utf-8"), re.M)
    return match.group(1) if match else ""


def audit_project(root: Path, expected_version: str = DEFAULT_VERSION, *, require_static_report: bool = False) -> list[Check]:
    root = root.resolve()
    checks: list[Check] = []
    existing = [name for name in REQUIRED_FILES if (root / name).is_file()]
    missing = [name for name in REQUIRED_FILES if not (root / name).is_file()]
    checks.append(Check("required project and release files", not missing, "missing: " + ", ".join(missing) if missing else f"all {len(REQUIRED_FILES)} required files exist"))

    project = (root / "project.godot").read_text(encoding="utf-8") if (root / "project.godot").is_file() else ""
    version = read_version(root)
    stable_name_present = 'config/name="Abyss Loop"' in project
    identity_ok = stable_name_present and version == expected_version
    checks.append(Check("stable app identity and exact version", identity_ok, f"name={'Abyss Loop' if stable_name_present else 'unexpected'}; version={version or 'missing'}; expected={expected_version}"))

    docs = {
        "README_RU.md": (f"Prototype {expected_version.split('.')[1]}.0 RC7", expected_version),
        "BUILD_REPORT_RU.md": (f"Prototype {expected_version.split('.')[1]}.0 RC7", expected_version),
        "RELEASE_MANIFEST_RU.md": ("RELEASE CANDIDATE 7", expected_version),
        "ROADMAP_STATUS_RU.md": (f"Prototype {expected_version.split('.')[1]}.0 RC7", expected_version),
        "RELEASE_CANDIDATE_CHECKLIST_Prototype61.md": (expected_version, "Ручная приёмка"),
        "UI_ACCEPTANCE_RUNTIME_CHECKLIST_Prototype61.md": ("Godot 4.7.2 stable", "высокий контраст"),
        "POST_RUN_DEBRIEF_RUNTIME_CHECKLIST_Prototype58.md": ("Сценарии результата", "не изменяет ресурсы"),
        "ROADMAP_CONTINUATION_STAGES29-61_RU.md": ("Этап 61", expected_version),
        "ROADMAP_CONTINUATION_STAGES29-62_RU.md": ("Этап 62", "runtime не подтверждён"),
        "ROADMAP_STATUS_STAGE68A_RU.md": ("Stage68A", "79/79"),
        "STAGE68A_BUILD_REPORT_RU.md": ("79/79", "runtime не подтверждён"),
        "FINAL_REGRESSION_RUNTIME_CHECKLIST_STAGE68A_RU.md": ("Godot 4.7.2", "Runtime"),
        "tests/reports/RESOURCE_GRAPH_AUDIT_STAGE68A_RU.md": ("53", "ExtResource"),
        "ROADMAP_STATUS_STAGE68B_RU.md": ("Stage68B", "Stage64B"),
        "STAGE68B_BUILD_REPORT_RU.md": ("17/17 PASS", "Не runtime-tested"),
        "REAL_RUN_BALANCE_CAPTURE_GUIDE_STAGE68B_RU.md": ("--input", "--output"),
        "REAL_RUN_BALANCE_RUNTIME_CHECKLIST_STAGE68B_RU.md": ("Godot", "legacy_partial"),
        "tests/real_run_balance_capture_regression.py": ("synthetic fixtures", "balance verdict"),
        "tools/real_run_balance.py": ("never edits a save", "Баланс не оценён автоматически"),
        "tests/reports/REAL_RUN_BALANCE_CAPTURE_AUDIT_STAGE68B_RU.md": ("17/17 PASS", "Реальных профилей"),
        "tests/reports/STAGE68B_PREFLIGHT_REPORT_RU.txt": ("Stage68B", "Runtime: NOT RUN"),
        "tests/stage64b_engine_run_capture_regression.py": ("STAGE64B ENGINE CAPTURE REGRESSION PASSED", "never forces player/enemy health"),
        "tests/reports/STAGE64B_AUTOMATED_ENGINE_RUN_CAPTURE_GUIDE_RU.md": ("automated_engine_run", "not human playtest"),
        "ROADMAP_STATUS_STAGE68C_RU.md": ("Stage68C", "Web"),
        "STAGE68C_BUILD_REPORT_RU.md": ("Web export", "runtime не подтверждён"),
        "WEB_EXPORT_RUNTIME_CHECKLIST_STAGE68C_RU.md": ("Godot 4.7.2", "WebGL 2.0"),
        "README_WEB_RU.md": ("Godot 4.7.2", "index.html"),
        "export_presets.cfg": ('name="Web"', 'platform="Web"'),
        ".github/workflows/abyssloop-web.yml": ("web_browser_smoke_test.py", "deploy-pages"),
        "tools/export_web.sh": ("SHA-256", "--export-release"),
        "tools/web_export_preflight.py": ("source_checks", "build_checks"),
        "tools/web_browser_smoke_test.py": ("WebGL 2", "index.wasm"),
        "tools/web_gameplay_browser_acceptance.py": ("sync_playwright", "page.reload"),
        "tests/web_gameplay_browser_acceptance_regression.py": ("WEB GAMEPLAY RELOAD REGRESSION PASSED", "saved expedition resumes after reload"),
        "tools/serve_web_export.py": ("application/wasm", "127.0.0.1"),
        "tests/web_export_readiness_regression.py": ("WEB EXPORT READINESS REGRESSION PASSED", "synthetic export files"),
        "tests/reports/WEB_EXPORT_READINESS_AUDIT_STAGE68C_RU.md": ("READY WITH WARNINGS", "Godot runtime not executed"),
        "tests/reports/WEB_EXPORT_PREFLIGHT_STAGE68C_RU.txt": ("7/7", "WebGL 2.0"),
    }
    doc_errors: list[str] = []
    for name, tokens in docs.items():
        path = root / name
        if not path.is_file():
            doc_errors.append(f"{name}: missing")
            continue
        text = path.read_text(encoding="utf-8")
        for token in tokens:
            if token not in text:
                doc_errors.append(f"{name}: missing {token!r}")
    manifest_path = root / "RELEASE_MANIFEST_RU.md"
    if manifest_path.is_file():
        manifest_text = manifest_path.read_text(encoding="utf-8")
        if "runtime не подтверждён" not in manifest_text:
            doc_errors.append("RELEASE_MANIFEST_RU.md: must state runtime is not verified")
    checks.append(Check("README/manifest/checklist/roadmap version consistency", not doc_errors, "; ".join(doc_errors) if doc_errors else "version, RC7 status, and release docs agree"))

    packager_path = root / "tools" / "package_release.py"
    packager = packager_path.read_text(encoding="utf-8") if packager_path.is_file() else ""
    packager_ok = f'read_project_version(ROOT) != "{expected_version}"' in packager and "release_preflight" in packager and "audit_archive" in packager
    checks.append(Check("packager enforces current version and preflight/archive audits", packager_ok, "version lock or independent preflight/archive audit hook missing" if not packager_ok else "current version lock and both audit hooks are wired"))

    expected_zip = f"AbyssLoop_Godot_Prototype_{expected_version.split('.')[1]}_RUNTIME_TESTED.zip"
    bat_errors: list[str] = []
    for name in ("RUN_RELEASE_GATE_WINDOWS.bat", "RUN_TESTS_WINDOWS.bat"):
        path = root / name
        text = path.read_text(encoding="utf-8") if path.is_file() else ""
        if expected_zip not in text:
            bat_errors.append(f"{name}: expected {expected_zip}")
        if "tools\\release_preflight.py" not in text:
            bat_errors.append(f"{name}: preflight not called")
    checks.append(Check("Windows launchers reference matching preflight and output", not bat_errors, "; ".join(bat_errors) if bat_errors else "both launchers preflight and name the matching artifact"))

    try:
        members = iter_project_files(root, include_runtime_report=False)
        checks.append(Check("source tree is safe to package", True, f"{len(members)} regular project files; symlinks rejected; local artifacts filtered"))
    except (OSError, ValueError) as exc:
        checks.append(Check("source tree is safe to package", False, str(exc)))

    if require_static_report:
        report_path = root / "tests" / "reports" / "STATIC_TEST_REPORT.txt"
        report = report_path.read_text(encoding="utf-8") if report_path.is_file() else ""
        summary = re.search(r"Checks discovered: (\d+); checks completed: (\d+); passed: (\d+); failed/timed out: (\d+)", report)
        valid_summary = bool(summary and int(summary.group(1)) > 0 and summary.groups()[0] == summary.groups()[1] == summary.groups()[2] and int(summary.group(4)) == 0)
        checks.append(Check("latest static/regression report is complete and all-pass", valid_summary, summary.group(0) if summary else "missing or malformed report summary"))
    return checks


def audit_archive(root: Path, archive_path: Path, expected_version: str = DEFAULT_VERSION, *, include_runtime_report: bool = False) -> list[Check]:
    root = root.resolve()
    archive_path = archive_path.resolve()
    checks: list[Check] = []
    try:
        expected_files = iter_project_files(root, include_runtime_report=include_runtime_report)
        expected = {"AbyssLoop/" + p.relative_to(root).as_posix(): p for p in expected_files}
        with zipfile.ZipFile(archive_path, "r") as archive:
            raw_names = archive.namelist()
            names = set(raw_names)
            roots = {Path(name).parts[0] for name in names if Path(name).parts}
            bad_member = archive.testzip()
            checks.append(Check("ZIP opens and CRC is valid", bad_member is None, f"bad member: {bad_member}" if bad_member else f"{len(raw_names)} archive members; CRC PASS"))
            checks.append(Check("archive has one AbyssLoop root", roots == {"AbyssLoop"} and all(name.startswith("AbyssLoop/") for name in raw_names), f"roots: {sorted(roots)}"))
            checks.append(Check("archive contains no duplicate member names", len(raw_names) == len(names), f"{len(raw_names) - len(names)} duplicate names" if len(raw_names) != len(names) else "no duplicates"))
            actual_files = {name for name in names if not name.endswith("/")}
            expected_names = set(expected)
            missing = sorted(expected_names - actual_files)
            extra = sorted(actual_files - expected_names)
            checks.append(Check("archive members exactly match filtered source tree", not missing and not extra, f"missing={missing[:4]}; extra={extra[:4]}" if missing or extra else f"all {len(expected_names)} expected files are present with no extras"))
            byte_mismatch = []
            for name in sorted(expected_names & actual_files):
                if archive.read(name) != expected[name].read_bytes():
                    byte_mismatch.append(name)
            checks.append(Check("packaged file bytes match source", not byte_mismatch, "mismatch: " + ", ".join(byte_mismatch[:5]) if byte_mismatch else "all packaged files match current source bytes"))
            project_text = archive.read("AbyssLoop/project.godot").decode("utf-8") if "AbyssLoop/project.godot" in names else ""
            project_ok = f'config/name="Abyss Loop"' in project_text and f'config/version="{expected_version}"' in project_text
            checks.append(Check("archive contains stable identity and expected version", project_ok, f"expected {expected_version} and stable app identity"))
            forbidden_suffixes = {".pyc", ".pyo", ".tmp", ".bak", ".zip", ".log", ".swp", ".swo", ".orig", ".pem", ".key", ".p12", ".pfx", ".crash"}
            forbidden_names = {".env", "credentials.json", "secrets.json", "token.json", "service-account.json", "id_rsa", "id_ed25519", "id_ecdsa"}
            forbidden = [name for name in actual_files if Path(name).name.lower() in forbidden_names or Path(name).name.lower().startswith(".env.") or Path(name).suffix.lower() in forbidden_suffixes or any(part in {".git", ".godot", "__pycache__", ".venv", "venv", "node_modules", "__MACOSX"} for part in Path(name).parts)]
            checks.append(Check("archive contains no banned artifacts", not forbidden, "forbidden: " + ", ".join(forbidden[:5]) if forbidden else "no banned files or cache directories"))
    except (OSError, ValueError, zipfile.BadZipFile, KeyError) as exc:
        checks.append(Check("archive can be independently audited", False, f"{type(exc).__name__}: {exc}"))
    return checks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT, help="Project root folder")
    parser.add_argument("--expected-version", default=DEFAULT_VERSION, help="Required config/version value")
    parser.add_argument("--require-static-report", action="store_true", help="Require the latest static suite report to be complete and all-pass")
    parser.add_argument("--archive", type=Path, help="Optionally compare an archive byte-for-byte against the source tree")
    parser.add_argument("--include-runtime-report", action="store_true", help="Expect the current runtime report inside the archive")
    args = parser.parse_args()

    checks = audit_project(args.root, args.expected_version, require_static_report=args.require_static_report)
    if args.archive:
        checks.extend(audit_archive(args.root, args.archive, args.expected_version, include_runtime_report=args.include_runtime_report))
    for check in checks:
        print(f"{'PASS' if check.passed else 'FAIL'}: {check.name} — {check.detail}")
    failed = [check for check in checks if not check.passed]
    print(f"\nRELEASE PREFLIGHT: {len(checks) - len(failed)}/{len(checks)} PASS; {len(failed)} FAIL")
    print("Scope: source/docs/artifact consistency only; no Godot engine was executed by this tool.")
    return 1 if failed else 0

if __name__ == "__main__":
    raise SystemExit(main())

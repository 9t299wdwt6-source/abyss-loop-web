#!/usr/bin/env python3
"""Create and verify a reproducible Abyss Loop ZIP; optionally require a matching runtime-gate report."""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import zipfile

from release_integrity import file_sha256, iter_project_files, project_fingerprint
from release_preflight import DEFAULT_VERSION, audit_archive, audit_project

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = (
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
    "ROADMAP_STATUS_STAGE66C_RU.md",
    "STAGE66C_BUILD_REPORT_RU.md",
    "ENEMY_ROLE_AND_STATUS_RUNTIME_CHECKLIST_STAGE66C_RU.md",
    "tests/stage66c_enemy_status_readability_regression.py",
    "tests/reports/ENEMY_ROLE_AND_STATUS_AUDIT_STAGE66C_RU.md",
    "tests/reports/LOCALIZATION_AUDIT_STAGE66C_RU.md",
    "tests/reports/STAGE66C_PREFLIGHT_REPORT_RU.txt",
    "ROADMAP_STATUS_STAGE66B_RU.md",
    "STAGE66B_BUILD_REPORT_RU.md",
    "CARD_PLACEMENT_AUDIT_STAGE66B_RU.md",
    "CARD_PLACEMENT_RUNTIME_ACCEPTANCE_STAGE66B_RU.md",
    "tests/stage66b_readability_localization_regression.py",
    "tests/reports/CARD_PLACEMENT_AUDIT_STAGE66B_RU.md",
    "tests/reports/LOCALIZATION_AUDIT_STAGE66B_RU.md",
    "tests/reports/STAGE66B_PREFLIGHT_REPORT_RU.txt",
    "tests/tutorial_regression.py",
    "ROADMAP_STATUS_STAGE65E_RU.md",
    "STAGE65E_BUILD_REPORT_RU.md",
    "tests/reports/CROSS_SYSTEM_INTERACTION_AUDIT_STAGE65E_RU.md",
    "ROADMAP_STATUS_STAGE65D_RU.md",
    "STAGE65D_BUILD_REPORT_RU.md",
    "ROADMAP_STATUS_STAGE65C_RU.md",
    "STAGE65C_BUILD_REPORT_RU.md",
    "BALANCE_SCREENING_STAGE64A_RU.md",
    "tests/reports/REAL_RUN_BALANCE_CAPTURE_TEMPLATE_STAGE64B_RU.md",
    "tests/reports/LOCALIZATION_TEXT_AUDIT_RU.md",
    "project.godot",
    "scenes/main.tscn",
    "scripts/core/content_registry.gd",
    "scripts/core/game_state.gd",
    "scripts/core/save_system.gd",
    "scripts/systems/expedition_manager.gd",
    "scripts/systems/route_system.gd",
    "scripts/ui/ui_controller.gd",
    "scripts/ui/developer_diagnostics_report.gd",
    "scripts/ui/status_effect_presenter.gd",
    "scripts/ui/item_text_presenter.gd",
    "scripts/ui/run_debrief_presenter.gd",
    "tests/item_text_presenter_regression.py",
    "tests/cross_system_interaction_regression.py",
    "scripts/ui/route_view.gd",
    "tests/smoke_test.gd",
    "tests/status_effect_presenter_regression.py",
    "tests/save_system_regression.gd",
    "tests/save_system_regression_runner.tscn",
    "tests/save_integrity_regression.py",
    "tests/expedition_integration_audit.gd",
    "tests/expedition_integration_audit_regression.py",
    "tests/run_static_suite.py",
    "tools/test_process_runner.py",
    "tests/static_suite_runner_regression.py",
    "tests/runtime_gate_process_cleanup_regression.py",
    "ROADMAP_CONTINUATION_STAGES29-62_RU.md",
    "tests/run_debrief_regression.py",
    "tests/content_v1_matrix_regression.py",
    "DEVELOPER_TOOLS_RUNTIME_CHECKLIST_Prototype50.md",
    "KEYBOARD_UX_RUNTIME_CHECKLIST_Prototype51.md",
    "ACCESSIBILITY_SETTINGS_RUNTIME_CHECKLIST_Prototype52.md",
    "LOCALIZATION_UI_RUNTIME_CHECKLIST_Prototype53.md",
    "INTEGRATION_AUDIT_RUNTIME_CHECKLIST_Prototype54.md",
    "RELEASE_CANDIDATE_CHECKLIST_Prototype55.md",
    "RELEASE_CANDIDATE_CHECKLIST_Prototype56.md",
    "RELEASE_CANDIDATE_CHECKLIST_Prototype60.md",
    "RELEASE_CANDIDATE_CHECKLIST_Prototype61.md",
    "UI_ACCEPTANCE_RUNTIME_CHECKLIST_Prototype61.md",
    "tests/ui_modal_responsiveness_regression.py",
    "SAVE_INTEGRITY_RUNTIME_CHECKLIST_Prototype59.md",
    "GAMEPLAY_CYCLE_RUNTIME_CHECKLIST_Prototype60.md",
    "POST_RUN_DEBRIEF_RUNTIME_CHECKLIST_Prototype58.md",
    "ROADMAP_CONTINUATION_STAGES29-56_RU.md",
    "ROADMAP_CONTINUATION_STAGES29-57_RU.md",
    "ROADMAP_CONTINUATION_STAGES29-59_RU.md",
    "ROADMAP_CONTINUATION_STAGES29-60_RU.md",
    "ROADMAP_CONTINUATION_STAGES29-61_RU.md",
    "tests/gameplay_cycle_regression.py",
    "tests/dual_placement_regression.py",
    "tests/release_artifact_hygiene_regression.py",
    "tests/runtime_gate_report_validation_regression.py",
    "tests/release_candidate_regression.py",
    "tests/reports/RELEASE_CANDIDATE_PREFLIGHT_RU.md",
    "localization/strings_ru.json",
    "scripts/core/localization.gd",
    "tests/localization_catalog_regression.py",
    "tests/ui_screenshot_findings_regression.py",
    "tools/localization_audit.py",
    "tests/reports/LOCALIZATION_TEXT_AUDIT_RU.md",
    "tests/accessibility_settings_regression.py",
    "tests/developer_tools_regression.py",
    "tests/keyboard_focus_navigation_regression.py",
    "tests/fixtures/content_v1_stable_ids.json",
    "tests/reports/CONTENT_V1_READINESS_MATRIX_RU.md",
    "tests/reports/DEVELOPER_DIAGNOSTICS_RU.md",
    "tools/content_v1_audit.py",
    "tools/developer_diagnostics.py",
    "tools/run_runtime_gate.py",
    "tools/release_integrity.py",
    "RELEASE_MANIFEST_RU.md",
    "assets/background/abyss_pixel_backdrop.png",
)
RUNTIME_REPORT = ROOT / "tests" / "reports" / "RUNTIME_GATE_REPORT_RU.md"


def read_project_version(root: Path) -> str:
    project_text = (root / "project.godot").read_text(encoding="utf-8")
    match = re.search(r'^config/version="([^"]+)"$', project_text, re.M)
    return match.group(1) if match else ""


def validate_runtime_report(root: Path) -> tuple[bool, str]:
    report = root / "tests" / "reports" / "RUNTIME_GATE_REPORT_RU.md"
    if not report.is_file():
        return False, "runtime gate report is missing"
    text = report.read_text(encoding="utf-8")
    result_values = re.findall(r"^Result:\s*(.*?)\s*$", text, re.M)
    if result_values != ["PASS"]:
        return False, "runtime gate report does not declare Result: PASS exactly once"
    build_versions = re.findall(r"^Build version:\s*(.*?)\s*$", text, re.M)
    if build_versions != [read_project_version(root)]:
        return False, "runtime report is for a different build version"
    fingerprints = re.findall(r"^Source fingerprint:\s*([0-9a-f]{64})\s*$", text, re.M)
    if len(fingerprints) != 1:
        return False, "runtime gate report has no unique source fingerprint"
    current = project_fingerprint(root)
    if fingerprints[0] != current:
        return False, "runtime gate report is stale: project sources changed after runtime tests"
    godot_versions = re.findall(r"^Godot version:\s*(.*?)\s*$", text, re.M)
    if len(godot_versions) != 1 or not re.fullmatch(r"4\.7\.2\.stable(?:\.official(?:\.[A-Za-z0-9_-]+)?)?", godot_versions[0]):
        return False, "runtime gate report was not generated by Godot 4.7.2"
    required_labels = [
        "Static/regression suite",
        "Godot version",
        "Editor/import preflight",
        "Clean main-scene launch",
        "Gameplay smoke",
        "Save-system regression",
        "Expedition integration audit",
    ]
    gate_rows = re.findall(r"^- ([^\n:]+): ([A-Z]+)\s*$", text, re.M)
    gate_statuses: dict[str, list[str]] = {}
    for label, status in gate_rows:
        gate_statuses.setdefault(label, []).append(status)
    missing = [label for label in required_labels if label not in gate_statuses]
    if missing:
        return False, "runtime gate report is incomplete: " + ", ".join(missing)
    duplicate = [label for label, statuses in gate_statuses.items() if len(statuses) != 1]
    if duplicate:
        return False, "runtime gate report contains duplicate gate rows: " + ", ".join(duplicate)
    failed = [label for label, statuses in gate_statuses.items() if statuses[0] != "PASS"]
    if failed:
        return False, "runtime gate report contains non-PASS gates: " + ", ".join(failed)
    unexpected = [label for label in gate_statuses if label not in required_labels]
    if unexpected:
        return False, "runtime gate report contains unexpected gate rows: " + ", ".join(unexpected)
    return True, "all seven runtime gates and source fingerprint match current build"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="Target ZIP path; must be outside project root")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--release-candidate", action="store_true", help="Create a pre-runtime release candidate; label remains provisional")
    mode.add_argument("--require-runtime-gate", action="store_true", help="Refuse packaging unless matching Godot 4.7.2 runtime gates passed")
    args = parser.parse_args()

    missing = [name for name in REQUIRED if not (ROOT / name).is_file()]
    if missing:
        parser.error("required project files are missing: " + ", ".join(missing))
    output = args.output.expanduser().resolve()
    root_resolved = ROOT.resolve()
    if output == root_resolved or root_resolved in output.parents:
        parser.error("output ZIP must be outside the project directory to avoid self-inclusion")
    if output.suffix.lower() != ".zip":
        parser.error("output filename must end with .zip")

    if args.release_candidate:
        if read_project_version(ROOT) != "0.61.0":
            parser.error("release-candidate packaging requires project version 0.61.0")
        manifest_text = (ROOT / "RELEASE_MANIFEST_RU.md").read_text(encoding="utf-8")
        if "RELEASE CANDIDATE 7" not in manifest_text or "runtime не подтверждён" not in manifest_text:
            parser.error("release candidate manifest must identify RC7 and state that runtime is not verified")

    if args.require_runtime_gate:
        valid, message = validate_runtime_report(ROOT)
        if not valid:
            parser.error("release candidate rejected: " + message)
        print("Runtime gate: PASS — " + message)

    if args.release_candidate or args.require_runtime_gate:
        preflight_checks = audit_project(ROOT, DEFAULT_VERSION, require_static_report=bool(args.require_runtime_gate))
        preflight_failures = [check for check in preflight_checks if not check.passed]
        if preflight_failures:
            summary = "; ".join(f"{check.name}: {check.detail}" for check in preflight_failures)
            parser.error("independent release preflight failed: " + summary)
        print(f"Independent release preflight: PASS ({len(preflight_checks)} checks)")

    members = iter_project_files(ROOT, include_runtime_report=bool(args.require_runtime_gate))
    member_names = {"AbyssLoop/" + path.relative_to(ROOT).as_posix() for path in members}
    missing_inside = ["AbyssLoop/" + name for name in REQUIRED if "AbyssLoop/" + name not in member_names]
    if missing_inside:
        parser.error("required project files would be excluded from the ZIP: " + ", ".join(missing_inside))
    if args.release_candidate and "AbyssLoop/tests/reports/RUNTIME_GATE_REPORT_RU.md" in member_names:
        parser.error("pre-runtime release candidate must not include a runtime PASS report")
    if args.require_runtime_gate and "AbyssLoop/tests/reports/RUNTIME_GATE_REPORT_RU.md" not in member_names:
        parser.error("runtime-tested package must include AbyssLoop/tests/reports/RUNTIME_GATE_REPORT_RU.md")

    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        archive.comment = b"Abyss Loop reproducible package"
        for path in members:
            arcname = "AbyssLoop/" + path.relative_to(ROOT).as_posix()
            info = zipfile.ZipInfo(arcname, date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = (0o100644 & 0xFFFF) << 16
            info.extra = b""
            info.comment = b""
            archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    with zipfile.ZipFile(output, "r") as archive:
        bad_member = archive.testzip()
        names = set(archive.namelist())
        missing_inside = ["AbyssLoop/" + name for name in REQUIRED if "AbyssLoop/" + name not in names]
        private_names = {".env", "credentials.json", "secrets.json", "token.json", "service-account.json", "id_rsa", "id_ed25519", "id_ecdsa"}
        private_suffixes = {".pyc", ".pyo", ".tmp", ".bak", ".zip", ".log", ".swp", ".swo", ".orig", ".pem", ".key", ".p12", ".pfx", ".crash"}
        forbidden = [name for name in names if any(part in {".git", ".godot", "__pycache__", ".venv", "venv", "node_modules", "__MACOSX"} for part in Path(name).parts) or Path(name).name.lower() in private_names or Path(name).name.lower().startswith(".env.") or Path(name).name.lower().endswith("~") or Path(name).suffix.lower() in private_suffixes]
        project_text = archive.read("AbyssLoop/project.godot").decode("utf-8")
        top_level = {Path(name).parts[0] for name in names if Path(name).parts}
        folder_ok = top_level == {"AbyssLoop"} and all(name.startswith("AbyssLoop/") for name in names)
        version_ok = 'config/name="Abyss Loop"' in project_text and 'config/version="0.61.0"' in project_text
        if bad_member or missing_inside or forbidden or not version_ok or not folder_ok:
            output.unlink(missing_ok=True)
            raise RuntimeError(f"ZIP integrity failure: bad_member={bad_member}; missing={missing_inside}; forbidden={forbidden[:5]}; version_ok={version_ok}; folder_ok={folder_ok}")
    if args.release_candidate or args.require_runtime_gate:
        archive_checks = audit_archive(ROOT, output, DEFAULT_VERSION, include_runtime_report=bool(args.require_runtime_gate))
        archive_failures = [check for check in archive_checks if not check.passed]
        if archive_failures:
            output.unlink(missing_ok=True)
            summary = "; ".join(f"{check.name}: {check.detail}" for check in archive_failures)
            raise RuntimeError("independent ZIP audit failed: " + summary)
        print(f"Independent ZIP audit: PASS ({len(archive_checks)} checks)")
    print(f"Created: {output}")
    print(f"Files: {len(members)}")
    print(f"Size: {output.stat().st_size} bytes")
    print(f"SHA-256: {file_sha256(output)}")
    print("ZIP integrity: PASS")
    if args.require_runtime_gate:
        print("Runtime gates: PASS — matching Godot 4.7.2 fingerprint")
    elif args.release_candidate:
        print("Package status: RELEASE CANDIDATE — RUNTIME NOT VERIFIED")
    else:
        print("Runtime gates: NOT ASSERTED (generic development package)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

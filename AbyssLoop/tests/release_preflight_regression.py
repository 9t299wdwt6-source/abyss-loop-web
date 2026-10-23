"""Tests the independent RC preflight and source-to-ZIP audit contract."""
from __future__ import annotations
from pathlib import Path
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from release_preflight import REQUIRED_FILES, audit_archive, audit_project  # noqa: E402
from release_integrity import iter_project_files  # noqa: E402

VERSION = "0.61.0"
STAGE68A_REQUIRED = {
    "ROADMAP_STATUS_STAGE68A_RU.md",
    "STAGE68A_BUILD_REPORT_RU.md",
    "FINAL_REGRESSION_RUNTIME_CHECKLIST_STAGE68A_RU.md",
    "tests/resource_graph_regression.py",
    "tests/reports/RESOURCE_GRAPH_AUDIT_STAGE68A_RU.md",
    "tests/reports/STAGE68A_PREFLIGHT_REPORT_RU.txt",
}
assert STAGE68A_REQUIRED.issubset(set(REQUIRED_FILES)), "Stage68A static final-regression evidence must be mandatory in independent preflight"
STAGE68B_REQUIRED = {
    "ROADMAP_STATUS_STAGE68B_RU.md", "STAGE68B_BUILD_REPORT_RU.md",
    "REAL_RUN_BALANCE_CAPTURE_GUIDE_STAGE68B_RU.md", "REAL_RUN_BALANCE_RUNTIME_CHECKLIST_STAGE68B_RU.md",
    "tools/real_run_balance.py", "tests/real_run_balance_capture_regression.py",
    "tests/reports/REAL_RUN_BALANCE_CAPTURE_AUDIT_STAGE68B_RU.md", "tests/reports/STAGE68B_PREFLIGHT_REPORT_RU.txt",
}
assert STAGE68B_REQUIRED.issubset(set(REQUIRED_FILES)), "Stage68B balance-capture evidence must be mandatory in independent preflight"
STAGE68C_REQUIRED = {
    "ROADMAP_STATUS_STAGE68C_RU.md", "STAGE68C_BUILD_REPORT_RU.md",
    "WEB_EXPORT_RUNTIME_CHECKLIST_STAGE68C_RU.md", "README_WEB_RU.md", "export_presets.cfg",
    ".github/workflows/abyssloop-web.yml", "tools/export_web.sh", "tools/web_export_preflight.py",
    "tools/web_browser_smoke_test.py", "tools/serve_web_export.py", "tests/web_export_readiness_regression.py",
    "tests/reports/WEB_EXPORT_READINESS_AUDIT_STAGE68C_RU.md", "tests/reports/WEB_EXPORT_PREFLIGHT_STAGE68C_RU.txt",
}
assert STAGE68C_REQUIRED.issubset(set(REQUIRED_FILES)), "Stage68C Web export and browser QA pipeline evidence must be mandatory in independent preflight"
STAGE64B_REQUIRED = {
    "tests/stage64b_engine_run_capture.gd",
    "tests/stage64b_engine_run_capture_runner.tscn",
    "tests/stage64b_engine_run_capture_regression.py",
    "tests/reports/STAGE64B_AUTOMATED_ENGINE_RUN_CAPTURE_GUIDE_RU.md",
}
assert STAGE64B_REQUIRED.issubset(set(REQUIRED_FILES)), "Stage64B automated engine capture and evidence must be mandatory in independent preflight"


def write_fixture(root: Path) -> None:
    for name in REQUIRED_FILES:
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if name == "project.godot":
            content = f'config/name="Abyss Loop"\nconfig/version="{VERSION}"\n'
        elif name in {"README_RU.md", "BUILD_REPORT_RU.md", "ROADMAP_STATUS_RU.md"}:
            content = f"Prototype 61.0 RC7 {VERSION}\n"
        elif name == "RELEASE_MANIFEST_RU.md":
            content = f"RELEASE CANDIDATE 7 {VERSION} runtime не подтверждён\n"
        elif name == "RELEASE_CANDIDATE_CHECKLIST_Prototype61.md":
            content = f"{VERSION} Ручная приёмка\n"
        elif name == "UI_ACCEPTANCE_RUNTIME_CHECKLIST_Prototype61.md":
            content = "Godot 4.7.2 stable; высокий контраст\n"
        elif name == "SAVE_INTEGRITY_RUNTIME_CHECKLIST_Prototype59.md":
            content = "checksum integrity SHA-256 checksum mismatch"
        elif name == "POST_RUN_DEBRIEF_RUNTIME_CHECKLIST_Prototype58.md":
            content = "Сценарии результата; не изменяет ресурсы\n"
        elif name in {"ROADMAP_CONTINUATION_STAGES29-57_RU.md", "ROADMAP_CONTINUATION_STAGES29-59_RU.md"}:
            content = f"Этап 59 {VERSION}\n"
        elif name == "ROADMAP_CONTINUATION_STAGES29-61_RU.md":
            content = f"Этап 61 {VERSION}\n"
        elif name == "ROADMAP_CONTINUATION_STAGES29-62_RU.md":
            content = f"Этап 62 {VERSION}; runtime не подтверждён\n"
        elif name == "ROADMAP_STATUS_STAGE68A_RU.md":
            content = "Stage68A; 79/79\n"
        elif name == "STAGE68A_BUILD_REPORT_RU.md":
            content = "79/79 runtime не подтверждён\n"
        elif name == "FINAL_REGRESSION_RUNTIME_CHECKLIST_STAGE68A_RU.md":
            content = "Godot 4.7.2 Runtime acceptance\n"
        elif name == "tests/reports/RESOURCE_GRAPH_AUDIT_STAGE68A_RU.md":
            content = "53 ExtResource\n"
        elif name == "ROADMAP_STATUS_STAGE68B_RU.md":
            content = "Stage68B; Stage64B open\n"
        elif name == "STAGE68B_BUILD_REPORT_RU.md":
            content = "17/17 PASS; Не runtime-tested\n"
        elif name == "REAL_RUN_BALANCE_CAPTURE_GUIDE_STAGE68B_RU.md":
            content = "--input --output\n"
        elif name == "REAL_RUN_BALANCE_RUNTIME_CHECKLIST_STAGE68B_RU.md":
            content = "Godot; legacy_partial\n"
        elif name == "tests/real_run_balance_capture_regression.py":
            content = "synthetic fixtures; balance verdict\n"
        elif name == "tools/real_run_balance.py":
            content = "never edits a save; Баланс не оценён автоматически\n"
        elif name == "tests/reports/REAL_RUN_BALANCE_CAPTURE_AUDIT_STAGE68B_RU.md":
            content = "17/17 PASS; Реальных профилей не получено\n"
        elif name == "tests/reports/STAGE68B_PREFLIGHT_REPORT_RU.txt":
            content = "Stage68B; Runtime: NOT RUN\n"
        elif name == "tests/stage64b_engine_run_capture_regression.py":
            content = "STAGE64B ENGINE CAPTURE REGRESSION PASSED; never forces player/enemy health\n"
        elif name == "tests/reports/STAGE64B_AUTOMATED_ENGINE_RUN_CAPTURE_GUIDE_RU.md":
            content = "automated_engine_run is not human playtest evidence\n"
        elif name == "ROADMAP_STATUS_STAGE68C_RU.md":
            content = "Stage68C Web export pipeline; browser URL not yet published\n"
        elif name == "STAGE68C_BUILD_REPORT_RU.md":
            content = "Web export preparation; runtime не подтверждён\n"
        elif name == "WEB_EXPORT_RUNTIME_CHECKLIST_STAGE68C_RU.md":
            content = "Godot 4.7.2; WebGL 2.0; browser test pending\n"
        elif name == "README_WEB_RU.md":
            content = "Godot 4.7.2 Web export instructions; index.html entry point\n"
        elif name == "export_presets.cfg":
            content = '[preset.0]\nname="Web"\nplatform="Web"\n'
        elif name == ".github/workflows/abyssloop-web.yml":
            content = "web_browser_smoke_test.py deploy-pages\n"
        elif name == "tools/export_web.sh":
            content = "SHA-256 --export-release\n"
        elif name == "tools/web_export_preflight.py":
            content = "source_checks build_checks\n"
        elif name == "tools/web_browser_smoke_test.py":
            content = "WebGL 2 index.wasm\n"
        elif name == "tools/serve_web_export.py":
            content = "application/wasm 127.0.0.1\n"
        elif name == "tests/web_export_readiness_regression.py":
            content = "WEB EXPORT READINESS REGRESSION PASSED synthetic export files\n"
        elif name == "tests/reports/WEB_EXPORT_READINESS_AUDIT_STAGE68C_RU.md":
            content = "READY WITH WARNINGS; Godot runtime not executed\n"
        elif name == "tests/reports/WEB_EXPORT_PREFLIGHT_STAGE68C_RU.txt":
            content = "7/7; WebGL 2.0 runtime not tested\n"
        elif name == "ROADMAP_CONTINUATION_STAGES29-60_RU.md":
            content = f"Этап 60 {VERSION}\n"
        elif name == "GAMEPLAY_CYCLE_RUNTIME_CHECKLIST_Prototype60.md":
            content = "full cycle runtime checklist\n"
        elif name == "tools/package_release.py":
            content = f'read_project_version(ROOT) != "{VERSION}" release_preflight audit_archive\n'
        elif name in {"RUN_RELEASE_GATE_WINDOWS.bat", "RUN_TESTS_WINDOWS.bat"}:
            content = f"AbyssLoop_Godot_Prototype_61_RUNTIME_TESTED.zip tools\\release_preflight.py\n"
        else:
            content = f"fixture for {name}\n"
        path.write_text(content, encoding="utf-8")


def names_with_failures(checks):
    return [check.name for check in checks if not check.passed]


with tempfile.TemporaryDirectory(prefix="abyssloop_preflight_valid_") as temp:
    root = Path(temp) / "project"
    write_fixture(root)
    checks = audit_project(root, VERSION)
    assert not names_with_failures(checks), "valid preflight fixture failed: " + "; ".join(f"{c.name}: {c.detail}" for c in checks if not c.passed)

    (root / "project.godot").write_text('config/name="Abyss Loop"\nconfig/version="0.56.0"\n', encoding="utf-8")
    failed_names = names_with_failures(audit_project(root, VERSION))
    assert "stable app identity and exact version" in failed_names, "preflight must fail a stale project version"
    (root / "project.godot").write_text(f'config/name="Abyss Loop"\nconfig/version="{VERSION}"\n', encoding="utf-8")

    manifest = root / "RELEASE_MANIFEST_RU.md"
    manifest.write_text(f"RELEASE CANDIDATE 2 {VERSION} runtime не подтверждён\n", encoding="utf-8")
    failed_names = names_with_failures(audit_project(root, VERSION))
    assert "README/manifest/checklist/roadmap version consistency" in failed_names, "preflight must reject RC manifest drift"
    manifest.write_text(f"RELEASE CANDIDATE 7 {VERSION} runtime не подтверждён\n", encoding="utf-8")

    report = root / "tests/reports/STATIC_TEST_REPORT.txt"
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text("Checks discovered: 3; checks completed: 2; passed: 2; failed/timed out: 0\n", encoding="utf-8")
    failed_names = names_with_failures(audit_project(root, VERSION, require_static_report=True))
    assert "latest static/regression report is complete and all-pass" in failed_names, "preflight must reject partial static evidence"
    report.write_text("Checks discovered: 3; checks completed: 3; passed: 3; failed/timed out: 0\n", encoding="utf-8")
    checks = audit_project(root, VERSION, require_static_report=True)
    assert not names_with_failures(checks), "complete all-pass static report must be accepted"

with tempfile.TemporaryDirectory(prefix="abyssloop_preflight_archive_") as temp:
    root = Path(temp) / "project"
    root.mkdir()
    (root / "project.godot").write_text(f'config/name="Abyss Loop"\nconfig/version="{VERSION}"\n', encoding="utf-8")
    (root / "assets").mkdir()
    (root / "assets" / "sample.dat").write_bytes(b"asset bytes")
    expected = iter_project_files(root, include_runtime_report=False)
    good = Path(temp) / "good.zip"
    with zipfile.ZipFile(good, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in expected:
            archive.write(path, "AbyssLoop/" + path.relative_to(root).as_posix())
    checks = audit_archive(root, good, VERSION)
    assert not names_with_failures(checks), "valid archive failed independent audit: " + "; ".join(f"{c.name}: {c.detail}" for c in checks if not c.passed)

    extra = Path(temp) / "extra.zip"
    with zipfile.ZipFile(good, "r") as source, zipfile.ZipFile(extra, "w", compression=zipfile.ZIP_DEFLATED) as target:
        for name in source.namelist():
            target.writestr(name, source.read(name))
        target.writestr("AbyssLoop/unexpected.txt", b"unexpected")
    failed_names = names_with_failures(audit_archive(root, extra, VERSION))
    assert "archive members exactly match filtered source tree" in failed_names, "archive audit must reject extra members"

    changed = Path(temp) / "changed.zip"
    with zipfile.ZipFile(good, "r") as source, zipfile.ZipFile(changed, "w", compression=zipfile.ZIP_DEFLATED) as target:
        for name in source.namelist():
            data = source.read(name)
            if name == "AbyssLoop/assets/sample.dat":
                data = b"changed after package"
            target.writestr(name, data)
    failed_names = names_with_failures(audit_archive(root, changed, VERSION))
    assert "packaged file bytes match source" in failed_names, "archive audit must reject byte drift"

checks = audit_project(ROOT, VERSION)
assert not names_with_failures(checks), "current RC7 project preflight is broken: " + "; ".join(f"{c.name}: {c.detail}" for c in checks if not c.passed)
print("RELEASE PREFLIGHT REGRESSION PASSED: version drift, manifest drift, incomplete static report, extra ZIP member and byte mismatch are rejected")

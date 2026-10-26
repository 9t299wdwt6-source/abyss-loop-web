"""Validate release packaging and reject accidental cache/test-artifact inclusion."""
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools/package_release.py"
assert TOOL.is_file(), "release package builder is missing"
with tempfile.TemporaryDirectory() as directory:
    output = Path(directory) / "AbyssLoop_package_check.zip"
    result = subprocess.run([sys.executable, str(TOOL), "--output", str(output)], cwd=ROOT,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
    assert result.returncode == 0, "release package check failed:\n" + result.stdout
    assert output.is_file() and output.stat().st_size > 100_000, "package is missing or suspiciously small"
    with zipfile.ZipFile(output, "r") as archive:
        assert archive.testzip() is None, "ZIP contains a corrupt member"
        names = set(archive.namelist())
        required = {
            "AbyssLoop/ROADMAP_STATUS_STAGE67_RU.md",
            "AbyssLoop/STAGE67_BUILD_REPORT_RU.md",
            "AbyssLoop/FIRST_HOUR_GUIDANCE_RUNTIME_CHECKLIST_STAGE67_RU.md",
            "AbyssLoop/tests/first_hour_guidance_regression.py",
            "AbyssLoop/tests/reports/FIRST_HOUR_GUIDANCE_AUDIT_STAGE67_RU.md",
            "AbyssLoop/tests/reports/LOCALIZATION_AUDIT_STAGE67_RU.md",
            "AbyssLoop/tests/reports/STAGE67_PREFLIGHT_REPORT_RU.txt",
            "AbyssLoop/ROADMAP_STATUS_STAGE66C_RU.md",
            "AbyssLoop/STAGE66C_BUILD_REPORT_RU.md",
            "AbyssLoop/ENEMY_ROLE_AND_STATUS_RUNTIME_CHECKLIST_STAGE66C_RU.md",
            "AbyssLoop/tests/stage66c_enemy_status_readability_regression.py",
            "AbyssLoop/tests/reports/ENEMY_ROLE_AND_STATUS_AUDIT_STAGE66C_RU.md",
            "AbyssLoop/tests/reports/LOCALIZATION_AUDIT_STAGE66C_RU.md",
            "AbyssLoop/tests/reports/STAGE66C_PREFLIGHT_REPORT_RU.txt",
            "AbyssLoop/ROADMAP_STATUS_STAGE66B_RU.md",
            "AbyssLoop/STAGE66B_BUILD_REPORT_RU.md",
            "AbyssLoop/CARD_PLACEMENT_AUDIT_STAGE66B_RU.md",
            "AbyssLoop/CARD_PLACEMENT_RUNTIME_ACCEPTANCE_STAGE66B_RU.md",
            "AbyssLoop/tests/stage66b_readability_localization_regression.py",
            "AbyssLoop/tests/reports/CARD_PLACEMENT_AUDIT_STAGE66B_RU.md",
            "AbyssLoop/tests/reports/LOCALIZATION_AUDIT_STAGE66B_RU.md",
            "AbyssLoop/tests/reports/STAGE66B_PREFLIGHT_REPORT_RU.txt",
            "AbyssLoop/tests/tutorial_regression.py",
            "AbyssLoop/project.godot", "AbyssLoop/ROADMAP_STATUS_STAGE65E_RU.md", "AbyssLoop/STAGE65E_BUILD_REPORT_RU.md", "AbyssLoop/tests/reports/CROSS_SYSTEM_INTERACTION_AUDIT_STAGE65E_RU.md", "AbyssLoop/scenes/main.tscn", "AbyssLoop/scripts/systems/expedition_manager.gd",
            "AbyssLoop/scripts/ui/route_view.gd", "AbyssLoop/scripts/ui/developer_diagnostics_report.gd", "AbyssLoop/scripts/ui/status_effect_presenter.gd", "AbyssLoop/scripts/ui/item_text_presenter.gd", "AbyssLoop/scripts/ui/run_debrief_presenter.gd", "AbyssLoop/tests/item_text_presenter_regression.py", "AbyssLoop/tests/equipment_landscape_mechanics_regression.py", "AbyssLoop/ROADMAP_STATUS_STAGE65D_RU.md", "AbyssLoop/STAGE65D_BUILD_REPORT_RU.md", "AbyssLoop/ROADMAP_STATUS_STAGE65C_RU.md", "AbyssLoop/STAGE65C_BUILD_REPORT_RU.md", "AbyssLoop/tests/reports/LOCALIZATION_TEXT_AUDIT_RU.md", "AbyssLoop/BALANCE_SCREENING_STAGE64A_RU.md", "AbyssLoop/tests/reports/REAL_RUN_BALANCE_CAPTURE_TEMPLATE_STAGE64B_RU.md", "AbyssLoop/tests/smoke_test.gd", "AbyssLoop/tests/run_debrief_regression.py", "AbyssLoop/tests/cross_system_interaction_regression.py", "AbyssLoop/tests/reports/BALANCE_CAMPAIGN_REPORT_RU.md",
            "AbyssLoop/RELEASE_MANIFEST_RU.md", "AbyssLoop/assets/background/abyss_pixel_backdrop.png",
            "AbyssLoop/tests/content_v1_matrix_regression.py", "AbyssLoop/tests/fixtures/content_v1_stable_ids.json",
            "AbyssLoop/tests/reports/CONTENT_V1_READINESS_MATRIX_RU.md", "AbyssLoop/tools/content_v1_audit.py",
            "AbyssLoop/tests/developer_tools_regression.py", "AbyssLoop/tools/developer_diagnostics.py",
            "AbyssLoop/tests/reports/DEVELOPER_DIAGNOSTICS_RU.md",
            "AbyssLoop/DEVELOPER_TOOLS_RUNTIME_CHECKLIST_Prototype50.md",
            "AbyssLoop/KEYBOARD_UX_RUNTIME_CHECKLIST_Prototype51.md",
            "AbyssLoop/tests/keyboard_focus_navigation_regression.py",
            "AbyssLoop/ACCESSIBILITY_SETTINGS_RUNTIME_CHECKLIST_Prototype52.md",
            "AbyssLoop/tests/accessibility_settings_regression.py",
            "AbyssLoop/LOCALIZATION_UI_RUNTIME_CHECKLIST_Prototype53.md",
            "AbyssLoop/localization/strings_ru.json",
            "AbyssLoop/scripts/core/localization.gd",
            "AbyssLoop/tests/localization_catalog_regression.py",
            "AbyssLoop/tests/expedition_integration_audit.gd",
            "AbyssLoop/tests/expedition_integration_audit_regression.py",
            "AbyssLoop/INTEGRATION_AUDIT_RUNTIME_CHECKLIST_Prototype54.md",
            "AbyssLoop/RELEASE_CANDIDATE_CHECKLIST_Prototype56.md",
            "AbyssLoop/RELEASE_CANDIDATE_CHECKLIST_Prototype60.md",
            "AbyssLoop/RELEASE_CANDIDATE_CHECKLIST_Prototype61.md",
            "AbyssLoop/UI_ACCEPTANCE_RUNTIME_CHECKLIST_Prototype61.md",
            "AbyssLoop/ROADMAP_CONTINUATION_STAGES29-61_RU.md",
            "AbyssLoop/tests/ui_modal_responsiveness_regression.py",
            "AbyssLoop/GAMEPLAY_CYCLE_RUNTIME_CHECKLIST_Prototype60.md",
            "AbyssLoop/tests/gameplay_cycle_regression.py",
            "AbyssLoop/POST_RUN_DEBRIEF_RUNTIME_CHECKLIST_Prototype58.md",
            "AbyssLoop/ROADMAP_CONTINUATION_STAGES29-57_RU.md",
            "AbyssLoop/ROADMAP_CONTINUATION_STAGES29-59_RU.md",
            "AbyssLoop/tools/release_preflight.py",
            "AbyssLoop/tests/release_preflight_regression.py",
            "AbyssLoop/tests/release_candidate_regression.py",
            "AbyssLoop/tests/reports/RELEASE_CANDIDATE_PREFLIGHT_RU.md",
            "AbyssLoop/ROADMAP_CONTINUATION_STAGES29-56_RU.md",
            "AbyssLoop/ROADMAP_CONTINUATION_STAGES29-57_RU.md",
            "AbyssLoop/ROADMAP_CONTINUATION_STAGES29-59_RU.md",
            "AbyssLoop/tests/release_artifact_hygiene_regression.py",
            "AbyssLoop/tests/runtime_gate_report_validation_regression.py",
            "AbyssLoop/tests/ui_screenshot_findings_regression.py",
            "AbyssLoop/tools/localization_audit.py",
            "AbyssLoop/tests/reports/LOCALIZATION_TEXT_AUDIT_RU.md"
        }
        assert required.issubset(names), "package is missing required members: " + ", ".join(sorted(required - names))
        top_level = {name.split("/", 1)[0] for name in names}
        assert top_level == {"AbyssLoop"} and all(name.startswith("AbyssLoop/") for name in names), "ZIP must contain exactly one root folder named AbyssLoop/"
        assert not any(".godot/" in name or "__pycache__/" in name or name.endswith(".pyc") for name in names), "developer cache leaked into archive"
        assert not any(Path(name).name.lower().startswith(".env") or Path(name).suffix.lower() in {".log", ".pem", ".key", ".p12", ".pfx", ".swp", ".swo"} for name in names), "local secret or log artifact leaked into archive"
        project = archive.read("AbyssLoop/project.godot").decode("utf-8")
        registry = archive.read("AbyssLoop/scripts/core/content_registry.gd").decode("utf-8")
        assert 'config/name="Abyss Loop"' in project and 'config/version="0.61.0"' in project, "wrong stable name/version in package"
        assert "Prototype 27" not in project, "prototype number must not change persistent application profile name"
        save_script = archive.read("AbyssLoop/scripts/core/save_system.gd").decode("utf-8")
        assert "_try_migrate_legacy_profile" in save_script and "recovered_backup_missing_primary" in save_script, "profile continuity and missing-primary recovery are missing"
        runtime_gate = archive.read("AbyssLoop/tools/run_runtime_gate.py").decode("utf-8")
        assert "Abyss Loop — Runtime QA Isolated" in runtime_gate and "ABYSS_LOOP_DISABLE_LEGACY_PROFILE_IMPORT" in runtime_gate, "runtime tests must be isolated from player saves"
        assert '"Expedition integration audit"' in runtime_gate and "res://tests/expedition_integration_audit.gd" in runtime_gate, "full cross-system audit must be included in the runtime gate"
        assert "const RUN_MODIFIERS :=" in registry, "modifier configuration missing from release package"
        ui = archive.read("AbyssLoop/scripts/ui/ui_controller.gd").decode("utf-8")
        diagnostic_reporter = archive.read("AbyssLoop/scripts/ui/developer_diagnostics_report.gd").decode("utf-8")
        assert "func build_report(manager: Variant, screen_mode: String) -> String:" in diagnostic_reporter and "developer_diagnostics_report.build_report(manager, screen_mode)" in ui, "diagnostic report must be extracted and included in package"
        assert "func _open_developer_tools()" in ui and "OS.is_debug_build()" in ui and "KEY_F9" in ui, "debug-only developer panel is missing"
        assert "current.focus_next = current.get_path_to(next_control)" in ui and "current.focus_previous = current.get_path_to(previous_control)" in ui, "modal keyboard focus cycle is missing"
        assert "func _apply_keyboard_focus_outline(control: Control)" in ui and "confirm_salvage" in ui, "keyboard focus outlines or safe modal protection are missing"
        assert "func _apply_display_settings()" in ui and "window.content_scale_factor" in ui, "display scaling/window mode settings are missing"
        assert "func _apply_contrast_to_tree(node: Node)" in ui and "status_symbols" in ui, "accessibility contrast and redundant status cues are missing"
        assert "var base_scroll := ScrollContainer.new()" in ui and "base_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO" in ui, "shelter layout must remain scrollable instead of clipping below the viewport"
        assert "Localization.text(\"route.header\")" in archive.read("AbyssLoop/scripts/ui/route_view.gd").decode("utf-8"), "route labels are not centralized"
        assert 'Localization="*res://scripts/core/localization.gd"' in project, "localization service autoload is missing"
        localized_ui = archive.read("AbyssLoop/scripts/ui/ui_controller.gd").decode("utf-8")
        assert '_t("base.floor.label")' in localized_ui and '_t("help.body")' in localized_ui, "main preparation/help UI is not using localized floor/help catalog keys"
        smoke = archive.read("AbyssLoop/tests/smoke_test.gd").decode("utf-8")
        assert "Localization.catalog_size() >= 100" in smoke and 'Localization.text("help.body")' in smoke, "runtime smoke is missing localization catalog assertions"
        assert 'tile_short = "%s · %d/%d"' in localized_ui, "repeated tile cards lack a clear copy indicator"
        developer_report = archive.read("AbyssLoop/tests/reports/DEVELOPER_DIAGNOSTICS_RU.md").decode("utf-8")
        assert "Ошибок схемы контента: 0" in developer_report, "developer diagnostics report has content errors"
        assert 'config/version="0.61.0"' in project, "wrong current version in package"
        manifest = archive.read("AbyssLoop/tests/fixtures/content_v1_stable_ids.json").decode("utf-8")
        assert '"Тайлы ландшафта"' in manifest and '"Боссы"' in manifest, "stable content ID baseline missing major categories"
        manager = archive.read("AbyssLoop/scripts/systems/expedition_manager.gd").decode("utf-8")
        assert "_tower_attack" not in manager and "turret_attack" not in manager, "tower combat slipped into build"
        debrief_presenter = archive.read("AbyssLoop/scripts/ui/run_debrief_presenter.gd").decode("utf-8")
        assert "RunDebriefPresenterScript.build(summary)" in ui and "РАЗБОР ЗАБЕГА · СЛЕДУЮЩИЙ ШАГ" in ui and "static func build(summary: Dictionary) -> Dictionary:" in debrief_presenter, "post-run coaching presenter/delegation missing"
print("RELEASE PACKAGE REGRESSION PASSED: AbyssLoop/ root folder, required files, archive integrity, stable save identity, runtime QA isolation, keyboard-focus and accessibility safeguards, version and no tower combat")
print("Package content is validated at file/archive level; this does not confirm Godot runtime compilation.")

#!/usr/bin/env python3
"""Regression tests for Web export settings and export-artifact validation."""
from __future__ import annotations
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from web_export_preflight import build_checks, source_checks  # noqa: E402


# The real project must be ready for export without pretending a Web build exists.
source_result = source_checks(ROOT)
source_failures = [check for check in source_result if check.status == "FAIL"]
assert not source_failures, "Web export source preflight failed: " + "; ".join(f"{item.name}: {item.detail}" for item in source_failures)
assert any(check.status == "WARN" and "clipboard" in check.name.lower() for check in source_result), "the guarded debug clipboard API should stay visible as a review warning"
assert (ROOT / ".github/workflows/abyssloop-web.yml").is_file(), "browser export/QA workflow must be shipped"
assert (ROOT / "tools/web_browser_smoke_test.py").is_file(), "browser smoke tester must be shipped"

# A small fixture confirms the validator fails closed when WebGL compatibility is disabled.
with tempfile.TemporaryDirectory(prefix="abyssloop-web-source-fixture-") as temp:
    base = Path(temp)
    (base / "scenes").mkdir()
    (base / "scripts/core").mkdir(parents=True)
    (base / "project.godot").write_text(
        'config/name="Abyss Loop"\n'
        'renderer/rendering_method="gl_compatibility"\n'
        'renderer/rendering_method.mobile="gl_compatibility"\n', encoding="utf-8")
    (base / "scenes/main.tscn").write_text('[gd_scene format=3]\n', encoding="utf-8")
    (base / "scripts/core/save_system.gd").write_text('const SAVE_PATH := "user://loop_roguelite_save.json"\n', encoding="utf-8")
    (base / "export_presets.cfg").write_text(
        '[preset.0]\nname="Web"\nplatform="Web"\n'
        '[preset.0.options]\nvariant/thread_support=false\nvariant/extensions_support=false\n'
        'html/canvas_resize_policy=2\nhtml/focus_canvas_on_start=true\n'
        'html/experimental_virtual_keyboard=true\n', encoding="utf-8")
    (base / "scripts/ui").mkdir(parents=True)
    (base / "scripts/ui/ui_controller.gd").write_text('func _ready():\n\tpass\n', encoding="utf-8")
    valid = source_checks(base)
    assert not [check for check in valid if check.status == "FAIL"], "valid minimal Web source fixture unexpectedly failed"
    (base / "project.godot").write_text(
        'config/name="Abyss Loop"\n'
        'renderer/rendering_method="forward_plus"\n'
        'renderer/rendering_method.mobile="forward_plus"\n', encoding="utf-8")
    invalid = source_checks(base)
    assert "Web-compatible Compatibility renderer" in {check.name for check in invalid if check.status == "FAIL"}, "preflight must reject non-Web rendering methods"

# A real export has to include matching, non-empty runtime files beside index.html.
with tempfile.TemporaryDirectory(prefix="abyssloop-web-build-fixture-") as temp:
    build = Path(temp)
    for name in ("index.html", "index.js", "index.wasm", "index.pck"):
        (build / name).write_bytes(b"synthetic fixture" if name != "index.html" else b"<!doctype html>")
    valid = build_checks(build)
    assert not [check for check in valid if check.status == "FAIL"], "complete Web artifact fixture unexpectedly failed"
    (build / "index.wasm").unlink()
    invalid = build_checks(build)
    assert any(check.status == "FAIL" and "index.wasm" in check.name for check in invalid), "preflight must reject a missing WebAssembly runtime"

print("WEB EXPORT READINESS REGRESSION PASSED: project compatibility, preset/CI hooks, and fail-closed build artifact checks")
print("This test uses synthetic export files; it does not compile or execute Godot.")

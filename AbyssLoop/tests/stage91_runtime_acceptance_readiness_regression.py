#!/usr/bin/env python3
"""Stage 91 source contracts: real runtime/browser gates must be wired and fail closed."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
runtime_gate = (ROOT / "tools/run_runtime_gate.py").read_text(encoding="utf-8")
web_smoke = (ROOT / "tools/web_browser_smoke_test.py").read_text(encoding="utf-8")
web_gameplay = (ROOT / "tools/web_gameplay_browser_acceptance.py").read_text(encoding="utf-8")
workflow_path = ROOT / ".github/workflows/abyssloop-web.yml"
workflow = workflow_path.read_text(encoding="utf-8") if workflow_path.is_file() else (ROOT.parent / ".github/workflows/abyssloop-web.yml").read_text(encoding="utf-8")
map_runtime = (ROOT / "tests/stage89_map_runtime_gate_regression.py").read_text(encoding="utf-8")
report = (ROOT / "STAGE91_MAP_RUNTIME_ACCEPTANCE_REPORT_RU.md").read_text(encoding="utf-8")
checklist = (ROOT / "STAGE91_MAP_RUNTIME_ACCEPTANCE_CHECKLIST_RU.md").read_text(encoding="utf-8")

checks = {
    "runtime gate requires an explicitly selected Godot executable": 'parser.add_argument("--godot", required=True' in runtime_gate,
    "runtime gate deletes stale pass evidence before attempting new gates": 'PASS_REPORT.unlink(missing_ok=True)' in runtime_gate and 'FAIL_REPORT.unlink(missing_ok=True)' in runtime_gate,
    "runtime gate rejects any engine version other than Godot 4.7.2": '4\\.7\\.2\\.stable' in runtime_gate,
    "runtime gate produces no runtime-tested archive when engine is unavailable": 'if not success:' in runtime_gate and 'no runtime-tested ZIP was created' in runtime_gate,
    "browser smoke measures real WebGL2 canvas and viewport sizes": 'getContext(\'webgl2\')' in web_smoke and 'page.set_viewport_size' in web_smoke,
    "browser smoke checks real JS/WASM/PCK responses and WASM MIME": 'asset_responses' in web_smoke and 'application/wasm' in web_smoke,
    "browser smoke fails on page or console errors and relevant failed requests": 'no uncaught JavaScript page errors' in web_smoke and 'no browser console errors' in web_smoke and 'no failed JS/WASM/PCK requests' in web_smoke,
    "gameplay browser acceptance includes reload and save resume": 'page.reload' in web_gameplay and 'resume' in web_gameplay.lower(),
    "browser gameplay acceptance includes touch emulation and a real 390x844 phone viewport": 'has_touch=True' in web_gameplay and '"width": 390, "height": 844' in web_gameplay and 'touchscreen.tap' in web_gameplay,
    "CI workflow runs the real discovery mask and save/restore acceptance": 'res://tests/expedition_runtime_acceptance_runner.tscn' in workflow and 'Run Godot gameplay acceptance' in workflow,
    "CI workflow exports Web and runs both Chromium test layers": 'Export Godot Web build' in workflow and 'web_browser_smoke_test.py' in workflow and 'web_gameplay_browser_acceptance.py' in workflow,
    "map-specific save/restore and old-snapshot contracts remain wired": 'restored.discovered_world_cells == manager.discovered_world_cells' in map_runtime and 'legacy_snapshot.erase("discovered_world_cells")' in map_runtime,
    "Stage 91 report explicitly records runtime as blocked rather than passed": 'STATIC PASS / RUNTIME BLOCKED' in report and 'NOT RUNTIME-ACCEPTED' in report,
    "Stage 91 checklist leaves current-candidate runtime checks open": 'Current-candidate Godot/runtime/browser checks: blocked by environment; not passed.' in checklist,
}
for label, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {label}")
failures = [label for label, passed in checks.items() if not passed]
if failures:
    raise SystemExit("Stage 91 runtime acceptance readiness regression failed: " + "; ".join(failures))
print(f"STAGE 91 RUNTIME ACCEPTANCE READINESS REGRESSION PASSED: {len(checks)}/{len(checks)} source contracts")
print("This test verifies gate wiring only; it does not claim Godot or browser runtime acceptance passed.")

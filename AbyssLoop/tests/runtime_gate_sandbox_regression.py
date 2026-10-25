"""Source-level regression for isolated runtime testing and gated packaging."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
runner = (ROOT / "tools" / "run_runtime_gate.py").read_text(encoding="utf-8")
packager = (ROOT / "tools" / "package_release.py").read_text(encoding="utf-8")
integrity = (ROOT / "tools" / "release_integrity.py").read_text(encoding="utf-8")
checks = {
    "runtime gate uses an isolated temporary project": "TemporaryDirectory" in runner and "shutil.copytree(ROOT, sandbox" in runner,
    "isolated project uses a distinct user-data identity": 'config/name="Abyss Loop — Runtime QA Isolated"' in runner,
    "QA cannot import actual legacy user profiles": 'ABYSS_LOOP_DISABLE_LEGACY_PROFILE_IMPORT' in runner and 'env["ABYSS_LOOP_DISABLE_LEGACY_PROFILE_IMPORT"] = "1"' in runner,
    "main project is editor/import-preflighted before main launch": runner.index('"Editor/import preflight"') < runner.index('"Clean main-scene launch"'),
    "main scene launches before gameplay smoke": runner.index('"Clean main-scene launch"') < runner.index('"Gameplay smoke"'),
    "save regression runs after smoke": runner.index('"Gameplay smoke"') < runner.index('"Save-system regression"'),
    "cross-system expedition audit runs after save regression": runner.index('"Save-system regression"') < runner.index('"Expedition integration audit"') and "res://tests/expedition_integration_audit.gd" in runner,
    "inventory settlement acceptance runs after broader integration audit": runner.index('"Expedition integration audit"') < runner.index('"Inventory-to-settlement runtime acceptance"') and "res://tests/inventory_settlement_runtime_acceptance_runner.tscn" in runner,
    "all eight runtime gates are required": "len(steps) == 8" in runner and all(label in packager for label in ["Static/regression suite", "Godot version", "Editor/import preflight", "Clean main-scene launch", "Gameplay smoke", "Save-system regression", "Expedition integration audit", "Inventory-to-settlement runtime acceptance"]),
    "failed runtime gates do not package": 'if not success:' in runner and 'no runtime-tested ZIP was created' in runner,
    "runtime report is fingerprinted against source": "project_fingerprint(ROOT)" in runner and "Source fingerprint:" in runner,
    "runtime fingerprint is refreshed after static reports are regenerated": runner.index('static_step = run_step') < runner.index('fingerprint = project_fingerprint(ROOT)', runner.index('static_step = run_step')),
    "packager requires a current gate report on release path": "--require-runtime-gate" in packager and "runtime gate report is stale" in packager,
    "fingerprint excludes volatile reports and caches": "VOLATILE_REPORTS" in integrity and "SKIP_DIRS" in integrity,
}
failed = [name for name, ok in checks.items() if not ok]
assert not failed, "Runtime gate isolation regression failed: " + ", ".join(failed)
print("RUNTIME GATE SANDBOX REGRESSION PASSED: " + str(len(checks)) + " checks")
for name in checks:
    print("- " + name)
print("The runtime gate must still be executed with Godot 4.7.2 on Windows.")

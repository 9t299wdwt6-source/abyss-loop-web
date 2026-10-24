"""Regression guards for actual browser reload and saved-expedition resume acceptance."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "tools" / "web_gameplay_browser_acceptance.py"
script = SCRIPT_PATH.read_text(encoding="utf-8")

checks = {
    "browser acceptance performs a real page reload after road placement": 'page.reload(wait_until="domcontentloaded"' in script and "selected tile is placed on a free road node by pointer" in script,
    "reload test tolerates cached JavaScript but requires fresh WASM/PCK requests": "counts_before_reload" in script and "Godot WASM/PCK are available again after browser reload" in script and 'reload_assets[".wasm"] and reload_assets[".pck"]' in script,
    "reload test checks transition to shelter": "browser reload leaves the expedition and returns to a shelter view" in script and "reload_hash != placed_hash" in script,
    "browser script explicitly checks saved-expedition resume": "saved expedition resumes after reload" in script,
    "resume click targets the compact saved-expedition button after reload": 'page.mouse.click(450, 385)' in script and "replaces the larger preparation form and moves upward" in script,
    "browser acceptance includes real touch interaction checks": "has_touch=True" in script and "touch tap dismisses first-launch tutorial" in script and "touch tap places the selected tile on a free road node" in script,
    "browser QA boots and captures a 390x844 phone-portrait viewport": 'viewport={"width": 390, "height": 844}' in script and "15-phone-portrait-first-launch" in script and "16-phone-portrait-after-tutorial" in script,
    "browser QA validates tutorial touch on phone portrait": "phone portrait touch dismisses first-launch tutorial" in script and "phone portrait acceptance completes" in script,
    "phone portrait tap targets the visible tutorial action after adaptive scaling": "phone_page.touchscreen.tap(195, 545)" in script,
    "resume test checks the same persisted road-node image crop": "road_node_clip" in script and "resumed_node_hash == placed_node_hash" in script,
    "browser QA scope separates the phone-portrait probe from full mobile and campaign acceptance": "390x844 phone-portrait boot/tutorial check" in script and "full mobile layout and complete playthrough remain separate acceptance items" in script,
    "reload, resume, JS errors, and console errors fail the browser acceptance": 'failures = [item for item in checks if not item["passed"]]' in script and "not errors" in script and "not console_errors" in script,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    raise SystemExit(f"WEB GAMEPLAY RELOAD REGRESSION FAILED: {failed}")
print(f"WEB GAMEPLAY RELOAD REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("These source tests do not claim that browser persistence has passed; the Chromium runtime job records that evidence.")

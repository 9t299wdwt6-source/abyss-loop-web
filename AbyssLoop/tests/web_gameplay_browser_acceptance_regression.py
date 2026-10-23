"""Regression guards for actual browser reload and saved-expedition resume acceptance."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "tools" / "web_gameplay_browser_acceptance.py"
script = SCRIPT_PATH.read_text(encoding="utf-8")

checks = {
    "browser acceptance performs a real page reload after road placement": 'page.reload(wait_until="domcontentloaded"' in script and "selected tile is placed on a free road node by pointer" in script,
    "reload test waits for JS/WASM/PCK to be fetched again": "counts_before_reload" in script and "asset_response_counts[suffix] > counts_before_reload[suffix]" in script,
    "reload test checks transition to shelter": "browser reload leaves the expedition and returns to a shelter view" in script and "reload_hash != placed_hash" in script,
    "resume test checks the same persisted road-node image crop": "road_node_clip" in script and "resumed_node_hash == placed_node_hash" in script,
    "browser QA scope admits that real iPhone Safari is still manual": "browser reload, and saved-run resume" in script and "not full-playthrough or iPhone Safari acceptance" in script,
    "reload, resume, JS errors, and console errors fail the browser acceptance": 'failures = [item for item in checks if not item["passed"]]' in script and "not errors" in script and "not console_errors" in script,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    raise SystemExit(f"WEB GAMEPLAY RELOAD REGRESSION FAILED: {failed}")
print(f"WEB GAMEPLAY RELOAD REGRESSION PASSED: {len(checks)}/{len(checks)} checks")
print("These source tests do not claim that browser persistence has passed; the Chromium runtime job records that evidence.")

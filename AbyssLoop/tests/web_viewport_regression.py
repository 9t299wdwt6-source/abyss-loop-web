#!/usr/bin/env python3
"""Regression guard for the real-browser viewport matrix in the Godot Web smoke test."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
smoke = (ROOT / "tools" / "web_browser_smoke_test.py").read_text(encoding="utf-8")

expected_viewports = (
    "(1280, 800)",  # desktop
    "(390, 844)",   # portrait phone
    "(844, 390)",   # landscape phone
    "(768, 1024)",  # tablet
)
checks = {
    "Web smoke test uses a real browser viewport resize": "page.set_viewport_size" in smoke,
    "all four target viewport sizes are represented": all(size in smoke for size in expected_viewports),
    "each resized viewport is measured from the actual canvas": "resized_info = page.locator(\"canvas\").first.evaluate(" in smoke,
    "viewport result is included in the fail-closed smoke checks": "canvas adapts to desktop, portrait, landscape, and tablet viewports" in smoke,
    "viewport evidence is preserved in JSON output": '"viewport_results": viewport_results' in smoke,
    "mobile QA explicitly does not pretend to replace physical Safari/touch testing": "does not replace manual touch/Safari acceptance" in smoke,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    raise SystemExit(f"WEB VIEWPORT REGRESSION FAILED: {failed}")
print(f"WEB VIEWPORT REGRESSION PASSED: {len(checks)}/{len(checks)} checks")

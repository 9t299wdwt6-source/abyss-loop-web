#!/usr/bin/env python3
"""Exercise the real Godot Web UI in Chromium with pointer input."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
import time
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from web_browser_smoke_test import _start_server  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=90)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--screenshots-dir", type=Path, required=True)
    args = parser.parse_args()
    if args.timeout < 10 or args.timeout > 300:
        parser.error("--timeout must be between 10 and 300 seconds")
    try:
        from playwright.sync_api import sync_playwright
    except ImportError as exc:
        print(f"PLAYWRIGHT GAMEPLAY ACCEPTANCE COULD NOT RUN: {exc}", file=sys.stderr)
        return 2

    build = args.directory.expanduser().resolve()
    if not (build / "index.html").is_file():
        print("The exported index.html is missing.", file=sys.stderr)
        return 2

    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.screenshots_dir.mkdir(parents=True, exist_ok=True)
    server, _thread, url = _start_server(build)
    errors: list[str] = []
    console_errors: list[str] = []
    assets: dict[str, bool] = {".js": False, ".wasm": False, ".pck": False}
    screenshots: dict[str, str] = {}
    checks: list[dict[str, Any]] = []

    def add(name: str, passed: bool, detail: Any) -> None:
        checks.append({"name": name, "passed": bool(passed), "detail": detail})
        print(f"{'PASS' if passed else 'FAIL'}: {name} — {detail}")

    def capture(page: Any, name: str) -> str:
        target = args.screenshots_dir / f"{name}.png"
        page.screenshot(path=str(target), full_page=False)
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        screenshots[name] = str(target)
        return digest

    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True, args=[
                "--no-sandbox", "--disable-dev-shm-usage", "--enable-webgl",
                "--ignore-gpu-blocklist", "--use-gl=angle", "--use-angle=swiftshader",
                "--enable-unsafe-swiftshader",
            ])
            context = browser.new_context(viewport={"width": 1280, "height": 800}, device_scale_factor=1)
            page = context.new_page()
            page.on("pageerror", lambda exc: errors.append(str(exc)))
            page.on("console", lambda msg: console_errors.append(msg.text) if msg.type == "error" else None)

            def collect_response(response: Any) -> None:
                suffix = Path(response.url.split("?", 1)[0]).suffix.lower()
                if suffix in assets and 200 <= response.status < 300:
                    assets[suffix] = True

            page.on("response", collect_response)
            try:
                response = page.goto(url, wait_until="domcontentloaded", timeout=args.timeout * 1000)
                add("HTML entry page responds", response is not None and 200 <= response.status < 400, response.status if response else None)
                page.wait_for_selector("canvas", state="visible", timeout=min(20000, args.timeout * 1000))
                deadline = time.monotonic() + args.timeout
                while time.monotonic() < deadline and not all(assets.values()):
                    page.wait_for_timeout(250)
                add("Godot JS/WASM/PCK runtime files load", all(assets.values()), assets)
                page.wait_for_timeout(1200)

                first_hash = capture(page, "01-first-launch-tutorial")
                # On the checked 1280x800 layout, skip-training is centred close to (640, 512).
                page.mouse.click(640, 512)
                page.wait_for_timeout(500)
                shelter_hash = capture(page, "02-shelter-after-tutorial")
                add("first-launch tutorial dismisses after pointer click", shelter_hash != first_hash,
                    {"tutorial": first_hash, "shelter": shelter_hash})

                # The primary launch action is at the lower-left of the shelter panel.
                page.mouse.click(450, 607)
                page.wait_for_timeout(1200)
                expedition_hash = capture(page, "03-expedition-after-launch")
                add("shelter launch action opens expedition UI", expedition_hash != shelter_hash,
                    {"shelter": shelter_hash, "expedition": expedition_hash})
                canvas_info = page.locator("canvas").first.evaluate(
                    "el => ({width: el.width, height: el.height, clientWidth: el.clientWidth, clientHeight: el.clientHeight, visible: !!(el.offsetWidth || el.offsetHeight)})"
                )
                add("game canvas stays visible after the UI transitions",
                    bool(canvas_info.get("visible")) and canvas_info.get("clientWidth", 0) > 10 and canvas_info.get("clientHeight", 0) > 10,
                    canvas_info)
            except Exception as exc:
                add("browser gameplay flow completes", False, f"{type(exc).__name__}: {exc}")
            finally:
                context.close()
                browser.close()
    except Exception as exc:
        add("Chromium launches", False, f"{type(exc).__name__}: {exc}")
    finally:
        server.shutdown()
        server.server_close()

    add("no uncaught JavaScript errors", not errors, errors or "none")
    add("no browser console errors", not console_errors, console_errors or "none")
    failures = [item for item in checks if not item["passed"]]
    report = {
        "project": "Abyss Loop",
        "checked_utc": datetime.now(timezone.utc).isoformat(),
        "url": url,
        "result": "FAIL" if failures else "PASS",
        "scope": "real Chromium pointer interaction through tutorial dismiss and expedition launch; not full-playthrough or iPhone Safari acceptance",
        "runtime_assets": assets,
        "screenshots": screenshots,
        "javascript_errors": errors,
        "console_errors": console_errors,
        "checks": checks,
    }
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"WEB GAMEPLAY BROWSER ACCEPTANCE: {report['result']}")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())

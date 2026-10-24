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
    asset_response_counts: dict[str, int] = {".js": 0, ".wasm": 0, ".pck": 0}
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
                    asset_response_counts[suffix] += 1

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
                # Exercise a real in-game control, card selection, and a legal road-cell
                # placement through the rendered canvas. Pause first so route animation
                # does not make the before/after screenshot comparison nondeterministic.
                page.mouse.click(1095, 316)
                page.wait_for_timeout(350)
                pause_hash = capture(page, "04-expedition-paused")
                add("expedition pause control responds to a real pointer click", pause_hash != expedition_hash,
                    {"expedition": expedition_hash, "paused": pause_hash})

                # On the verified 1280x800 layout the first card is centred near (1020, 540).
                page.mouse.click(1020, 565)
                page.wait_for_timeout(350)
                page.mouse.move(900, 110)
                page.wait_for_timeout(200)
                selected_hash = capture(page, "05-road-tile-selected")
                add("first road tile can be selected by pointer", selected_hash != pause_hash,
                    {"paused": pause_hash, "selected": selected_hash})

                # Route node 2 is a normal, free road node; node 1 at the loop origin is protected.
                page.mouse.click(585, 348)
                page.wait_for_timeout(350)
                page.mouse.move(900, 110)
                page.wait_for_timeout(200)
                placed_hash = capture(page, "06-road-tile-placed")
                add("selected tile is placed on a free road node by pointer", placed_hash != selected_hash,
                    {"selected": selected_hash, "placed": placed_hash})

                # Verify the actual Godot user:// filesystem survives a browser reload.
                # Wait for a complete autosave interval, then require the exported JS,
                # WASM, and PCK files to be requested again by the reloaded page.
                page.wait_for_timeout(2200)
                road_node_clip = {"x": 545, "y": 319, "width": 88, "height": 67}
                placed_node_hash = hashlib.sha256(page.screenshot(clip=road_node_clip)).hexdigest()
                counts_before_reload = dict(asset_response_counts)
                page.reload(wait_until="domcontentloaded", timeout=args.timeout * 1000)
                page.wait_for_selector("canvas", state="visible", timeout=min(20000, args.timeout * 1000))
                reload_deadline = time.monotonic() + args.timeout
                while time.monotonic() < reload_deadline:
                    if all(asset_response_counts[suffix] > counts_before_reload[suffix] for suffix in asset_response_counts):
                        break
                    page.wait_for_timeout(250)
                reload_assets = {
                    suffix: asset_response_counts[suffix] > counts_before_reload[suffix]
                    for suffix in asset_response_counts
                }
                # Chromium may satisfy the JavaScript entry point from HTTP cache
                # without a fresh response event. A visible canvas after reload
                # proves the JS booted; require the binary runtime assets explicitly.
                add("Godot WASM/PCK are available again after browser reload",
                    reload_assets[".wasm"] and reload_assets[".pck"],
                    {"response_events": reload_assets, "js_cached_or_reloaded": assets[".js"]})
                page.wait_for_timeout(1400)
                page.mouse.move(900, 110)
                page.wait_for_timeout(150)
                reload_hash = capture(page, "07-shelter-after-browser-reload")
                reload_node_hash = hashlib.sha256(page.screenshot(clip=road_node_clip)).hexdigest()
                add("browser reload leaves the expedition and returns to a shelter view",
                    reload_hash != placed_hash and reload_node_hash != placed_node_hash,
                    {"before_reload": placed_hash, "after_reload": reload_hash,
                     "road_node_before": placed_node_hash, "road_node_after": reload_node_hash})

                # With a valid persisted checkpoint, the primary shelter action resumes
                # the saved run. A crop of the original placed road node must match after
                # restoration, proving state survived rather than merely changing screens.
                page.mouse.click(450, 378)
                page.wait_for_timeout(1000)
                page.mouse.move(900, 110)
                page.wait_for_timeout(180)
                resumed_hash = capture(page, "08-expedition-resumed-after-browser-reload")
                resumed_node_hash = hashlib.sha256(page.screenshot(clip=road_node_clip)).hexdigest()
                add("saved expedition resumes after reload with the placed road tile preserved",
                    resumed_hash != reload_hash and resumed_node_hash == placed_node_hash,
                    {"shelter_after_reload": reload_hash, "resumed": resumed_hash,
                     "road_node_before": placed_node_hash, "road_node_after_resume": resumed_node_hash})

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
        "scope": "real Chromium pointer interaction through tutorial dismiss, expedition launch, pause, tile selection, road placement, browser reload, and saved-run resume; not full-playthrough or iPhone Safari acceptance",
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

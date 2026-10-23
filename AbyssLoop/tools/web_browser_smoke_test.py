#!/usr/bin/env python3
"""Run a Chromium smoke test against a Godot Web export or published URL.

Requires Playwright Python and a Chromium browser. The test verifies HTTP startup,
WebGL 2 availability, the Godot canvas, successful JS/WASM/PCK responses, and
absence of uncaught JavaScript/console errors. It is a smoke test, not gameplay
acceptance. --self-test exercises this test runner against a synthetic fixture.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import threading
import time
from typing import Any
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from web_export_preflight import build_checks  # noqa: E402


class _QuietWebHandler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm", ".pck": "application/octet-stream", ".js": "text/javascript; charset=utf-8"}

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
        return


def _start_server(directory: Path) -> tuple[ThreadingHTTPServer, threading.Thread, str]:
    handler = lambda *args, **kwargs: _QuietWebHandler(*args, directory=str(directory), **kwargs)  # noqa: E731
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, name="abyssloop-web-test-server", daemon=True)
    thread.start()
    return server, thread, f"http://127.0.0.1:{server.server_address[1]}/"


def _self_test_fixture(directory: Path) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "index.wasm").write_bytes(bytes([0, 97, 115, 109, 1, 0, 0, 0]))
    (directory / "index.pck").write_bytes(b"mock Godot PCK for smoke-test harness validation")
    (directory / "index.js").write_text(
        "Promise.all(["
        "fetch('./index.wasm').then(r=>{if(!r.ok)throw Error('wasm HTTP '+r.status);return r.arrayBuffer()}).then(b=>WebAssembly.instantiate(b)),"
        "fetch('./index.pck').then(r=>{if(!r.ok)throw Error('pck HTTP '+r.status);return r.arrayBuffer()})"
        "]).then(()=>console.log('synthetic runtime loaded')).catch(e=>console.error(e));\n",
        encoding="utf-8",
    )
    (directory / "index.html").write_text(
        "<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>Abyss Loop Web Smoke Fixture</title></head><body style='margin:0;background:#101d22'>"
        "<canvas id='canvas' width='800' height='500' style='display:block;width:100vw;height:100vh'></canvas>"
        "<script>const c=document.getElementById('canvas');const g=c.getContext('2d');g.fillStyle='#101d22';g.fillRect(0,0,c.width,c.height);g.fillStyle='#78d8c1';g.font='bold 32px sans-serif';g.fillText('ABYSS LOOP TEST FIXTURE',36,64);</script>"
        "<script src='./index.js'></script></body></html>",
        encoding="utf-8",
    )


def _run_browser(url: str, timeout_seconds: int, screenshot_path: Path | None) -> dict[str, Any]:
    try:
        from playwright.sync_api import sync_playwright
    except ImportError as exc:
        raise RuntimeError("Playwright is not installed. Run: python -m pip install playwright; python -m playwright install chromium") from exc

    console_errors: list[str] = []
    page_errors: list[str] = []
    failed_requests: list[str] = []
    asset_responses: dict[str, list[dict[str, Any]]] = {".js": [], ".wasm": [], ".pck": []}
    startup_error: str | None = None
    screenshot_result: str | None = None
    canvas_info: dict[str, Any] | None = None
    viewport_results: list[dict[str, Any]] = []
    webgl2_supported = False
    page_title = ""
    response_status: int | None = None

    with sync_playwright() as playwright:
        launch_kwargs: dict[str, Any] = {
            "headless": True,
            # GitHub-hosted Linux runners need SwiftShader for deterministic headless WebGL 2.
            "args": [
                "--no-sandbox", "--disable-dev-shm-usage", "--enable-webgl",
                "--ignore-gpu-blocklist", "--use-gl=angle", "--use-angle=swiftshader",
                "--enable-unsafe-swiftshader",
            ],
        }
        configured_chromium = os.environ.get("PLAYWRIGHT_CHROMIUM_EXECUTABLE", "").strip()
        system_chromium = shutil.which("chromium") or shutil.which("chromium-browser") or shutil.which("google-chrome")
        executable = configured_chromium or system_chromium
        if executable:
            launch_kwargs["executable_path"] = executable
        browser = playwright.chromium.launch(**launch_kwargs)
        context = browser.new_context(viewport={"width": 1280, "height": 800}, device_scale_factor=1)
        page = context.new_page()
        page.on("console", lambda msg: console_errors.append(msg.text) if msg.type == "error" else None)
        page.on("pageerror", lambda exc: page_errors.append(str(exc)))
        page.on("requestfailed", lambda req: failed_requests.append(f"{req.url}: {req.failure}"))

        def collect_response(response: Any) -> None:
            suffix = Path(urlparse(response.url).path).suffix.lower()
            if suffix in asset_responses:
                asset_responses[suffix].append({"url": response.url, "status": response.status, "content_type": response.headers.get("content-type", "")})

        page.on("response", collect_response)
        try:
            main_response = page.goto(url, wait_until="domcontentloaded", timeout=timeout_seconds * 1000)
            response_status = main_response.status if main_response else None
            page.wait_for_selector("canvas", state="visible", timeout=min(20_000, timeout_seconds * 1000))
            webgl2_supported = bool(page.evaluate("(() => { const c=document.createElement('canvas'); const gl=c.getContext('webgl2'); if (gl) { const ext=gl.getExtension('WEBGL_lose_context'); if (ext) ext.loseContext(); } return !!gl; })()"))
            deadline = time.monotonic() + timeout_seconds
            while time.monotonic() < deadline:
                if asset_responses[".wasm"] and asset_responses[".pck"]:
                    break
                page.wait_for_timeout(250)
            page.wait_for_timeout(1500)
            page_title = page.title()
            canvas_info = page.locator("canvas").first.evaluate(
                "el => ({width: el.width, height: el.height, clientWidth: el.clientWidth, clientHeight: el.clientHeight, visible: !!(el.offsetWidth || el.offsetHeight)})"
            )
            if screenshot_path:
                screenshot_path.parent.mkdir(parents=True, exist_ok=True)
                page.screenshot(path=str(screenshot_path), full_page=False)
                screenshot_result = str(screenshot_path)

            # Exercise the actual exported canvas after startup at desktop, portrait,
            # landscape, and tablet viewport sizes. This checks resize wiring in the
            # real Web build; it does not replace manual touch/Safari acceptance.
            for width, height in ((1280, 800), (390, 844), (844, 390), (768, 1024)):
                page.set_viewport_size({"width": width, "height": height})
                page.wait_for_timeout(350)
                resized_info = page.locator("canvas").first.evaluate(
                    "el => ({width: el.width, height: el.height, clientWidth: el.clientWidth, clientHeight: el.clientHeight, visible: !!(el.offsetWidth || el.offsetHeight)})"
                )
                width_ok = float(resized_info.get("clientWidth", 0)) >= width * 0.75
                height_ok = float(resized_info.get("clientHeight", 0)) >= height * 0.75
                viewport_results.append({
                    "viewport": {"width": width, "height": height},
                    "passed": bool(resized_info.get("visible")) and width_ok and height_ok,
                    "canvas": resized_info,
                })
            page.set_viewport_size({"width": 1280, "height": 800})
            page.wait_for_timeout(150)
        except Exception as exc:  # include browser navigation/selector errors in durable report
            startup_error = f"{type(exc).__name__}: {exc}"
        finally:
            context.close()
            browser.close()

    checks: list[dict[str, Any]] = []
    checks.append({"name": "HTML entry page responds successfully", "passed": response_status is not None and 200 <= response_status < 400, "detail": str(response_status)})
    checks.append({"name": "visible canvas has a non-zero size", "passed": bool(canvas_info and canvas_info.get("visible") and canvas_info.get("clientWidth", 0) > 10 and canvas_info.get("clientHeight", 0) > 10), "detail": str(canvas_info)})
    checks.append({"name": "browser supports WebGL 2", "passed": webgl2_supported, "detail": "WebGL 2 context available" if webgl2_supported else "WebGL 2 context unavailable"})
    for suffix in (".js", ".wasm", ".pck"):
        rows = asset_responses[suffix]
        successful = any(200 <= int(row["status"]) < 300 for row in rows)
        checks.append({"name": f"runtime asset {suffix} loads", "passed": successful, "detail": json.dumps(rows, ensure_ascii=False) if rows else "no response captured"})
    wasm_rows = asset_responses[".wasm"]
    wasm_mime_ok = any("application/wasm" in str(row.get("content_type", "")).lower() for row in wasm_rows)
    checks.append({
        "name": "WASM response uses application/wasm MIME type",
        "passed": wasm_mime_ok,
        "detail": json.dumps([{"url": row["url"], "content_type": row["content_type"]} for row in wasm_rows], ensure_ascii=False) if wasm_rows else "no WASM response captured",
    })
    checks.append({"name": "no uncaught JavaScript page errors", "passed": not page_errors, "detail": page_errors or "none"})
    checks.append({"name": "no browser console errors", "passed": not console_errors, "detail": console_errors or "none"})
    relevant_failed = [item for item in failed_requests if any(ext in item.lower().split("?", 1)[0] for ext in (".js", ".wasm", ".pck"))]
    checks.append({"name": "no failed JS/WASM/PCK requests", "passed": not relevant_failed, "detail": relevant_failed or "none"})
    checks.append({
        "name": "canvas adapts to desktop, portrait, landscape, and tablet viewports",
        "passed": len(viewport_results) == 4 and all(bool(item.get("passed")) for item in viewport_results),
        "detail": json.dumps(viewport_results, ensure_ascii=False),
    })
    if startup_error:
        checks.append({"name": "browser navigation completed", "passed": False, "detail": startup_error})
    else:
        checks.append({"name": "browser navigation completed", "passed": True, "detail": f"title={page_title!r}"})

    failures = [item for item in checks if not item["passed"]]
    return {
        "project": "Abyss Loop",
        "checked_utc": datetime.now(timezone.utc).isoformat(),
        "url": url,
        "result": "FAIL" if failures else "PASS",
        "scope": "Chromium Web smoke only; no gameplay or save/load acceptance implied",
        "response_status": response_status,
        "page_title": page_title,
        "canvas": canvas_info,
        "viewport_results": viewport_results,
        "webgl2_supported": webgl2_supported,
        "runtime_asset_responses": asset_responses,
        "console_errors": console_errors,
        "page_errors": page_errors,
        "failed_requests": failed_requests,
        "screenshot": screenshot_result,
        "checks": checks,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--directory", type=Path, help="Folder containing an exported index.html plus .js/.wasm/.pck files")
    target.add_argument("--url", help="Published or local HTTP(S) URL to test")
    target.add_argument("--self-test", action="store_true", help="Run the harness against a temporary synthetic Web fixture; does not test Godot")
    parser.add_argument("--timeout", type=int, default=60, help="Seconds to wait for the WASM and PCK downloads")
    parser.add_argument("--screenshot", type=Path, help="Where to save a screenshot of the initial canvas")
    parser.add_argument("--report", type=Path, help="Where to save JSON results")
    args = parser.parse_args()
    if args.timeout < 5 or args.timeout > 300:
        parser.error("--timeout must be between 5 and 300 seconds")

    server = None
    temp_context = None
    target_url = args.url
    try:
        if args.self_test:
            temp_context = tempfile.TemporaryDirectory(prefix="abyssloop-web-smoke-selftest-")
            fixture = Path(temp_context.name)
            _self_test_fixture(fixture)
            server, _, base_url = _start_server(fixture)
            target_url = base_url
        elif args.directory:
            directory = args.directory.expanduser().resolve()
            build_failures = [c for c in build_checks(directory) if c.status == "FAIL"]
            if build_failures:
                for item in build_failures:
                    print(f"FAIL: {item.name} — {item.detail}", file=sys.stderr)
                return 2
            server, _, base_url = _start_server(directory)
            target_url = base_url

        assert target_url
        result = _run_browser(target_url, args.timeout, args.screenshot)
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        for check in result["checks"]:
            print(f"{'PASS' if check['passed'] else 'FAIL'}: {check['name']} — {check['detail']}")
        print(f"\nWEB BROWSER SMOKE: {result['result']}")
        if args.self_test:
            print("NOTE: synthetic fixture only; Godot export/runtime was not tested.")
        return 0 if result["result"] == "PASS" else 1
    except (OSError, RuntimeError) as exc:
        print(f"WEB BROWSER SMOKE COULD NOT RUN: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    finally:
        if server:
            server.shutdown()
            server.server_close()
        if temp_context:
            temp_context.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())

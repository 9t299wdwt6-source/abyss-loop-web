# Stage 91 — запись о блокировке Chromium smoke test

- Checked at: `2026-10-25T05:53:13Z`
- Test harness: `tools/web_browser_smoke_test.py`
- Target: a local extraction of the last available GitHub Pages artifact, which predates Stage 90.
- Result: `FAIL TO START`, not an application test result.

The browser automation failed at navigation to the temporary loopback server before HTTP navigation completed:

```text
Error: Page.goto: net::ERR_BLOCKED_BY_ADMINISTRATOR at http://127.0.0.1:41821/
```

Observed details:

- HTML response status: none.
- Canvas: not created/observed.
- JS/WASM/PCK response events: none.
- Screenshot: not captured.
- No application JavaScript or console errors were observed because the page did not load.

Interpretation: all assertions that depend on the page loaded are untested. This does not indicate a game code defect and must not be counted as browser PASS. The tested artifact is also older than Stage 90, so even a successful run would not prove Stage 90 acceptance.

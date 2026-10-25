# Stage 91 — runtime/browser acceptance attempt

**Project:** Abyss Loop 0.61.0  
**Candidate base:** Stage 90 — Discovery Readability  
**Checked:** 2026-10-25  
**Status:** STATIC PASS / RUNTIME BLOCKED — NOT RUNTIME-ACCEPTED

## What was checked

1. The complete Python static/regression suite was run from this exact Stage 90 source tree: **117/117 PASS**.
2. Web source preflight: **8/8 non-failing, 0 failures, 1 warning**. The warning concerns a debug-only clipboard call and must remain release-inaccessible.
3. Independent release preflight for version `0.61.0`: **7/7 PASS**.
4. The real runtime gate was invoked with `--godot godot`. The final runtime-gate attempt reran the current static suite at 117/117 PASS and independent release preflight at 7/7 PASS, then correctly failed closed at the engine-version gate because no `godot` executable is installed. No runtime-tested archive was created. No runtime-tested archive was created.
5. The browser smoke test was attempted against a locally extracted copy of the last available GitHub Pages artifact. Chromium rejected navigation to the temporary local test server with `net::ERR_BLOCKED_BY_ADMINISTRATOR` before the page loaded. Therefore no JS/WASM/PCK, WebGL, screenshot, pointer or touch result was obtained from that attempt.
6. A Godot 4.7.2 download attempt was blocked before an HTTP request could be made because this environment could not resolve `downloads.godotengine.org` (`curl: (6) Could not resolve host`).

## Important version boundary

The previously successful GitHub Actions/browser run `40073910109` belongs to the older source commit `2ab5a8ac2ff4c4692437b29a3538607645d8f9f4`, not to the Stage 90 candidate in this archive. It is historical evidence only and is not counted as Stage 90 acceptance.

The newest readable default-branch run during this check, `40084067929` at commit `704663e80a74d2e175fbcdbb8af25fa5ba85d5fd`, failed in an older 12-loop long-expedition acceptance before Web export/browser tests. The log shows save-integrity rejections during victory/settlement and 8/55 long-run assertions failing. That project revision predates the Stage 90 archive, so the failure is recorded for follow-up but was not patched into this candidate blindly.

## Verdict

- Static/source contracts: **PASS**.
- Source-level Web readiness: **PASS WITH WARNING**.
- Runtime GDScript compile/import: **BLOCKED — not executed**.
- Godot gameplay acceptance for Stage 90: **NOT RUN**.
- Stage 90 Web export: **NOT BUILT in this environment**.
- Browser runtime/gameplay acceptance for Stage 90: **BLOCKED — not executed**.
- Desktop/mobile screenshots from the Stage 90 candidate: **NOT CAPTURED**.

Do not label this archive runtime-tested and do not treat the published older Web version as a test of Stage 90. To close Stage 91, the exact source in this archive must be synchronized to the CI checkout; then the Godot 4.7.2 import, gameplay/save acceptance, Web export, Chromium smoke and browser gameplay acceptance jobs must pass against that same source revision. Only then should the deployment artifact be used as the new current Web version.

# Stage 91 — карта: Godot и браузерная приёмка

**Candidate:** Stage 90 source, Abyss Loop 0.61.0.  
**Runtime status:** NOT ACCEPTED. Python checks are not a substitute for engine execution.

## Godot 4.7.2

- [ ] Exact candidate source is present in the CI checkout and source fingerprint matches this package.
- [ ] `project.godot` imports in a clean isolated profile without parse/resource errors.
- [ ] Main scene starts without errors.
- [ ] `res://tests/expedition_runtime_acceptance_runner.tscn` passes.
- [ ] Seeded contour remains a connected loop of exactly 34 unique orthogonally adjacent road cells.
- [ ] Initial/revealed discovery mask contains valid off-road modern IDs only.
- [ ] Allowed and disallowed placement preview agrees with actual placement; invalid actions do not spend cards.
- [ ] Save/reload restores route seed, discovery mask, road tiles and landscape tiles exactly.
- [ ] Snapshot missing Stage 88 discovery data migrates with the expected safe compatibility behavior.

## Web/Chromium

- [ ] Export a fresh Web build from that exact commit using Godot 4.7.2.
- [ ] JS/WASM/PCK requests succeed; WASM MIME is `application/wasm`; no uncaught JS or console errors.
- [ ] Capture screenshots at 1280×800, 768×1024, 844×390 and 390×844.
- [ ] Launch tutorial → shelter → expedition with pointer input.
- [ ] Check hover/click selection of road, discovered landscape, unknown cell and invalid target.
- [ ] Place a legal tile, reload browser and resume the same expedition with matching route seed, discovery mask and tile placement.
- [ ] Repeat essential placement flows using touch emulation; physical iPhone Safari remains separate acceptance.

## Current attempt

- [x] Static suite: 116/116 PASS.
- [x] Web source preflight: 8/8 non-failing, one warning.
- [x] Independent release preflight: 7/7 PASS.
- [x] Run the fail-closed runtime gate; it records failure because Godot is unavailable.
- [x] Attempt local Chromium smoke against the previously deployed artifact.
- [ ] Current-candidate Godot/runtime/browser checks: blocked by environment; not passed.

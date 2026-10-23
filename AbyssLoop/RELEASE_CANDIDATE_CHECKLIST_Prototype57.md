# Abyss Loop — release-candidate checklist, Prototype 57 RC3

Prototype 57.0 is a **release candidate**, not a final 1.0 release. Source preflight and Python tests do not substitute for Godot 4.7.2 runtime testing.

## Source and documentation consistency

- [ ] Project metadata says `0.57.0`; stable application name remains `Abyss Loop`.
- [ ] README, build report, manifest, roadmap, checklist, packager and Windows output filenames agree on RC3.
- [ ] `tools/release_preflight.py --expected-version 0.57.0` passes.
- [ ] Static report is complete and all discovered checks passed.

## Artifact integrity

- [ ] ZIP contains exactly one root folder named `AbyssLoop/`.
- [ ] ZIP CRC passes and member names exactly match the filtered source tree.
- [ ] Packaged bytes match the current source bytes.
- [ ] No symlinks, `.env*`, credentials/tokens/private keys, logs, editor caches, Python bytecode, temporary backups or nested archives are included.
- [ ] Two candidate ZIPs built from the same source tree have an identical SHA-256.
- [ ] Runtime-tested packaging is rejected without a current, matching runtime report.

## Required automated Windows runtime gates

- [ ] Godot 4.7.2 stable is detected exactly.
- [ ] Editor/import preflight passes in an isolated temporary project.
- [ ] Clean main-scene launch passes.
- [ ] Gameplay smoke passes.
- [ ] Save-system regression passes.
- [ ] Expedition integration audit passes.
- [ ] Source fingerprint remains current through validation and final packaging.

## Required human acceptance

- [ ] Start a new profile and load an existing profile from the previous confirmed build.
- [ ] Complete one expedition with an event, tile placement, combat and return.
- [ ] Complete one defeat path and verify retained resources/history.
- [ ] Close/reopen and resume a saved expedition; verify no duplicate payout after retry.
- [ ] Check shelter scrolling, route/landscape separation, equipment text wrapping, tile-card copy indicators, settings and event/tutorial dialogs at 1440×900 and 1920×1080.
- [ ] Check localization keys and visible strings for clipping/overflow.
- [ ] Confirm no unexpected errors or GDScript parse warnings in Godot 4.7.2.

## Release decision

Do not promote to 1.0 based only on static tests. If any gate fails, retain the complete log, fix in a separate hotfix build and repeat all gates. Previous ZIP files must remain unchanged.

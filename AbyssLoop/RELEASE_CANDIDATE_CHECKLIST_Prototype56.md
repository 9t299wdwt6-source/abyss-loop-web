# Abyss Loop — release-candidate checklist, Prototype 56 RC2

Prototype 56.0 is a **release candidate**, not a final 1.0 release. It may be shared for review, but must not be described as runtime-verified unless the packaged `tests/reports/RUNTIME_GATE_REPORT_RU.md` matches the exact source fingerprint and reports Godot 4.7.2 with every automated runtime gate passing.

## Artifact and source integrity

- [ ] Project metadata says `0.56.0`; stable application name remains `Abyss Loop`.
- [ ] ZIP contains exactly one root folder named `AbyssLoop/`.
- [ ] ZIP CRC passes and every packaged file is expected.
- [ ] No symlinks, `.env*`, credentials/tokens/private keys, logs, editor caches, Python bytecode, temp/backup files or nested archives are included.
- [ ] Two candidate ZIPs built from the same source tree have an identical SHA-256.
- [ ] Runtime report is not included in RC2 unless it is produced by the actual release gate; runtime-tested packaging requires a current report.

## Required automated Windows runtime gates

- [ ] Godot 4.7.2 stable (не RC/dev build) detected exactly.
- [ ] Editor/import preflight passes in an isolated temporary project.
- [ ] Clean main-scene launch passes.
- [ ] Gameplay smoke passes.
- [ ] Save-system regression passes.
- [ ] Expedition integration audit passes.
- [ ] Source fingerprint remains the same through report validation and runtime-tested packaging.

## Required human acceptance

- [ ] Start a new profile and load an existing profile from the previous confirmed build.
- [ ] Complete one expedition with an event, tile placement, combat and return.
- [ ] Complete one defeat path and verify the retained resources/history.
- [ ] Close/reopen and resume a saved expedition; verify no duplicate payout after retry.
- [ ] Check shelter scrolling, route/landscape separation, equipment text wrapping, tile-card copy indicators and event/tutorial dialogs at 1440×900 and 1920×1080.
- [ ] Check localization keys are all present and visible strings have no clipping/overflow.
- [ ] Confirm no unexpected output errors or GDScript parse warnings in Godot 4.7.2.

## Release decision

Do not promote to 1.0 solely on the basis of static tests. If any gate fails, save the full output, fix the defect in a separate hotfix build and rerun the whole suite. Keep every previous ZIP unchanged.

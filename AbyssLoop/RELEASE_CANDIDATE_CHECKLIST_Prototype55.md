# Abyss Loop — release-candidate checklist, Prototype 55

## Purpose and status
Prototype 55 is a **release candidate**, not a final 1.0 release. It may be shared for review, but must not be described as runtime-verified unless the packaged `tests/reports/RUNTIME_GATE_REPORT_RU.md` matches the exact source fingerprint and reports Godot 4.7.2 with every automated runtime gate passing.

The absence of `RUNTIME_GATE_REPORT_RU.md` means runtime is unverified. A failed or stale report also means the archive is not runtime-verified.

## Release hygiene
- [ ] Project is extracted to a clean folder from the chosen source archive.
- [ ] Application identity remains `Abyss Loop`; only the version changes.
- [ ] Project metadata says `0.55.0`.
- [ ] Static regression suite passes in full.
- [ ] Release candidate can be built twice with byte-identical ZIP hashes from the same source tree.
- [ ] Archive has one top-level folder named `AbyssLoop/` only.
- [ ] No `.godot/`, `.git/`, `__pycache__/`, compiled Python files, temporary files, backup files, local saves or nested ZIP files are present.
- [ ] ZIP can be tested/extracted without CRC errors.
- [ ] Release manifest, README, changelog, system requirements and launch instructions are included.
- [ ] Historical prototype ZIPs are not overwritten.

## Required automated Windows runtime gates
Run `RUN_RELEASE_GATE_WINDOWS.bat` using Godot 4.7.2 stable on Windows. The process must pass all seven steps: static suite, exact Godot version check, editor/import preflight in an isolated copy, clean main-scene launch, gameplay smoke, save-system regression, and expedition integration audit. The gate must generate a source-fingerprinted report and then package the exact matching source tree.

QA tests use a temporary copy and a distinct project identity. They must not alter the user's actual save profile.

## Required human acceptance
- [ ] Open the extracted archive in Godot 4.7.2 and ensure there are no parse/resource errors.
- [ ] Start a new expedition; pause/resume, change time speed, trigger an event, choose an option, interact with tactical tiles, and return to base.
- [ ] Save, close/reopen the project, and continue an existing expedition.
- [ ] Check one combat encounter, equipment/loot, research and post-expedition rewards.
- [ ] Verify settings and accessibility changes remain after restart.
- [ ] Check the UI at 1440×900 and one smaller window size; inspect scrolling, focus, labels and event modal text.
- [ ] Confirm no unexpected errors or warnings in the Godot Output/Debugger panels.
- [ ] Record results, screenshots and any defects before calling the build accepted.

## Release decision
Do not call this version 1.0 until the Godot runtime gates and manual acceptance above have actually passed on the target Windows/Godot version. If a blocker is found, fix it, increment the build/hotfix version, rerun the full suite and package a new archive.

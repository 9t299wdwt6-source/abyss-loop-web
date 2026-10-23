#!/usr/bin/env python3
"""Source/build preflight for Abyss Loop's Godot Web export.

This does not compile GDScript. Source mode verifies the export configuration;
build mode verifies the shape and size of a real Godot Web export directory.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import re
import sys


@dataclass(frozen=True)
class Check:
    name: str
    status: str
    detail: str


def _check(name: str, condition: bool, success: str, failure: str) -> Check:
    return Check(name, "PASS" if condition else "FAIL", success if condition else failure)


def source_checks(root: Path) -> list[Check]:
    root = root.resolve()
    checks: list[Check] = []
    project_path = root / "project.godot"
    main_scene = root / "scenes" / "main.tscn"
    project = project_path.read_text(encoding="utf-8") if project_path.is_file() else ""
    checks.append(_check(
        "Godot project and main scene exist",
        project_path.is_file() and main_scene.is_file(),
        "project.godot and scenes/main.tscn are present",
        "project.godot or scenes/main.tscn is missing",
    ))

    renderer_ok = (
        'renderer/rendering_method="gl_compatibility"' in project
        and 'renderer/rendering_method.mobile="gl_compatibility"' in project
    )
    checks.append(_check(
        "Web-compatible Compatibility renderer",
        renderer_ok,
        "both default and mobile renderers use GL Compatibility",
        "Godot 4 Web supports the Compatibility renderer; configure both renderer settings",
    ))

    code_files = [p for p in root.rglob("*") if p.is_file() and ".godot" not in p.parts]
    csharp_files = [p.relative_to(root).as_posix() for p in code_files if p.suffix.lower() in {".cs", ".csproj", ".sln"}]
    checks.append(_check(
        "No C# project code",
        not csharp_files,
        "no C# project files found; this project is GDScript-based",
        "Godot 4 does not export C# projects to Web: " + ", ".join(csharp_files[:8]),
    ))

    preset_path = root / "export_presets.cfg"
    preset = preset_path.read_text(encoding="utf-8") if preset_path.is_file() else ""
    preset_ok = all(token in preset for token in (
        'name="Web"', 'platform="Web"', 'variant/thread_support=false',
        'variant/extensions_support=false', 'html/canvas_resize_policy=2',
        'html/focus_canvas_on_start=true', 'html/experimental_virtual_keyboard=true',
    ))
    no_threads = 'variant/thread_support=false' in preset
    checks.append(_check(
        "Web export preset is configured for portable hosting",
        preset_ok and no_threads,
        "Web preset exists, disables thread/extension support, resizes to browser, and enables mobile virtual keyboard",
        "export_presets.cfg is missing required Web options or thread support is enabled",
    ))

    native_suffixes = {".gdextension", ".dll", ".so", ".dylib"}
    native_files = [p.relative_to(root).as_posix() for p in code_files if p.suffix.lower() in native_suffixes]
    checks.append(_check(
        "No native extension binaries required by Web export",
        not native_files,
        "no GDExtension descriptors or native binaries found",
        "native extensions need a Web-specific build and Extension Support; found: " + ", ".join(native_files[:8]),
    ))

    save_system = root / "scripts" / "core" / "save_system.gd"
    save_text = save_system.read_text(encoding="utf-8") if save_system.is_file() else ""
    user_storage_ok = "user://" in save_text and "loop_roguelite_save.json" in save_text
    checks.append(_check(
        "Save system targets user data storage",
        user_storage_ok,
        "save paths use user://, allowing Godot to apply its platform-specific user-data storage",
        "expected user:// save path not found in scripts/core/save_system.gd",
    ))

    ui_path = root / "scripts" / "ui" / "ui_controller.gd"
    ui_text = ui_path.read_text(encoding="utf-8") if ui_path.is_file() else ""
    clipboard_call = "DisplayServer.clipboard_set(" in ui_text
    guarded_clipboard = (
        "func _copy_developer_report()" in ui_text
        and "if not OS.is_debug_build():" in ui_text
        and clipboard_call
    )
    if clipboard_call and guarded_clipboard:
        checks.append(Check(
            "Platform-specific clipboard call is gated",
            "WARN",
            "clipboard API is inside a debug-only diagnostics action; confirm debug actions remain unavailable in release Web export",
        ))
    else:
        checks.append(_check(
            "Platform-specific clipboard call is gated",
            not clipboard_call,
            "no DisplayServer clipboard call found",
            "DisplayServer.clipboard_set is present and its debug-only guard could not be confirmed",
        ))

    return checks


def build_checks(root: Path) -> list[Check]:
    root = root.resolve()
    checks: list[Check] = []
    entry = root / "index.html"
    checks.append(_check(
        "Web entry point exists",
        entry.is_file() and entry.stat().st_size > 0,
        "index.html exists and is non-empty",
        "index.html is missing or empty; export filename must be index.html",
    ))

    required_suffixes = (".js", ".wasm", ".pck")
    stem = entry.stem
    for suffix in required_suffixes:
        candidate = root / f"{stem}{suffix}"
        checks.append(_check(
            f"Web runtime asset {candidate.name} exists",
            candidate.is_file() and candidate.stat().st_size > 0,
            f"{candidate.name}: {candidate.stat().st_size:,} bytes" if candidate.is_file() else "",
            f"{candidate.name} is missing or empty; do not rename files independently of index.html",
        ))

    files = [p for p in root.rglob("*") if p.is_file()]
    total_bytes = sum(p.stat().st_size for p in files)
    long_names = [p.relative_to(root).as_posix() for p in files if len(p.relative_to(root).as_posix()) > 240]
    size_ok = len(files) <= 1000 and total_bytes <= 500 * 1024 * 1024 and not long_names
    detail = f"{len(files)} files; {total_bytes:,} bytes extracted"
    if long_names:
        detail += "; paths over 240 chars: " + ", ".join(long_names[:3])
    checks.append(_check(
        "Browser-hosting package stays within common itch.io limits",
        size_ok,
        detail,
        detail + " (limits: <=1,000 files, <=500 MB total, <=240 chars per path)",
    ))
    return checks


def render_report(mode: str, root: Path, checks: list[Check]) -> str:
    failures = [c for c in checks if c.status == "FAIL"]
    warnings = [c for c in checks if c.status == "WARN"]
    result = "FAIL" if failures else ("READY WITH WARNINGS" if warnings else "PASS")
    lines = [
        "# Abyss Loop — Web Export Preflight",
        "",
        f"- Mode: `{mode}`",
        f"- Root: `{root.name}/`" + (" (export output directory)" if mode == "build" else " (project root)"),
        f"- Checked (UTC): `{datetime.now(timezone.utc).isoformat()}`",
        f"- Result: **{result}**",
        f"- Checks: {len(checks) - len(failures)}/{len(checks)} non-failing; {len(warnings)} warning(s); {len(failures)} failure(s)",
        "",
        "| Status | Check | Detail |",
        "|---|---|---|",
    ]
    for item in checks:
        detail = item.detail.replace("|", "\\|").replace("\n", " ")
        lines.append(f"| {item.status} | {item.name} | {detail} |")
    lines += ["", "Source-mode checks do not compile GDScript. Build-mode checks do not replace browser runtime testing.", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("source", "build"), default="source")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1], help="Godot project root in source mode; exported output directory in build mode")
    parser.add_argument("--report", type=Path, help="Optional Markdown report output path")
    args = parser.parse_args()
    checks = source_checks(args.root) if args.mode == "source" else build_checks(args.root)
    report = render_report(args.mode, args.root, checks)
    print(report)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(report, encoding="utf-8")
    failures = [item for item in checks if item.status == "FAIL"]
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())

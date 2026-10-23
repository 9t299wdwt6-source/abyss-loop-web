"""Shared file filters and deterministic fingerprinting for Abyss Loop release gates.

Only regular, project-owned files are allowed into a release candidate. In
particular, local secrets and symlinks are excluded/rejected so an archive can
never silently pull content from outside its source tree.
"""
from __future__ import annotations
import hashlib
from pathlib import Path

SKIP_DIRS = {".git", ".godot", "__pycache__", ".venv", "venv", "node_modules", "__MACOSX"}
SKIP_FILES = {
    ".DS_Store", "Thumbs.db", ".env", "credentials.json", "secrets.json",
    "token.json", "service-account.json", "id_rsa", "id_ed25519", "id_ecdsa",
}
SKIP_SUFFIXES = {
    ".pyc", ".pyo", ".zip", ".tmp", ".bak", ".log", ".swp", ".swo",
    ".orig", ".pem", ".key", ".p12", ".pfx",
}
VOLATILE_REPORTS = {
    "tests/reports/STATIC_TEST_REPORT.txt",
    "tests/reports/RUNTIME_GATE_REPORT_RU.md",
    "tests/reports/RUNTIME_GATE_FAILURE_REPORT_RU.md",
}


def _is_local_or_sensitive_artifact(path: Path) -> bool:
    name = path.name.lower()
    suffix = path.suffix.lower()
    if name in {value.lower() for value in SKIP_FILES} or suffix in SKIP_SUFFIXES:
        return True
    # Include .env.local, .env.production, and similar variants. Avoid broad
    # substring matching which could hide legitimate game content.
    if name == ".env" or name.startswith(".env."):
        return True
    # Editor backup and crash-dump variants often contain local paths or data.
    if name.endswith("~") or name.endswith(".crash"):
        return True
    return False


def iter_project_files(root: Path, *, include_runtime_report: bool = True) -> list[Path]:
    """Return stable release members; reject symlinks anywhere in the tree.

    Rejecting links, rather than silently following them, prevents accidental
    inclusion of files outside the project tree and keeps archive builds portable.
    """
    root = root.resolve()
    output: list[Path] = []
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        rel_posix = relative.as_posix()
        if path.is_symlink():
            raise ValueError(f"symbolic links are not allowed in a release tree: {rel_posix}")
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in relative.parts):
            continue
        if _is_local_or_sensitive_artifact(path):
            continue
        if rel_posix in VOLATILE_REPORTS and rel_posix != "tests/reports/RUNTIME_GATE_REPORT_RU.md":
            continue
        if not include_runtime_report and rel_posix == "tests/reports/RUNTIME_GATE_REPORT_RU.md":
            continue
        output.append(path)
    return output


def project_fingerprint(root: Path) -> str:
    """Hash package source contents while ignoring caches and volatile reports."""
    digest = hashlib.sha256()
    for path in iter_project_files(root, include_runtime_report=False):
        relative = path.relative_to(root.resolve()).as_posix().encode("utf-8")
        digest.update(relative)
        digest.update(b"\0")
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        digest.update(b"\0")
    return digest.hexdigest()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

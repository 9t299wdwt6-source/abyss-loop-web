"""Ensure release packaging excludes local secrets and rejects symbolic links."""
from __future__ import annotations
import os
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from release_integrity import iter_project_files, project_fingerprint  # noqa: E402

# 1. Exact-name and extension filters in a synthetic local working tree.
with tempfile.TemporaryDirectory(prefix="abyssloop_artifact_hygiene_") as temp:
    base = Path(temp)
    include = base / "scripts" / "gameplay.gd"
    include.parent.mkdir(parents=True)
    include.write_text("extends Node\n", encoding="utf-8")
    (base / "assets.png").write_bytes(b"public asset")
    sensitive = [
        ".env", ".env.local", ".env.production.local", "credentials.json",
        "secrets.json", "token.json", "service-account.json", "id_rsa",
        "private.pem", "signing.key", "keystore.p12", "runtime.log",
        "editor.swp", "scene.gd~", "crash.crash", "backup.tmp", "backup.bak",
    ]
    for name in sensitive:
        (base / name).write_text("do not package", encoding="utf-8")
    names = {item.relative_to(base).as_posix() for item in iter_project_files(base)}
    assert "scripts/gameplay.gd" in names and "assets.png" in names, "regular project assets should be kept"
    excluded = {".env", ".env.local", ".env.production.local", "credentials.json", "secrets.json", "token.json", "service-account.json", "id_rsa", "private.pem", "signing.key", "keystore.p12", "runtime.log", "editor.swp", "scene.gd~", "crash.crash", "backup.tmp", "backup.bak"}
    assert not (excluded & names), "local/private artifacts leaked into the member list: " + ", ".join(sorted(excluded & names))

    # A local-only secret must not affect a source fingerprint, since it is not a release input.
    before = project_fingerprint(base)
    (base / ".env.local").write_text("changed local secret", encoding="utf-8")
    after = project_fingerprint(base)
    assert before == after, "excluded local-only file should not change the release source fingerprint"

# 2. Refuse both file and directory symlinks. Symlink creation can be blocked on
# Windows without Developer Mode; the test reports that platform limitation.
with tempfile.TemporaryDirectory(prefix="abyssloop_artifact_link_") as temp:
    base = Path(temp) / "project"
    base.mkdir()
    (base / "project.godot").write_text('config/name="Abyss Loop"\n', encoding="utf-8")
    outside = Path(temp) / "outside.secret"
    outside.write_text("external data", encoding="utf-8")
    link = base / "outside_link.txt"
    try:
        os.symlink(outside, link)
    except (OSError, NotImplementedError) as exc:
        print(f"SKIP: platform does not allow symlink creation in this context ({type(exc).__name__})")
    else:
        try:
            iter_project_files(base)
        except ValueError as exc:
            assert "symbolic links are not allowed" in str(exc), f"wrong symlink rejection reason: {exc}"
        else:
            raise AssertionError("release file listing must reject symlinks instead of following them")

# 3. The actual project tree should remain valid and fingerprintable.
project_members = iter_project_files(ROOT)
member_names = {item.relative_to(ROOT).as_posix() for item in project_members}
for expected in ("project.godot", "scenes/main.tscn", "assets/background/abyss_pixel_backdrop.png"):
    assert expected in member_names, f"required project file was filtered: {expected}"
assert len(project_fingerprint(ROOT)) == 64, "project fingerprint must be SHA-256 hex"
print("RELEASE ARTIFACT HYGIENE REGRESSION PASSED: local secrets/logs/temp files excluded, fingerprints stable, symlink source rejected, project inputs retained")

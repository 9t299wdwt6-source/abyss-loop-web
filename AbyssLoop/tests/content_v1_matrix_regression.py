"""Stage 49: audit the authored v1.0 content set and guard stable IDs.

This parses only literal const dictionaries/lists from GDScript source. It does not
pretend to compile GDScript or validate visuals in Godot; those remain runtime gates.
"""
from __future__ import annotations
import ast
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from content_v1_audit import build_audit, read_catalogs, stable_ids_snapshot, validate_catalogs, write_readiness_report

catalogs = read_catalogs(ROOT)
issues = validate_catalogs(catalogs)
manifest_path = ROOT / "tests/fixtures/content_v1_stable_ids.json"
assert manifest_path.is_file(), "stable content ID manifest is missing"
expected_ids = json.loads(manifest_path.read_text(encoding="utf-8"))
actual_ids = stable_ids_snapshot(catalogs)
assert expected_ids == actual_ids, "stable content IDs changed without updating the reviewed manifest/migration:\n" + "\n".join(
    f"{key}: expected {expected_ids.get(key, [])}, actual {actual_ids.get(key, [])}"
    for key in sorted(set(expected_ids) | set(actual_ids)) if expected_ids.get(key, []) != actual_ids.get(key, [])
)
assert not issues, "v1.0 content registry audit failed:\n" + "\n".join(f"- {issue}" for issue in issues)
report = ROOT / "tests/reports/CONTENT_V1_READINESS_MATRIX_RU.md"
write_readiness_report(ROOT, catalogs, report)
summary = build_audit(catalogs)
print("CONTENT V1.0 MATRIX REGRESSION PASSED")
print(f"- Categories: {len(summary['categories'])}")
print(f"- Stable-ID content records: {sum(len(row['items']) for row in summary['categories'])}")
print(f"- Authored data checks: {summary['records_checked']}; issues: {len(issues)}")
print("- Stable IDs match the reviewed manifest")
print(f"- Readiness matrix: {report.relative_to(ROOT)}")
print("- Dedicated per-entity sprites and multi-language localization remain release-readiness tasks, not claimed as complete.")

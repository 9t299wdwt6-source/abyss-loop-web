"""Source-level regression guards for checksum-protected save envelopes.

These checks validate implementation wiring and deterministic canonicalization
fixtures, not GDScript execution; run save_system_regression.gd in Godot as well.
"""
from __future__ import annotations
import hashlib
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
runtime = (ROOT / "tests/save_system_regression.gd").read_text(encoding="utf-8")

checks = {
    "payload schema stays v3 while integrity envelope is v2": 'const SAVE_VERSION := 3' in save and 'const SAVE_ENVELOPE_VERSION := 2' in save and '"envelope_version": SAVE_ENVELOPE_VERSION' in save and '"integrity"' in save,
    "new save envelope declares SHA-256": '"algorithm": SAVE_INTEGRITY_ALGORITHM' in save and 'const SAVE_INTEGRITY_ALGORITHM := "sha256"' in save,
    "removing checksum cannot downgrade envelope v2 to legacy": 'if envelope_version >= 2 and not parsed.has("integrity"):' in save and 'envelope v2 without checksum must be rejected' in runtime,
    "canonical payload sorts dictionary keys recursively": "func _canonical_json(value: Variant) -> String:" in save and "keys.sort()" in save and "_canonical_json(entry)" in save,
    "Web JSON integer-to-float conversion is normalized before version/schema checks": "var parsed: Dictionary = _normalize_numeric_types(parsed_value)" in save and "func _normalize_numeric_types(value: Variant) -> Variant:" in save and "canonical JSON must normalize whole numbers" in runtime,
    "checksum is verified before migration and data validation": save.index('if parsed.has("integrity"):') < save.index('var data: Dictionary = data_value.duplicate(true)') < save.index('if not _validate_save_data(data):'),
    "unknown checksum algorithm is rejected": 'str(algorithm_value) != SAVE_INTEGRITY_ALGORITHM' in save,
    "invalid checksum length and mismatch are rejected": 'str(checksum_value).length() != 64' in save and 'var actual_checksum: String = _payload_checksum(checksum_data)' in save and 'integrity_checksum_mismatch_expected_%s_actual_%s' in save,
    "save decode reports stable rejection reasons with expected/actual digest prefixes": '_reject_decoded_save("integrity_checksum_mismatch_expected_%s_actual_%s"' in save and 'expedition_snapshot_invalid_v%d_status%d_telemetry%d' in save,
    "payload checksum uses the JSON roundtrip representation actually persisted": 'var encoded_payload := JSON.stringify(payload)' in save and 'var normalized_payload: Dictionary = _normalize_numeric_types(parsed_payload)' in save,
    "legacy envelopes without checksum remain readable": 'if parsed.has("integrity")' in save and "Version 1 stores permanent progress only" in save and "version < 3" in save,
    "primary and backup recovery use common checksum encoder": '_encode_save(backup_data)' in save and '_encode_save(candidate_data)' in save,
    "corrupt primary is quarantined and repaired from validated backup": 'recovered_backup_primary_restore_failed' in save and 'recovered_backup_quarantine_failed' in save and '_write_atomic_text(SAVE_PATH, SAVE_TEMP_PATH, recovered_text)' in save,
    "save, export and profile migration use common envelope encoder": 'var encoded := _encode_save(payload)' in save and '_encode_save(candidate_data)' in save,
    "runtime regression checks tamper detection and backup fallback": 'tampered_envelope["data"]["scrap"] = 999' in runtime and 'checksum mismatch should trigger validated backup recovery' in runtime and 'successful backup recovery should rewrite a valid primary envelope' in runtime,
    "runtime regression checks checksum key-order invariance": 'canonical checksum must ignore dictionary key insertion order' in runtime,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
assert not failed, "Save integrity regression failed: " + ", ".join(failed)

def canonical(value):
    if isinstance(value, dict):
        return "{" + ",".join(json.dumps(str(k), ensure_ascii=False) + ":" + canonical(value[k]) for k in sorted(value, key=lambda key: str(key))) + "}"
    if isinstance(value, list):
        return "[" + ",".join(canonical(item) for item in value) + "]"
    if isinstance(value, float) and math.isfinite(value):
        stable = struct.unpack("!f", struct.pack("!f", value))[0]
        if abs(stable) <= 9007199254740991 and stable.is_integer():
            return str(int(stable))
        if abs(stable) <= 1000000:
            return f"{stable:.7f}"
        return json.dumps(stable, ensure_ascii=False, separators=(",", ":"))
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))

left = {"scrap": 41, "settings": {"music": 0.7, "master": 0.8}, "saved_expedition": {}}
right = {"saved_expedition": {}, "settings": {"master": 0.8, "music": 0.7}, "scrap": 41}
left_hash = hashlib.sha256(canonical(left).encode("utf-8")).hexdigest()
right_hash = hashlib.sha256(canonical(right).encode("utf-8")).hexdigest()
assert left_hash == right_hash, "canonical JSON hash should be insensitive to key insertion order"
web_parsed = {"scrap": 41.0, "settings": {"music": 0.7, "master": 0.8}, "saved_expedition": {}}
assert canonical(left) == canonical(web_parsed), "Web-style integral-float parsing must preserve canonical payload bytes"
assert hashlib.sha256(canonical(web_parsed).encode("utf-8")).hexdigest() == left_hash, "Web-style numeric roundtrip must preserve payload checksum"
fractional = {"settings": {"music": 0.7, "effects": 0.85}}
web_fractional = {"settings": {"music": 0.699999988079071, "effects": 0.8500000238418579}}
assert canonical(fractional) == canonical(web_fractional), "single-precision Web fractions must share canonical JSON"
assert hashlib.sha256(canonical(fractional).encode("utf-8")).hexdigest() == hashlib.sha256(canonical(web_fractional).encode("utf-8")).hexdigest(), "fractional Web roundtrip must preserve save checksum"
changed = dict(right); changed["scrap"] = 42
changed_hash = hashlib.sha256(canonical(changed).encode("utf-8")).hexdigest()
assert changed_hash != left_hash, "payload mutation should change checksum"
print("PASS: independent canonical JSON fixtures are stable and payload-sensitive")
print(f"SAVE INTEGRITY SOURCE REGRESSION PASSED: {len(checks) + 2} assertions")
print("Source-level only; the GDScript runtime test must pass in Godot 4.7.2.")

#!/usr/bin/env bash
# Reproducible local Web export helper for Abyss Loop (Linux x86_64).
# Downloads the official Godot 4.7.2 stable binary and official export templates,
# verifies both SHA-256 digests, imports project resources, exports index.html,
# and checks the resulting Web artifact structure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="4.7.2"
OUTPUT_DIR="${1:-"$(dirname "$ROOT")/AbyssLoop_WebExport"}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/abyssloop-web-export.XXXXXX")"
GODOT_ZIP="$TMP_DIR/godot.zip"
TEMPLATES_TPZ="$TMP_DIR/export_templates.tpz"
GODOT_TEMPLATES="$HOME/.local/share/godot/export_templates/${VERSION}.stable"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  echo "ERROR: This helper supports Linux x86_64 only. Use README_WEB_RU.md for Windows/macOS GUI export." >&2
  exit 2
fi
for cmd in curl unzip sha256sum find; do
  command -v "$cmd" >/dev/null || { echo "ERROR: missing required command: $cmd" >&2; exit 2; }
done

printf '\n[1/5] Downloading official Godot %s stable binary...\n' "$VERSION"
curl --fail --location --silent --show-error --retry 3 \
  "https://downloads.godotengine.org/?version=${VERSION}&flavor=stable&slug=linux.x86_64.zip" \
  -o "$GODOT_ZIP"
printf '%s  %s\n' 'cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4' "$GODOT_ZIP" | sha256sum --check --status || {
  echo "ERROR: Godot binary archive SHA-256 mismatch." >&2; exit 3;
}
unzip -q "$GODOT_ZIP" -d "$TMP_DIR/godot-bin"
GODOT_BIN="$(find "$TMP_DIR/godot-bin" -type f -name "Godot_v${VERSION}-stable_linux.x86_64" -print -quit)"
[[ -n "$GODOT_BIN" ]] || { echo "ERROR: Godot executable missing in official archive." >&2; exit 3; }
chmod +x "$GODOT_BIN"
"$GODOT_BIN" --version

printf '\n[2/5] Downloading and verifying official export templates...\n'
curl --fail --location --silent --show-error --retry 3 \
  "https://downloads.godotengine.org/?version=${VERSION}&flavor=stable&slug=export_templates.tpz" \
  -o "$TEMPLATES_TPZ"
printf '%s  %s\n' 'f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011' "$TEMPLATES_TPZ" | sha256sum --check --status || {
  echo "ERROR: export templates SHA-256 mismatch." >&2; exit 3;
}
unzip -q "$TEMPLATES_TPZ" -d "$TMP_DIR/templates"
TEMPLATE_SOURCE="$(find "$TMP_DIR/templates" -type f -name 'web_release.zip' -print -quit | xargs -r dirname)"
[[ -n "$TEMPLATE_SOURCE" && -f "$TEMPLATE_SOURCE/web_release.zip" ]] || {
  echo "ERROR: Web release template missing in export-template archive." >&2; exit 3;
}
mkdir -p "$GODOT_TEMPLATES"
cp "$TEMPLATE_SOURCE"/* "$GODOT_TEMPLATES"/

printf '\n[3/5] Importing Godot resources...\n'
"$GODOT_BIN" --headless --editor --path "$ROOT" --import

printf '\n[4/5] Exporting Web build to %s...\n' "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
"$GODOT_BIN" --headless --path "$ROOT" --export-release "Web" "$OUTPUT_DIR/index.html"

printf '\n[5/5] Checking exported files...\n'
python3 "$ROOT/tools/web_export_preflight.py" --mode build --root "$OUTPUT_DIR" --report "$(dirname "$OUTPUT_DIR")/AbyssLoop_WebExport_preflight.md"
printf '\nWeb export created at: %s\n' "$OUTPUT_DIR"
printf 'To run browser smoke tests: python3 "%s/tools/web_browser_smoke_test.py" --directory "%s"\n' "$ROOT" "$OUTPUT_DIR"

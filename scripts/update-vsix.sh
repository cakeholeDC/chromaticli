#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTENSION_DIR="$ROOT_DIR/vscode-extension"
MANIFEST="$EXTENSION_DIR/package.json"

command -v jq >/dev/null 2>&1 || {
  printf 'update-vsix: jq is required\n' >&2
  exit 1
}
command -v npx >/dev/null 2>&1 || {
  printf 'update-vsix: npx is required (install Node.js and npm)\n' >&2
  exit 1
}

version="$(jq -er '
  .version
  | select(type == "string")
  | select(test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$"))
' "$MANIFEST")" || {
  printf 'update-vsix: package.json must contain a valid extension version\n' >&2
  exit 1
}

vsix_name="chromaticli-themes-$version.vsix"
vsix_path="$EXTENSION_DIR/$vsix_name"

printf 'Building %s\n' "$vsix_name"
(
  cd "$EXTENSION_DIR"
  npx --yes --package @vscode/vsce@3.6.2 vsce package \
    --no-dependencies --out "$vsix_path"
)

[[ -s "$vsix_path" ]] || {
  printf 'update-vsix: packager did not create %s\n' "$vsix_path" >&2
  exit 1
}

python3 "$ROOT_DIR/tests/verify-bundled-themes.py"
printf 'Updated %s\n' "$vsix_path"

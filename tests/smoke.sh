#!/usr/bin/env bash
# Non-TTY smoke checks for chromaticli. Runs in CI's `smoke` job; also
# runnable locally for a fast pre-commit sanity sweep:
#
#   ./tests/smoke.sh
#
# Covers what can be exercised without a real terminal: help/version/usage,
# `list` output, `set`/`unset` settings.json writes, exit codes for bad
# input. The hook + actual OSC emission belong in tests/SMOKE_TEST.md (the
# human walkthrough) since they require an interactive shell.

set -euo pipefail

# Resolve CHROMATICLI to an absolute path so subshell `cd`s don't break the
# invocation. Default to the repo-relative `./chromaticli` so the script can
# be run via `./tests/smoke.sh` from the repo root.
_default_cli="$(cd "$(dirname "$0")/.." && pwd)/chromaticli"
CHROMATICLI="${CHROMATICLI:-$_default_cli}"
PROJECT=$(mktemp -d)
trap 'rm -rf "$PROJECT"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "  ok  $*"; }

require() {
  command -v "$1" >/dev/null || fail "smoke.sh needs '$1' on PATH"
}

require jq
require "$CHROMATICLI"

echo "=== top-level help / version / usage ==="

"$CHROMATICLI" --version | grep -q "^chromaticli " || fail "--version output"
pass "--version prints semver-style line"

"$CHROMATICLI" --help > /dev/null || fail "--help exit"
pass "--help exits 0"

"$CHROMATICLI" -h > /dev/null || fail "-h exit"
pass "-h exits 0"

# Bare invocation should also print help and exit 0
"$CHROMATICLI" > /dev/null || fail "bare invocation exit"
pass "bare invocation exits 0 (prints help)"

# Unknown subcommand must exit 2 (usage error per Plan.md §8.10)
set +e
"$CHROMATICLI" nonexistent_subcmd 2>/dev/null
rc=$?
set -e
[[ $rc -eq 2 ]] || fail "unknown subcommand expected exit 2, got $rc"
pass "unknown subcommand exits 2"

echo ""
echo "=== list ==="

LIST_OUT=$("$CHROMATICLI" list)
echo "$LIST_OUT" | grep -q "monokai" || fail "list missing 'monokai'"
echo "$LIST_OUT" | grep -q "solarized-dark" || fail "list missing 'solarized-dark'"
echo "$LIST_OUT" | grep -q "Dark — warm" || fail "list missing 'Dark — warm' header"
echo "$LIST_OUT" | grep -q "Pairs" || fail "list missing 'Pairs' section"
pass "list output includes expected themes and section headers"

echo ""
echo "=== set <theme> writes the right settings.json ==="

"$CHROMATICLI" set monokai --no-install --project "$PROJECT" > /dev/null
jq -e '.["workbench.colorTheme"] == "Monokai"' "$PROJECT/.vscode/settings.json" > /dev/null \
  || fail "set monokai did not write workbench.colorTheme=Monokai"
pass "set monokai writes workbench.colorTheme=Monokai"

echo ""
echo "=== set <N> (numeric pick) resolves to the same theme as the name ==="

# Recompute the project so we have a clean slate
rm -rf "$PROJECT/.vscode"
# Pick a known index: theme #1 is 'grass' (dark-warm bucket, alpha-sorted first).
"$CHROMATICLI" set 1 --no-install --project "$PROJECT" > /dev/null
jq -e '.["workbench.colorTheme"] == "Green Abyss"' "$PROJECT/.vscode/settings.json" > /dev/null \
  || fail "set 1 should resolve to grass (Green Abyss), got: $(jq -r '."workbench.colorTheme"' "$PROJECT/.vscode/settings.json")"
pass "set 1 resolves to grass (Green Abyss)"

echo ""
echo "=== set --pair writes pair keys, not single-theme key ==="

rm -rf "$PROJECT/.vscode"
"$CHROMATICLI" set --pair solarized --no-install --project "$PROJECT" > /dev/null
SETTINGS="$PROJECT/.vscode/settings.json"
jq -e '.["window.autoDetectColorScheme"] == true' "$SETTINGS" > /dev/null \
  || fail "set --pair did not set window.autoDetectColorScheme"
jq -e '.["workbench.preferredLightColorTheme"] == "Solarized Light"' "$SETTINGS" > /dev/null \
  || fail "set --pair did not set preferredLightColorTheme"
jq -e '.["workbench.preferredDarkColorTheme"] == "Solarized Dark"' "$SETTINGS" > /dev/null \
  || fail "set --pair did not set preferredDarkColorTheme"
jq -e '.["workbench.colorTheme"] == null' "$SETTINGS" > /dev/null \
  || fail "set --pair should not leave workbench.colorTheme"
pass "set --pair writes autoDetectColorScheme + preferredLight/DarkColorTheme"

echo ""
echo "=== unset removes theme keys, leaves others intact ==="

# Seed an unrelated key to confirm it survives
jq '. + {"editor.fontSize": 14}' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
"$CHROMATICLI" unset --project "$PROJECT" > /dev/null
jq -e '.["workbench.colorTheme"] == null' "$SETTINGS" > /dev/null \
  || fail "unset did not remove workbench.colorTheme"
jq -e '.["window.autoDetectColorScheme"] == null' "$SETTINGS" > /dev/null \
  || fail "unset did not remove window.autoDetectColorScheme"
jq -e '.["editor.fontSize"] == 14' "$SETTINGS" > /dev/null \
  || fail "unset stomped an unrelated key (editor.fontSize)"
pass "unset removes theme keys only, preserves others"

echo ""
echo "=== preview does not write settings.json ==="

# Fresh state — make sure there's no .vscode dir to find
rm -rf "$PROJECT/.vscode"
# Use --no-emit-friendly path: preview *does* try to OSC-emit, but in a non-TTY
# CI runner /dev/tty is unavailable; the script swallows the error and
# continues. We're verifying the no-file-write contract, not the OSC behavior.
(cd "$PROJECT" && "$CHROMATICLI" preview monokai > /dev/null) \
  || fail "preview exited nonzero"
[[ ! -e "$PROJECT/.vscode" ]] || fail "preview created .vscode (should be no file writes)"
pass "preview monokai does not write .vscode/"

# Bad theme to preview → exit 2
set +e
(cd "$PROJECT" && "$CHROMATICLI" preview nonexistent_theme 2>/dev/null)
rc=$?
set -e
[[ $rc -eq 2 ]] || fail "preview bad theme expected exit 2, got $rc"
pass "preview unknown theme exits 2"

echo ""
echo "=== bad theme / pair / number → exit 2 ==="

set +e
"$CHROMATICLI" set nonexistent_theme --no-install --project "$PROJECT" 2>/dev/null
rc=$?
set -e
[[ $rc -eq 2 ]] || fail "bad theme expected exit 2, got $rc"
pass "unknown theme name exits 2"

set +e
"$CHROMATICLI" set 999 --no-install --project "$PROJECT" 2>/dev/null
rc=$?
set -e
[[ $rc -eq 2 ]] || fail "out-of-range number expected exit 2, got $rc"
pass "out-of-range numeric pick exits 2"

set +e
"$CHROMATICLI" set --pair nonexistent_pair --no-install --project "$PROJECT" 2>/dev/null
rc=$?
set -e
[[ $rc -eq 2 ]] || fail "bad pair expected exit 2, got $rc"
pass "unknown pair name exits 2"

echo ""
echo "All smoke checks passed."

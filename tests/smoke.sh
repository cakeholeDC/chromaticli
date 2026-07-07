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
TESTHOME=$(mktemp -d)
trap 'rm -rf "$PROJECT" "$TESTHOME"' EXIT

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
echo "=== list marks active theme from parent settings ==="

mkdir -p "$PROJECT/src/nested"
LIST_CHILD_OUT=$(cd "$PROJECT/src/nested" && "$CHROMATICLI" list)
echo "$LIST_CHILD_OUT" | grep -q "monokai.*(currently active)" \
  || fail "list from child dir did not mark parent project theme as active"
pass "list walks up parent dirs to mark active theme"

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
# preview requires an installed hook; install first with HOME=$PROJECT so hook lands there
XDG_CONFIG_HOME='' HOME="$PROJECT" "$CHROMATICLI" install --shell zsh --force > /dev/null 2>&1 \
  || fail "pre-preview install exited nonzero"
# Use --no-emit-friendly path: preview *does* try to OSC-emit, but in a non-TTY
# CI runner /dev/tty is unavailable; the script swallows the error and
# continues. We're verifying the no-file-write contract, not the OSC behavior.
XDG_CONFIG_HOME='' HOME="$PROJECT" "$CHROMATICLI" preview monokai > /dev/null \
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

# Save and unset XDG_CONFIG_HOME for the new multi-shell test block
_SAVED_XDG="${XDG_CONFIG_HOME:-}"
unset XDG_CONFIG_HOME

echo ""
echo "=== install --shell zsh wires .zshrc ==="

HOME="$TESTHOME" "$CHROMATICLI" install --shell zsh --force > /dev/null 2>&1 || fail "install --shell zsh exited nonzero"
grep -Fq "# chromaticli" "$TESTHOME/.zshrc" \
  || fail "install --shell zsh did not write # chromaticli marker to .zshrc"
grep -Fq "hook.zsh" "$TESTHOME/.zshrc" \
  || fail "install --shell zsh did not write hook.zsh source line to .zshrc"
[[ -f "$TESTHOME/.config/chromaticli/hook.bash" ]] \
  || fail "install --shell zsh did not copy hook.bash to config dir"
[[ -f "$TESTHOME/.config/chromaticli/hook.fish" ]] \
  || fail "install --shell zsh did not copy hook.fish to config dir"
pass "install --shell zsh wires .zshrc and copies all hooks"

echo ""
echo "=== install --shell bash wires .bash_profile ==="

HOME="$TESTHOME" "$CHROMATICLI" install --shell bash --force > /dev/null 2>&1 || fail "install --shell bash exited nonzero"
grep -Fq "# chromaticli" "$TESTHOME/.bash_profile" \
  || fail "install --shell bash did not write # chromaticli marker to .bash_profile"
grep -Fq "hook.bash" "$TESTHOME/.bash_profile" \
  || fail "install --shell bash did not write hook.bash source line to .bash_profile"
pass "install --shell bash wires .bash_profile"

echo ""
echo "=== install --shell fish writes conf.d shim ==="

HOME="$TESTHOME" "$CHROMATICLI" install --shell fish --force > /dev/null 2>&1 || fail "install --shell fish exited nonzero"
FISH_SHIM_PATH="$TESTHOME/.config/fish/conf.d/chromaticli.fish"
[[ -f "$FISH_SHIM_PATH" ]] \
  || fail "install --shell fish did not create $FISH_SHIM_PATH"
grep -Fq "hook.fish" "$FISH_SHIM_PATH" \
  || fail "fish conf.d shim does not reference hook.fish"
pass "install --shell fish writes conf.d shim"

echo ""
echo "=== install --shell <unknown> exits 2 ==="

set +e
HOME="$TESTHOME" "$CHROMATICLI" install --shell nushell 2>/dev/null
rc=$?
set -e
[[ $rc -eq 2 ]] || fail "install --shell nushell expected exit 2, got $rc"
pass "install --shell <unsupported> exits 2"

echo ""
echo "=== install is additive: --shell zsh then --shell bash ==="

HOME="$TESTHOME" "$CHROMATICLI" install --shell zsh  --force > /dev/null 2>&1
HOME="$TESTHOME" "$CHROMATICLI" install --shell bash --force > /dev/null 2>&1
grep -Fq "# chromaticli" "$TESTHOME/.zshrc"        || fail "zshrc marker missing after additive install"
grep -Fq "# chromaticli" "$TESTHOME/.bash_profile"  || fail "bash_profile marker missing after additive install"
pass "install is additive: both shells wired independently"

echo ""
echo "=== uninstall cleans all shells ==="

# Install each shell that is available, then verify uninstall removes what was installed.
# Fish is only tested when fish is on PATH — otherwise the assertion would vacuously pass
# (nothing was installed, so nothing to clean) while actually testing nothing.
HOME="$TESTHOME" "$CHROMATICLI" install --shell zsh   --force > /dev/null 2>&1 || true
HOME="$TESTHOME" "$CHROMATICLI" install --shell bash  --force > /dev/null 2>&1 || true
HOME="$TESTHOME" "$CHROMATICLI" install --shell fish --force > /dev/null 2>&1 || true
FISH_SHIM_INSTALLED=0
[[ -f "$TESTHOME/.config/fish/conf.d/chromaticli.fish" ]] && FISH_SHIM_INSTALLED=1

# XDG_CONFIG_HOME is unset for this entire test block (see setup above).
# With XDG_CONFIG_HOME unset and HOME="$TESTHOME", FISH_CONF_D inside the script
# resolves to "$TESTHOME/.config/fish/conf.d" — identical to where the fish install wrote.
# FISH_SHIM_INSTALLED tracks whether the shim file was actually written, regardless of
# whether fish is on PATH. The install command does not require fish to be installed.
HOME="$TESTHOME" "$CHROMATICLI" uninstall > /dev/null 2>&1 || fail "uninstall exited nonzero"
grep -Fq "# chromaticli" "$TESTHOME/.zshrc"       2>/dev/null && fail "uninstall left # chromaticli in .zshrc"
grep -Fq "# chromaticli" "$TESTHOME/.bash_profile" 2>/dev/null && fail "uninstall left # chromaticli in .bash_profile"
if (( FISH_SHIM_INSTALLED )); then
  [[ ! -f "$TESTHOME/.config/fish/conf.d/chromaticli.fish" ]] \
    || fail "uninstall left fish conf.d shim"
fi
pass "uninstall removes rc entries for all shells"

echo ""
echo "=== --shell and --all-shells are mutually exclusive ==="

set +e
HOME="$TESTHOME" "$CHROMATICLI" install --shell zsh --all-shells 2>/dev/null
rc=$?
set -e
[[ $rc -eq 2 ]] || fail "--shell + --all-shells expected exit 2, got $rc"
pass "--shell and --all-shells are mutually exclusive"

echo ""
echo "=== install auto-detects from SHELL env var ==="

SHELL=bash HOME="$TESTHOME" "$CHROMATICLI" install --force > /dev/null 2>&1 \
  || fail "install with SHELL=bash exited nonzero"
grep -Fq "# chromaticli" "$TESTHOME/.bash_profile" \
  || fail "auto-detect SHELL=bash did not wire .bash_profile"
pass "install auto-detects shell from SHELL env var"

echo ""
echo "=== --all-shells wires all shells present ==="

HOME="$TESTHOME" "$CHROMATICLI" install --all-shells --force > /dev/null 2>&1 \
  || fail "install --all-shells exited nonzero"
# Gate zsh assertion on PATH availability — CI (ubuntu-latest) may not have zsh.
# zsh is always on macOS but is not guaranteed in Linux CI environments.
if command -v zsh > /dev/null 2>&1; then
  grep -Fq "# chromaticli" "$TESTHOME/.zshrc" \
    || fail "--all-shells did not wire .zshrc"
fi
# bash is always present
grep -Fq "# chromaticli" "$TESTHOME/.bash_profile" \
  || fail "--all-shells did not wire .bash_profile"
pass "install --all-shells wires available shells"

echo ""
echo "=== hook.bash prepends to PROMPT_COMMAND without clobbering ==="

# Source hook.bash directly in a subshell with a pre-existing PROMPT_COMMAND.
# Verifies the scalar prepend path (bash 3.2/4.x) doesn't clobber an existing value.
# CHROMATICLI is <repo_root>/chromaticli, so dirname gives the repo root where hook.bash lives.
HOOK_BASH="$(dirname "$CHROMATICLI")/hook.bash"
result=$(bash -c '
  PROMPT_COMMAND="existing_func"
  source "'"$HOOK_BASH"'" 2>/dev/null
  echo "$PROMPT_COMMAND"
' 2>/dev/null)
echo "$result" | grep -q "_chromaticli_prompt_hook" \
  || fail "hook.bash did not register _chromaticli_prompt_hook in PROMPT_COMMAND"
echo "$result" | grep -q "existing_func" \
  || fail "hook.bash clobbered existing PROMPT_COMMAND value"
pass "hook.bash prepends to PROMPT_COMMAND without clobbering"

echo ""
echo "=== bash-only uninstall (no zsh configured) ==="

# Reset TESTHOME to a clean state.
# rm -rf deletes the FIRST tmpdir before reassignment. The EXIT trap expands $TESTHOME
# at fire time (not definition time), so it cleans the SECOND tmpdir. No leak.
rm -rf "$TESTHOME"
TESTHOME=$(mktemp -d)
HOME="$TESTHOME" "$CHROMATICLI" install --shell bash --force > /dev/null 2>&1 \
  || fail "bash-only install exited nonzero"
HOME="$TESTHOME" "$CHROMATICLI" uninstall > /dev/null 2>&1 \
  || fail "bash-only uninstall exited nonzero"
grep -Fq "# chromaticli" "$TESTHOME/.bash_profile" 2>/dev/null \
  && fail "bash-only uninstall left # chromaticli in .bash_profile"
pass "bash-only uninstall removes rc entry without touching zsh"

echo ""
echo "=== preview smoke ==="

# preview requires a real TTY for OSC output; only verify it exits 0 with a valid theme
# and that the hook resolution path doesn't regress when hook files are present.
# Install first so the hook file exists — preview must find it to exit 0.
HOME="$TESTHOME" "$CHROMATICLI" install --shell zsh --force > /dev/null 2>&1 \
  || fail "pre-preview install exited nonzero"
set +e
# Use monokai — it exists in themes.json. (github-dark does not.)
SHELL=zsh HOME="$TESTHOME" "$CHROMATICLI" preview monokai > /dev/null 2>&1
rc=$?
set -e
# exit 0 means the hook was found and the spawn path didn't error;
# non-zero means a hook-resolution regression — install must precede preview.
# ponytail: OSC output is not verified here (no TTY in CI). Manual TTY check required.
# Ceiling: if preview exits 0 even when the hook is broken (e.g., silent fail), this
# test passes vacuously. Upgrade path: restructure preview to emit a machine-readable
# status line when stdout is not a TTY.
[[ $rc -eq 0 ]] || fail "preview exited $rc — possible hook resolution regression"
pass "preview resolves shell hook without error"

# Restore XDG_CONFIG_HOME after multi-shell tests
[[ -n "$_SAVED_XDG" ]] && export XDG_CONFIG_HOME="$_SAVED_XDG"
unset _SAVED_XDG

echo ""
echo "All smoke checks passed."

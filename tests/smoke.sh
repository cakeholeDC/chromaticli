#!/usr/bin/env bash
# Non-TTY smoke checks for chromaticli. Runs in CI's `smoke` job; also
# runnable locally for a fast pre-commit sanity sweep:
#
#   ./tests/smoke.sh
#
# Covers what can be exercised without a real terminal: help/version/usage,
# `list` output, `set`/`unset` settings.json writes, exit codes for bad
# input, fake-code lifecycle, and hook palette selection. Actual TTY rendering
# belongs in tests/SMOKE_TEST.md (the human walkthrough).

set -euo pipefail

# Resolve CHROMATICLI to an absolute path so subshell `cd`s don't break the
# invocation. Default to the repo-relative `./chromaticli` so the script can
# be run via `./tests/smoke.sh` from the repo root.
_default_cli="$(cd "$(dirname "$0")/.." && pwd)/chromaticli"
CHROMATICLI="${CHROMATICLI:-$_default_cli}"
PROJECT=$(mktemp -d)
TESTHOME=$(mktemp -d)
MANAGED_LIBEXEC=$(mktemp -d)
TEST_WORK=$(mktemp -d)
trap 'rm -rf "$PROJECT" "$TESTHOME" "$MANAGED_LIBEXEC" "$TEST_WORK"' EXIT
REPO_ROOT=$(dirname "$CHROMATICLI")
# Isolate every invocation, including early list/set checks, from real settings,
# shell rc files, inherited hook state, package paths, and the real code CLI.
export HOME="$TEST_WORK/home" SHELL=bash
mkdir -p "$HOME" "$TEST_WORK/bin"
unset XDG_CONFIG_HOME ZDOTDIR CHROMATICLI_LIBEXEC CHROMATICLI_FORCE _CHROMATICLI_ACTIVE _CHROMATICLI_HOOK_BASH_LOADED
export PATH="$TEST_WORK/bin:$PATH" CHROMATICLI_TEST_WORK="$TEST_WORK"
cat > "$TEST_WORK/bin/code" <<'CODE'
#!/usr/bin/env bash
set -euo pipefail
work="$CHROMATICLI_TEST_WORK"
printf '%s\n' "$*" >> "$work/code-calls"
case "$1" in
  --list-extensions)
    [[ $# == 1 || ( $# == 2 && "$2" == --show-versions ) ]] || exit 90
    printf 'other.extension%s\n' "${2:+@1.0.0}"
    if [[ -f "$work/code-version" ]]; then
      printf 'chromaticli.chromaticli-themes%s\n' "${2:+@$(cat "$work/code-version")}"
    fi ;;
  --install-extension)
    [[ $# == 3 && "$3" == --force && -s "$2" && "$2" == *.vsix ]] || exit 91
    version=$(jq -er 'select(.publisher == "chromaticli" and .name == "chromaticli-themes") | .version | select(type == "string")' "$(dirname "$2")/package.json")
    [[ "$2" == "$(dirname "$2")/chromaticli-themes-$version.vsix" ]] || exit 92
    printf '%s\n' "$version" > "$work/code-version" ;;
  --uninstall-extension)
    [[ $# == 2 && "$2" == chromaticli.chromaticli-themes ]] || exit 93
    [[ "${CHROMATICLI_TEST_REMOVE_FAIL:-}" != 1 ]] || exit 94
    rm -f "$work/code-version" ;;
  *) exit 95 ;;
esac
CODE
chmod +x "$TEST_WORK/bin/code"
: > "$TEST_WORK/code-calls"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "  ok  $*"; }

require() {
  command -v "$1" >/dev/null || fail "smoke.sh needs '$1' on PATH"
}

require jq
require "$CHROMATICLI"

echo "=== top-level help / version / usage ==="

EXPECTED_VERSION=$(sed -n 's/^CHROMATICLI_VERSION="\([^"]*\)".*/\1/p' "$CHROMATICLI")
[[ -n "$EXPECTED_VERSION" ]] || fail "could not read CHROMATICLI_VERSION"
[[ $("$CHROMATICLI" --version) == "chromaticli $EXPECTED_VERSION" ]] \
  || fail "--version does not match CHROMATICLI_VERSION"
pass "--version matches CHROMATICLI_VERSION ($EXPECTED_VERSION)"

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
echo "$LIST_OUT" | grep -q "dark-green" || fail "list missing 'dark-green'"
echo "$LIST_OUT" | grep -q "dark-indigo" || fail "list missing 'dark-indigo'"
echo "$LIST_OUT" | grep -q "── Core" || fail "list missing 'Core' header"
echo "$LIST_OUT" | grep -q "── Light" || fail "list missing 'Light' header"
echo "$LIST_OUT" | grep -q "── Dark" || fail "list missing 'Dark' header"
echo "$LIST_OUT" | grep -q "── Defaults" || fail "list missing 'Defaults' header"
echo "$LIST_OUT" | grep -q "Pairs" || fail "list missing 'Pairs' section"
printf '%s\n' "$LIST_OUT" | awk '$1 ~ /^[0-9]+[.]$/ {print $2}' | sort > "$TEST_WORK/list-ids"
jq -r '(.themes | keys[]), (.pairs | keys[])' "$REPO_ROOT/themes.json" | sort > "$TEST_WORK/registry-ids"
cmp "$TEST_WORK/registry-ids" "$TEST_WORK/list-ids" || fail "list has missing or duplicate visible entries"
printf '%s\n' red orange yellow green blue indigo violet \
  light-red light-orange light-yellow light-green light-blue light-indigo light-violet \
  dark-red dark-orange dark-yellow dark-green dark-blue dark-indigo dark-violet \
  light dark > "$TEST_WORK/expected-theme-order"
printf '%s\n' "$LIST_OUT" | awk '$1 ~ /^[0-9]+[.]$/ {print $2}' | head -n 23 > "$TEST_WORK/list-theme-order"
cmp "$TEST_WORK/expected-theme-order" "$TEST_WORK/list-theme-order" \
  || fail "list themes are not ordered by ROYGBIV within their sections"
pass "list shows each registered theme/pair once and expected section headers"

# An older source install can still have the previous category values until
# install --force refreshes its config copy. Those entries must remain visible.
mkdir -p "$TEST_WORK/legacy-config/chromaticli"
jq '(.themes |= with_entries(.value.category |=
      if . == "core" then "dark-warm" elif . == "dark" then "dark-cool" else . end))' \
  "$REPO_ROOT/themes.json" > "$TEST_WORK/legacy-config/chromaticli/themes.json"
LEGACY_CATEGORY_LIST=$(XDG_CONFIG_HOME="$TEST_WORK/legacy-config" "$CHROMATICLI" list)
printf '%s\n' "$LEGACY_CATEGORY_LIST" | awk '$1 ~ /^[0-9]+[.]$/ {print $2}' | sort > "$TEST_WORK/legacy-category-list-ids"
cmp "$TEST_WORK/registry-ids" "$TEST_WORK/legacy-category-list-ids" \
  || fail "list omitted themes from an older installed registry"
printf '%s\n' "$LEGACY_CATEGORY_LIST" | grep -q "── Dark" \
  || fail "older dark categories were not grouped under Dark"
pass "list keeps every theme visible from an older installed registry"

echo ""
echo "=== set <theme> writes the right settings.json ==="

"$CHROMATICLI" set dark-green --no-install --project "$PROJECT" > /dev/null
jq -e '.["workbench.colorTheme"] == "chromaticli dark-green"' "$PROJECT/.vscode/settings.json" > /dev/null \
  || fail "set dark-green did not write workbench.colorTheme=chromaticli dark-green"
[[ ! -e "$PROJECT/.vscode/extensions.json" ]] || fail "bundled set created Marketplace recommendations"
pass "set dark-green writes workbench.colorTheme=chromaticli dark-green"

echo ""
echo "=== list marks active theme from parent settings ==="

mkdir -p "$PROJECT/src/nested"
LIST_CHILD_OUT=$(cd "$PROJECT/src/nested" && "$CHROMATICLI" list)
echo "$LIST_CHILD_OUT" | grep -q "dark-green.*(currently active)" \
  || fail "list from child dir did not mark parent project theme as active"
pass "list walks up parent dirs to mark active theme"

echo ""
echo "=== set <N> (numeric pick) resolves to the same theme as the name ==="

# Recompute the project so we have a clean slate
rm -rf "$PROJECT/.vscode"
# Read the displayed number rather than duplicating category/order logic.
PICK_NUMBER=$(printf '%s\n' "$LIST_OUT" | awk '$2 == "dark-green" {sub(/\.$/, "", $1); print $1}')
[[ "$PICK_NUMBER" =~ ^[0-9]+$ ]] || fail "no numeric pick for dark-green in list"
"$CHROMATICLI" set "$PICK_NUMBER" --no-install --project "$PROJECT" > /dev/null
jq -e '.["workbench.colorTheme"] == "chromaticli dark-green"' "$PROJECT/.vscode/settings.json" > /dev/null \
  || fail "numeric pick $PICK_NUMBER differs from set dark-green"
pass "numeric pick matches the displayed theme name"

echo ""
echo "=== set --pair writes pair keys, not single-theme key ==="

rm -rf "$PROJECT/.vscode"
"$CHROMATICLI" set --pair blue-pair --no-install --project "$PROJECT" > /dev/null
SETTINGS="$PROJECT/.vscode/settings.json"
jq -e '.["window.autoDetectColorScheme"] == true' "$SETTINGS" > /dev/null \
  || fail "set --pair did not set window.autoDetectColorScheme"
jq -e '.["workbench.preferredLightColorTheme"] == "chromaticli light-blue"' "$SETTINGS" > /dev/null \
  || fail "set --pair did not set preferredLightColorTheme"
jq -e '.["workbench.preferredDarkColorTheme"] == "chromaticli dark-blue"' "$SETTINGS" > /dev/null \
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
jq -e 'has("workbench.preferredLightColorTheme") or has("workbench.preferredDarkColorTheme") | not' "$SETTINGS" >/dev/null \
  || fail "unset left preferred pair theme keys"
[[ ! -s "$TEST_WORK/code-calls" ]] || fail "--no-install / unset called code"
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
XDG_CONFIG_HOME='' HOME="$PROJECT" "$CHROMATICLI" preview dark-green > /dev/null \
  || fail "preview exited nonzero"
[[ ! -e "$PROJECT/.vscode" ]] || fail "preview created .vscode (should be no file writes)"
pass "preview dark-green does not write .vscode/"

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
echo "=== package-managed install uses support files in place ==="

cp "$CHROMATICLI" "$REPO_ROOT/hook.zsh" "$REPO_ROOT/hook.bash" \
  "$REPO_ROOT/hook.fish" "$REPO_ROOT/themes.json" "$MANAGED_LIBEXEC/"
mkdir -p "$MANAGED_LIBEXEC/vscode-extension"
cp "$REPO_ROOT/vscode-extension/package.json" "$REPO_ROOT/vscode-extension/"*.vsix "$MANAGED_LIBEXEC/vscode-extension/"
chmod +x "$MANAGED_LIBEXEC/chromaticli"
rm -rf "$TESTHOME"
TESTHOME=$(mktemp -d)
[[ $(CHROMATICLI_LIBEXEC="$MANAGED_LIBEXEC" "$MANAGED_LIBEXEC/chromaticli" --version) == "chromaticli $EXPECTED_VERSION" ]] \
  || fail "package-managed CLI reported the wrong version"
CHROMATICLI_LIBEXEC="$MANAGED_LIBEXEC" HOME="$TESTHOME" ZDOTDIR="$TESTHOME" \
  "$MANAGED_LIBEXEC/chromaticli" install --shell zsh --force > /dev/null 2>&1 \
  || fail "package-managed install exited nonzero"
[[ ! -e "$TESTHOME/.local/bin/chromaticli" ]] \
  || fail "package-managed install copied the CLI to ~/.local/bin"
[[ ! -d "$TESTHOME/.config/chromaticli" ]] \
  || fail "package-managed install copied support files to ~/.config"
grep -Fq "source \"$MANAGED_LIBEXEC/hook.zsh\"" "$TESTHOME/.zshrc" \
  || fail "package-managed install did not wire the managed hook path"
CHROMATICLI_LIBEXEC="$MANAGED_LIBEXEC" HOME="$TESTHOME" \
  "$MANAGED_LIBEXEC/chromaticli" list > /dev/null \
  || fail "package-managed CLI could not read managed themes.json"
CHROMATICLI_LIBEXEC="$MANAGED_LIBEXEC" SHELL=zsh HOME="$TESTHOME" \
  "$MANAGED_LIBEXEC/chromaticli" preview dark-green > /dev/null 2>&1 \
  || fail "package-managed CLI could not resolve the managed hook"
CHROMATICLI_LIBEXEC="$MANAGED_LIBEXEC" HOME="$TESTHOME" ZDOTDIR="$TESTHOME" \
  "$MANAGED_LIBEXEC/chromaticli" uninstall > /dev/null 2>&1 \
  || fail "package-managed uninstall exited nonzero"
[[ -f "$MANAGED_LIBEXEC/chromaticli" && -f "$MANAGED_LIBEXEC/hook.zsh" ]] \
  || fail "package-managed uninstall removed package-owned files"
grep -Fq "# chromaticli" "$TESTHOME/.zshrc" 2>/dev/null \
  && fail "package-managed uninstall left the zsh rc block"
pass "package-managed install and uninstall preserve package-owned files"

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
# Use a retained theme with its current color ID.
SHELL=zsh HOME="$TESTHOME" "$CHROMATICLI" preview dark-green > /dev/null 2>&1
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

echo ""
echo "=== public source / managed VS Code theme lifecycle (fake code only) ==="

expect_code_calls() {
  : > "$TEST_WORK/expected-calls"
  if (( $# )); then printf '%s\n' "$@" > "$TEST_WORK/expected-calls"; fi
  cmp "$TEST_WORK/expected-calls" "$TEST_WORK/code-calls" || fail "unexpected code lifecycle calls"
  : > "$TEST_WORK/code-calls"
}

BUNDLED_VERSION=$(jq -r .version "$REPO_ROOT/vscode-extension/package.json")
for mode in source managed; do
  export HOME="$TEST_WORK/lifecycle-$mode"
  mkdir -p "$HOME" "$HOME/project"
  if [[ "$mode" == managed ]]; then
    export CHROMATICLI_LIBEXEC="$MANAGED_LIBEXEC"
    LIFECYCLE_CLI="$MANAGED_LIBEXEC/chromaticli"
    SUPPORT="$MANAGED_LIBEXEC"
  else
    unset CHROMATICLI_LIBEXEC
    LIFECYCLE_CLI="$CHROMATICLI"
    SUPPORT="$HOME/.config/chromaticli"
  fi
  INSTALL_CALL="--install-extension $SUPPORT/vscode-extension/chromaticli-themes-$BUNDLED_VERSION.vsix --force"
  rm -f "$TEST_WORK/code-version"
  : > "$TEST_WORK/code-calls"
  "$LIFECYCLE_CLI" install --shell bash --no-install > "$TEST_WORK/output" 2>&1 || fail "$mode --no-install setup failed"
  expect_code_calls
  [[ -s "$SUPPORT/vscode-extension/chromaticli-themes-$BUNDLED_VERSION.vsix" ]] || fail "$mode --no-install lost VSIX support"
  "$LIFECYCLE_CLI" install --shell bash > "$TEST_WORK/output" 2>&1 || fail "$mode install failed"
  expect_code_calls '--list-extensions --show-versions' "$INSTALL_CALL" '--list-extensions --show-versions'
  "$LIFECYCLE_CLI" install --shell bash > "$TEST_WORK/output" 2>&1 || fail "$mode repeat install failed"
  expect_code_calls '--list-extensions --show-versions'
  if [[ "$mode" == source ]]; then LIFECYCLE_CLI="$HOME/.local/bin/chromaticli"; fi
  # The copied CLI must find copied support; managed mode must use libexec.
  rm "$TEST_WORK/code-version"
  printf '{"recommendations":["other.extension"]}\n' > "$TEST_WORK/extensions-original"
  mkdir -p "$HOME/project/.vscode"
  cp "$TEST_WORK/extensions-original" "$HOME/project/.vscode/extensions.json"
  "$LIFECYCLE_CLI" set blue --project "$HOME/project" > "$TEST_WORK/output" 2>&1 || fail "$mode set failed"
  expect_code_calls '--list-extensions --show-versions' "$INSTALL_CALL" '--list-extensions --show-versions'
  jq -e '.["workbench.colorTheme"] == "chromaticli blue"' "$HOME/project/.vscode/settings.json" >/dev/null \
    || fail "$mode set wrote wrong label"
  cmp "$TEST_WORK/extensions-original" "$HOME/project/.vscode/extensions.json" || fail "$mode set changed recommendations"
  "$LIFECYCLE_CLI" set green --no-install --project "$HOME/project" > "$TEST_WORK/output" 2>&1
  grep -q 'skipped bundled VS Code theme installation' "$TEST_WORK/output" || fail "$mode --no-install omitted notice"
  expect_code_calls
  cp "$HOME/project/.vscode/settings.json" "$TEST_WORK/settings-original"
  (cd "$HOME/project" && "$LIFECYCLE_CLI" preview blue) > "$TEST_WORK/output" 2>&1
  cmp "$TEST_WORK/settings-original" "$HOME/project/.vscode/settings.json" || fail "$mode preview changed settings"
  expect_code_calls
  if [[ "$mode" == source ]]; then
    if CHROMATICLI_TEST_REMOVE_FAIL=1 "$LIFECYCLE_CLI" uninstall > "$TEST_WORK/output" 2>&1; then
      fail "source uninstall hid code removal failure"
    fi
    expect_code_calls --list-extensions '--uninstall-extension chromaticli.chromaticli-themes'
    [[ -x "$LIFECYCLE_CLI" && -s "$SUPPORT/vscode-extension/chromaticli-themes-$BUNDLED_VERSION.vsix" ]] \
      || fail "failed source uninstall removed retry support"
  fi
  "$LIFECYCLE_CLI" uninstall > "$TEST_WORK/output" 2>&1 || fail "$mode uninstall failed"
  expect_code_calls --list-extensions '--uninstall-extension chromaticli.chromaticli-themes' --list-extensions
  cmp "$TEST_WORK/settings-original" "$HOME/project/.vscode/settings.json" || fail "$mode uninstall changed settings"
  cmp "$TEST_WORK/extensions-original" "$HOME/project/.vscode/extensions.json" || fail "$mode uninstall changed recommendations"
  if [[ "$mode" == managed ]]; then
    [[ -x "$LIFECYCLE_CLI" && -s "$SUPPORT/vscode-extension/chromaticli-themes-$BUNDLED_VERSION.vsix" ]] \
      || fail "managed uninstall removed package files"
  else
    [[ ! -e "$LIFECYCLE_CLI" && ! -e "$SUPPORT" ]] || fail "source uninstall left installed files"
    LIFECYCLE_CLI="$CHROMATICLI"
  fi
  "$LIFECYCLE_CLI" uninstall > "$TEST_WORK/output" 2>&1 || fail "$mode repeated uninstall failed"
  expect_code_calls --list-extensions
  pass "$mode install, repeat install, set, --no-install, preview, uninstall, and repeated uninstall"
done
unset CHROMATICLI_LIBEXEC
export HOME="$TEST_WORK/home"

echo ""
echo "=== legacy workspace labels and shell hook palettes ==="

# Each current label and each old label gets the same full OSC body expectation.
# Override only the final TTY writer so lookup, apply, and all 19 colors run.
mkdir -p "$TEST_WORK/cases"
: > "$TEST_WORK/hook-cases"
: > "$TEST_WORK/expected-osc"
expect_palette() {
  {
    printf '%s\n' "$THEME_ID"
    jq -r --arg id "$THEME_ID" '.themes[$id].palette |
      "10;\(.foreground)", "11;\(.background)", "12;\(.cursor)",
      (.ansi | to_entries[] | "4;\(.key);\(.value)")' "$REPO_ROOT/themes.json"
    printf '%s\n' "$THEME_ID"
  } >> "$TEST_WORK/expected-osc"
}
CASE_NUMBER=0
while IFS=$'\t' read -r THEME_ID LABEL; do
  CASE_NUMBER=$((CASE_NUMBER + 1))
  CASE_DIR="$TEST_WORK/cases/$CASE_NUMBER"
  mkdir -p "$CASE_DIR/.vscode" "$CASE_DIR/child"
  jq -n --arg label "$LABEL" '{"workbench.colorTheme":$label}' > "$CASE_DIR/.vscode/settings.json"
  printf '%s\tLight\n' "$CASE_DIR/child" >> "$TEST_WORK/hook-cases"
  expect_palette
  if [[ "$LABEL" != "chromaticli $THEME_ID" ]]; then
    LEGACY_LIST=$(cd "$CASE_DIR/child" && "$CHROMATICLI" list)
    [[ $(printf '%s\n' "$LEGACY_LIST" | grep -c '(currently active)') == 1 ]] || fail "legacy label $LABEL did not select exactly one visible theme"
    printf '%s\n' "$LEGACY_LIST" | grep -q " $THEME_ID .*currently active" || fail "legacy label $LABEL selected wrong theme"
  fi
done < <(jq -r '.themes | to_entries[] | .key as $id |
  (.value.vscode.theme_id, .value.vscode.legacy_theme_ids[]?) | [$id, .] | @tsv' "$REPO_ROOT/themes.json")
# Exercise a light/dark pair in both appearances, with deterministic defaults.
for APPEARANCE in Light Dark; do
  CASE_DIR="$TEST_WORK/cases/pair-$APPEARANCE"
  mkdir -p "$CASE_DIR/.vscode" "$CASE_DIR/child"
  printf '%s\n' '{"window.autoDetectColorScheme":true,"workbench.preferredLightColorTheme":"chromaticli light-yellow","workbench.preferredDarkColorTheme":"chromaticli dark-indigo"}' > "$CASE_DIR/.vscode/settings.json"
  printf '%s\t%s\n' "$CASE_DIR/child" "$APPEARANCE" >> "$TEST_WORK/hook-cases"
  if [[ "$APPEARANCE" == Light ]]; then THEME_ID=light-yellow; else THEME_ID=dark-indigo; fi
  expect_palette
done
pass "CLI recognizes all legacy workspace labels without duplicate active entries"

for hook_shell in bash zsh fish; do
  if ! command -v "$hook_shell" >/dev/null; then
    printf '  SKIP %s hook runtime: shell unavailable\n' "$hook_shell"
    continue
  fi
  if [[ "$hook_shell" == fish ]]; then
    # shellcheck disable=SC2016 # Expanded inside the child shell.
    fish --no-config -c '
      set -gx TERM_PROGRAM vscode
      set -e CHROMATICLI_FORCE
      source $argv[1]
      function _chromaticli_osc; printf "%s\n" $argv[1]; end
      function defaults; printf "%s\n" $appearance; end
      while read -l case_dir appearance
        set -e CHROMATICLI_FORCE
        cd $case_dir
        set -e _CHROMATICLI_ACTIVE
        _chromaticli_pick
        set -gx CHROMATICLI_FORCE 1
        _chromaticli_apply
        printf "%s\n" $_CHROMATICLI_ACTIVE
      end < $argv[2]
    ' "$REPO_ROOT/hook.fish" "$TEST_WORK/hook-cases" > "$TEST_WORK/actual-osc"
  else
    # shellcheck disable=SC2016 # Expanded inside the child shell.
    "$hook_shell" -f -c '
      TERM_PROGRAM=vscode
      unset CHROMATICLI_FORCE
      source "$1"
      _chromaticli_osc() { printf "%s\n" "$1"; }
      defaults() { printf "%s\n" "$appearance"; }
      while read -r case_dir appearance; do
        unset CHROMATICLI_FORCE
        cd "$case_dir" || exit 1
        unset _CHROMATICLI_ACTIVE
        _chromaticli_pick
        CHROMATICLI_FORCE=1 _chromaticli_apply
        printf "%s\n" "$_CHROMATICLI_ACTIVE"
      done < "$2"
    ' smoke-hook "$REPO_ROOT/hook.$hook_shell" "$TEST_WORK/hook-cases" > "$TEST_WORK/actual-osc"
  fi
  cmp "$TEST_WORK/expected-osc" "$TEST_WORK/actual-osc" || fail "$hook_shell hook selected or emitted the wrong palette"
  pass "$hook_shell current / legacy labels and legacy pairs emit matching foreground, background, cursor, and all ANSI colors"
done

echo ""
echo "All smoke checks passed."

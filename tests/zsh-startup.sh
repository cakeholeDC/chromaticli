#!/usr/bin/env bash
# Verifies zsh installation stays at the end of .zshrc and sourcing its hook
# does not perform terminal I/O during initialization.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
command -v zsh >/dev/null || {
  echo 'skip zsh startup test (zsh is not installed)'
  exit 0
}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
HOME_DIR="$WORK/home"
PROJECT="$WORK/project"
mkdir -p "$HOME_DIR" "$PROJECT/.vscode"
cat > "$HOME_DIR/.zshrc" <<'EOF'
# Enable Powerlevel10k instant prompt. Should stay close to the top.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export TEST_CONFIG_AFTER_P10K=1
EOF
jq -n '{"workbench.colorTheme":"chromaticli blue"}' > "$PROJECT/.vscode/settings.json"

HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" ZDOTDIR="$HOME_DIR" SHELL=/bin/zsh \
  "$ROOT/chromaticli" install --shell zsh --force --no-install > "$WORK/install.out" 2>&1

last_line=$(awk 'NF { last = $0 } END { print last }' "$HOME_DIR/.zshrc")
expected_line="source \"$HOME_DIR/.config/chromaticli/hook.zsh\""
[[ "$last_line" == "$expected_line" ]] || {
  printf 'FAIL: chromaticli source line is not at the end of .zshrc\n' >&2
  exit 1
}
[[ ! -e "$HOME_DIR/.config/chromaticli/install-version.json" ]] || {
  printf 'FAIL: --no-install wrote a sync marker\n' >&2
  exit 1
}

if HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" ZDOTDIR="$HOME_DIR" \
  PROJECT="$PROJECT" TERM_PROGRAM=Terminal zsh -f -c '
    cd "$PROJECT"
    source "$ZDOTDIR/.zshrc"
    (( ${precmd_functions[(Ie)_chromaticli_after_initial_prompt]} > 0 )) || exit 42
    [[ -z "${_CHROMATICLI_SYNC_CHECKED-}" ]] || exit 43
  ' > "$WORK/startup.out" 2>&1; then
  :
else
  cat "$WORK/startup.out" >&2
  printf 'FAIL: zsh startup exited nonzero\n' >&2
  exit 1
fi

if [[ -s "$WORK/startup.out" ]]; then
  cat "$WORK/startup.out" >&2
  printf 'FAIL: sourcing the zsh hook produced startup output\n' >&2
  exit 1
fi

HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" ZDOTDIR="$HOME_DIR" \
  PROJECT="$PROJECT" OSC_FILE="$WORK/osc.out" TERM_PROGRAM=Terminal zsh -f -c '
    cd "$PROJECT"
    source "$ZDOTDIR/.zshrc"
    _chromaticli_osc() { print -r -- "$1" >> "$OSC_FILE"; }
    _chromaticli_finish_initial_prompt
    [[ "$_CHROMATICLI_ACTIVE" == blue ]] || exit 44
    __p9k_instant_prompt_active=1
    _chromaticli_check_version_after_instant_prompt
    [[ -z "${_CHROMATICLI_SYNC_CHECKED-}" ]] || exit 45
    unset __p9k_instant_prompt_active
    _chromaticli_check_version_after_instant_prompt
    [[ -n "${_CHROMATICLI_SYNC_CHECKED-}" ]] || exit 46
  ' > "$WORK/first-prompt.out" 2>&1 || {
    cat "$WORK/first-prompt.out" >&2
  printf 'FAIL: first-prompt setup did not apply the theme or defer the warning until after instant-prompt cleanup\n' >&2
    exit 1
  }
[[ $(grep -c "^\[WARN\]: chromaticli: version mismatch detected; run \`chromaticli install --force\`" "$WORK/first-prompt.out" || true) == 1 ]] || {
  cat "$WORK/first-prompt.out" >&2
  printf 'FAIL: version check did not warn exactly once after instant-prompt cleanup\n' >&2
  exit 1
}
[[ "$(head -n 1 "$WORK/first-prompt.out")" == "" ]] || {
  printf 'FAIL: version warning did not have a leading blank line\n' >&2
  exit 1
}
[[ $(wc -l < "$WORK/osc.out" | tr -d ' ') -gt 0 ]] || {
  printf 'FAIL: first-prompt setup did not emit the selected palette\n' >&2
  exit 1
}

echo 'OK: zsh hook stays at the end, applies the theme, and delays version warnings until P10K cleanup'

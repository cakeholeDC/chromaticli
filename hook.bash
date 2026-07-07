#!/usr/bin/env bash
# chromaticli — sync terminal colors with VSCode workspace themes.
# chromaticli :: hook.bash
# Sourced from ~/.bash_profile by `chromaticli install`. On every cd (detected
# via PROMPT_COMMAND + $PWD tracking), reads .vscode/settings.json from the
# current dir tree and emits standard OSC color escapes to /dev/tty.
# Resets on cd out. Honors `window.autoDetectColorScheme` + macOS
# AppleInterfaceStyle for light/dark pairs.
# 
# OSC codes used (iTerm2, Terminal.app, Alacritty, Kitty, etc.):
#   OSC 10 ; #RRGGBB  BEL   default foreground
#   OSC 11 ; #RRGGBB  BEL   default background
#   OSC 12 ; #RRGGBB  BEL   cursor color
#   OSC 4 ; N ; #RRGGBB BEL ANSI palette index N (0-15)
#   OSC 104             BEL  reset palette 0-15
#   OSC 110/111/112     BEL  reset fg/bg/cursor

# Idempotency guard: if .bash_profile is re-sourced (e.g. `source ~/.bash_profile`),
# skip re-registration to avoid appending _chromaticli_prompt_hook to PROMPT_COMMAND twice.
[[ "${_CHROMATICLI_HOOK_BASH_LOADED:-}" == "1" ]] && return
_CHROMATICLI_HOOK_BASH_LOADED=1

_CHROMATICLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CHROMATICLI_THEMES="$_CHROMATICLI_DIR/themes.json"

_chromaticli_osc() {
  local body="$1"
  if [[ -n "$TMUX" ]]; then
    # shellcheck disable=SC1003
    printf '\ePtmux;\e\033]%s\007\e\\' "$body" > /dev/tty
  else
    printf '\033]%s\007' "$body" > /dev/tty
  fi
}

_chromaticli_emit() {
  local theme="$1"
  command -v jq >/dev/null || return 1
  local palette
  palette=$(jq -r --arg t "$theme" '
    .themes[$t].palette |
    (.foreground // ""), (.background // ""), (.cursor // ""),
    (.ansi[] // "")
  ' "$_CHROMATICLI_THEMES") || return 1
  local fg="" bg="" cur="" i=0
  local ansi=()
  while IFS= read -r line; do
    case $i in
      0) fg="$line" ;; 1) bg="$line" ;; 2) cur="$line" ;;
      *) ansi+=("$line") ;;
    esac
    (( i++ ))
  done <<< "$palette"
  [[ -z "$bg" ]] && return 1
  [[ -n "$fg"  ]] && _chromaticli_osc "10;$fg"
  [[ -n "$bg"  ]] && _chromaticli_osc "11;$bg"
  [[ -n "$cur" ]] && _chromaticli_osc "12;$cur"
  for i in "${!ansi[@]}"; do
    [[ -n "${ansi[$i]}" ]] && _chromaticli_osc "4;$i;${ansi[$i]}"
  done
}

_chromaticli_reset() {
  _chromaticli_osc "110"
  _chromaticli_osc "111"
  _chromaticli_osc "112"
  _chromaticli_osc "104"
}

_chromaticli_find_settings() {
  local dir="$PWD"
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -f "$dir/.vscode/settings.json" ]]; then
      printf '%s' "$dir/.vscode/settings.json"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

_chromaticli_pick() {
  local settings
  settings=$(_chromaticli_find_settings) || return 1
  command -v jq >/dev/null || return 1

  local settings_vals
  settings_vals=$(jq -r '
    (."window.autoDetectColorScheme" // ""),
    (."workbench.preferredLightColorTheme" // ""),
    (."workbench.preferredDarkColorTheme" // ""),
    (."workbench.colorTheme" // "")
  ' "$settings") || return 1
  local auto="" pref_light="" pref_dark="" single="" i=0
  while IFS= read -r line; do
    case $i in
      0) auto="$line" ;; 1) pref_light="$line" ;;
      2) pref_dark="$line" ;; 3) single="$line" ;;
    esac
    (( i++ ))
  done <<< "$settings_vals"
  local theme_name

  if [[ "$auto" == "true" && -n "$pref_light" && -n "$pref_dark" ]]; then
    if [[ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" == "Dark" ]]; then
      theme_name="$pref_dark"
    else
      theme_name="$pref_light"
    fi
  elif [[ -n "$single" ]]; then
    theme_name="$single"
  else
    return 1
  fi

  jq -r --arg n "$theme_name" \
    '.themes | to_entries[] | select(.value.vscode.theme_id == $n) | .key' \
    "$_CHROMATICLI_THEMES"
}

_chromaticli_apply() {
  if [[ -z "${CHROMATICLI_FORCE-}" ]]; then
    case "$TERM_PROGRAM" in
      vscode|cursor) return ;;
      esac
  fi

  local theme
  theme=$(_chromaticli_pick 2>/dev/null) || theme=""

  if [[ -n "$theme" ]]; then
    if [[ "$theme" != "${_CHROMATICLI_ACTIVE-}" ]]; then
      _chromaticli_emit "$theme" && export _CHROMATICLI_ACTIVE="$theme"
    fi
  elif [[ -n "${_CHROMATICLI_ACTIVE-}" ]]; then
    _chromaticli_reset
    unset _CHROMATICLI_ACTIVE
  fi
}

_chromaticli_precmd_check_appearance() {
  [[ -z "${_CHROMATICLI_ACTIVE-}" ]] && return
  local cur
  cur="$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light)"
  if [[ "$cur" != "${_CHROMATICLI_APPEARANCE-}" ]]; then
    export _CHROMATICLI_APPEARANCE="$cur"
    unset _CHROMATICLI_ACTIVE
    _chromaticli_apply
  fi
}

# Simulate chpwd: fire _chromaticli_apply only when $PWD changes.
# Appearance re-check runs every prompt when directory is unchanged.
_CHROMATICLI_PREV_PWD="$PWD"
_chromaticli_prompt_hook() {
  if [[ "$PWD" != "$_CHROMATICLI_PREV_PWD" ]]; then
    _CHROMATICLI_PREV_PWD="$PWD"
    _chromaticli_apply
  else
    _chromaticli_precmd_check_appearance
  fi
}

# Bash 5.1+ supports PROMPT_COMMAND as an array. Detect and prepend correctly.
# ponytail: scalar branch handles bash 3.2 (macOS default) and 4.x; array branch
# handles 5.1+ where PROMPT_COMMAND may already be an array.
if declare -p PROMPT_COMMAND 2>/dev/null | grep -q 'declare \-a'; then
  PROMPT_COMMAND=("_chromaticli_prompt_hook" "${PROMPT_COMMAND[@]}")
elif [[ -z "${PROMPT_COMMAND:-}" ]]; then
  PROMPT_COMMAND="_chromaticli_prompt_hook"
else
  PROMPT_COMMAND="_chromaticli_prompt_hook; ${PROMPT_COMMAND}"
fi

_chromaticli_apply

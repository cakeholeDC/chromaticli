#!/usr/bin/env zsh
# chromaticli :: hook.zsh
# Sourced from ~/.zshrc by `chromaticli install`. On every cd (and on shell
# init), reads .vscode/settings.json from the current dir tree and emits
# standard OSC color escapes to /dev/tty. Honors `window.autoDetectColorScheme`
# + macOS AppleInterfaceStyle for light/dark pairs. Resets on cd out.
#
# OSC codes used (iTerm2, Terminal.app, Alacritty, Kitty, etc.):
#   OSC 10 ; #RRGGBB  BEL   default foreground
#   OSC 11 ; #RRGGBB  BEL   default background
#   OSC 12 ; #RRGGBB  BEL   cursor color
#   OSC 4 ; N ; #RRGGBB BEL ANSI palette index N (0-15)
#   OSC 104             BEL  reset palette 0-15
#   OSC 110/111/112     BEL  reset fg/bg/cursor

# shellcheck shell=bash
# shellcheck disable=SC2296  # ${0:A:h} is valid zsh but not recognized by shellcheck

# Resolve config dir from this file's absolute location (works after install
# to ~/.config/chromaticli/).
_CHROMATICLI_DIR="${0:A:h}"
_CHROMATICLI_THEMES="$_CHROMATICLI_DIR/themes.json"

# --- emit one OSC sequence, wrapping for tmux passthrough if needed ---
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
  local fg bg cur
  fg=$(jq -r --arg t "$theme" '.themes[$t].palette.foreground // empty' "$_CHROMATICLI_THEMES")
  bg=$(jq -r --arg t "$theme" '.themes[$t].palette.background // empty' "$_CHROMATICLI_THEMES")
  cur=$(jq -r --arg t "$theme" '.themes[$t].palette.cursor // empty' "$_CHROMATICLI_THEMES")
  [[ -z "$bg" ]] && return 1

  [[ -n "$fg"  ]] && _chromaticli_osc "10;$fg"
  [[ -n "$bg"  ]] && _chromaticli_osc "11;$bg"
  [[ -n "$cur" ]] && _chromaticli_osc "12;$cur"

  local i ansi
  for i in {0..15}; do
    ansi=$(jq -r --arg t "$theme" --argjson i "$i" '.themes[$t].palette.ansi[$i] // empty' "$_CHROMATICLI_THEMES")
    [[ -n "$ansi" ]] && _chromaticli_osc "4;$i;$ansi"
  done
}

_chromaticli_reset() {
  _chromaticli_osc "110"
  _chromaticli_osc "111"
  _chromaticli_osc "112"
  _chromaticli_osc "104"
}

# Walk up from $PWD looking for .vscode/settings.json; first hit wins.
_chromaticli_find_settings() {
  local dir="$PWD"
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -f "$dir/.vscode/settings.json" ]]; then
      echo "$dir/.vscode/settings.json"
      return 0
    fi
    dir="${dir:h}"
  done
  return 1
}

# Read settings.json and reverse-lookup to a theme-id from our registry.
_chromaticli_pick() {
  local settings
  settings=$(_chromaticli_find_settings) || return 1
  command -v jq >/dev/null || return 1

  local auto pref_light pref_dark single theme_name
  auto=$(jq -r '."window.autoDetectColorScheme" // empty' "$settings")
  pref_light=$(jq -r '."workbench.preferredLightColorTheme" // empty' "$settings")
  pref_dark=$(jq -r '."workbench.preferredDarkColorTheme" // empty' "$settings")
  single=$(jq -r '."workbench.colorTheme" // empty' "$settings")

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

  jq -r --arg n "$theme_name" '
    .themes | to_entries[] | select(.value.vscode.theme_id == $n) | .key
  ' "$_CHROMATICLI_THEMES"
}

_chromaticli_apply() {
  # Skip when running inside an IDE's integrated terminal — the editor already
  # syncs terminal colors to its own theme. Override with CHROMATICLI_FORCE=1.
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

# Re-evaluate on macOS Appearance flip (cheap: one `defaults read` per prompt,
# only acts when the value changed AND a themed dir is currently active).
_chromaticli_precmd_check_appearance() {
  [[ -z "${_CHROMATICLI_ACTIVE-}" ]] && return
  local cur
  cur="$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light)"
  if [[ "$cur" != "${_CHROMATICLI_APPEARANCE-}" ]]; then
    export _CHROMATICLI_APPEARANCE="$cur"
    unset _CHROMATICLI_ACTIVE   # force re-pick + re-emit
    _chromaticli_apply
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd  _chromaticli_apply
add-zsh-hook precmd _chromaticli_precmd_check_appearance

# Apply once on shell init for the spawning directory.
_chromaticli_apply

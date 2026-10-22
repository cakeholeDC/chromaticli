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

_chromaticli_check_install_version() {
  [[ -n "${_CHROMATICLI_SYNC_CHECKED-}" ]] && return
  _CHROMATICLI_SYNC_CHECKED=1
  local marker="${XDG_CONFIG_HOME:-$HOME/.config}/chromaticli/install-version.json"
  local cli="$HOME/.local/bin/chromaticli" reported result
  local recovery='chromaticli install --force'
  if [[ -x "$_CHROMATICLI_DIR/chromaticli" ]]; then
    cli="$_CHROMATICLI_DIR/chromaticli"
    recovery="env CHROMATICLI_LIBEXEC=\"$_CHROMATICLI_DIR\" \"$cli\" install --force"
  fi
  if [[ ! -f "$marker" ]]; then
    result=stale
  elif [[ ! -x "$cli" ]] || ! reported=$("$cli" --version 2>/dev/null); then
    result=unverifiable
  else
    result=$(jq -er --arg reported "$reported" '
      if .schema == 1 and (.version | type) == "string" then
        if ($reported | test("^chromaticli [0-9]+\\.[0-9]+\\.[0-9]+([-+][0-9A-Za-z.+-]+)?$") | not) then "unverifiable"
        elif $reported == ("chromaticli " + .version) then "current"
        else "stale" end
      else "unverifiable" end
    ' "$marker" 2>/dev/null) || result=unverifiable
  fi
  case "$result" in
    stale) printf "\n[WARN]: chromaticli: version mismatch detected; run \`%s\`, then restart your shell.\n" "$recovery" >&2 ;;
    unverifiable) printf "\n[WARN]: chromaticli: could not verify installed versions; run \`%s\`, then restart your shell.\n" "$recovery" >&2 ;;
  esac
}

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
  local palette
  # shellcheck disable=SC2034  # used by zsh parameter expansion below
  palette=$(jq -r --arg t "$theme" '
    .themes[$t].palette |
    (.foreground // ""), (.background // ""), (.cursor // ""),
    (.ansi[] // "")
  ' "$_CHROMATICLI_THEMES") || return 1
  local lines=("${(@f)palette}")
  local fg=${lines[1]} bg=${lines[2]} cur=${lines[3]}
  [[ -z "$bg" ]] && return 1
  [[ -n "$fg"  ]] && _chromaticli_osc "10;$fg"
  [[ -n "$bg"  ]] && _chromaticli_osc "11;$bg"
  [[ -n "$cur" ]] && _chromaticli_osc "12;$cur"
  local i=0 entry
  for entry in "${lines[@]:3}"; do
    [[ -n "$entry" ]] && _chromaticli_osc "4;$i;$entry"
    (( i++ ))
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
      printf '%s' "$dir/.vscode/settings.json"
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

  local settings_vals
  # shellcheck disable=SC2034  # used by zsh parameter expansion below
  settings_vals=$(jq -r '
    (."window.autoDetectColorScheme" // ""),
    (."workbench.preferredLightColorTheme" // ""),
    (."workbench.preferredDarkColorTheme" // ""),
    (."workbench.colorTheme" // "")
  ' "$settings") || return 1
  local vals=("${(@f)settings_vals}")
  local auto=${vals[1]} pref_light=${vals[2]} pref_dark=${vals[3]} single=${vals[4]}
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

  jq -r --arg n "$theme_name" '
    .themes | to_entries[] | select(.value.vscode.theme_id == $n or ((.value.vscode.legacy_theme_ids // []) | index($n) != null)) | .key
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

_chromaticli_finish_initial_prompt() {
  _chromaticli_apply
}

# Powerlevel10k keeps stdout and stderr redirected through initialization.
# Its first precmd hook schedules cleanup after precmd handlers have run, so a
# zero-delay scheduled callback can still write into the capture. Keep the
# version warning pending until a later precmd, when P10K has removed its
# instant-prompt marker and restored the normal terminal streams.
_chromaticli_check_version_after_instant_prompt() {
  [[ -n "${__p9k_instant_prompt_active-}" ]] && return
  add-zsh-hook -d precmd _chromaticli_check_version_after_instant_prompt
  _chromaticli_check_install_version
}

_chromaticli_after_initial_prompt() {
  add-zsh-hook -d precmd _chromaticli_after_initial_prompt
  sched +0 _chromaticli_finish_initial_prompt
}

autoload -Uz add-zsh-hook
zmodload zsh/sched 2>/dev/null || true
add-zsh-hook chpwd  _chromaticli_apply
add-zsh-hook precmd _chromaticli_precmd_check_appearance
add-zsh-hook precmd _chromaticli_after_initial_prompt
add-zsh-hook precmd _chromaticli_check_version_after_instant_prompt

# chromaticli — sync terminal colors with VSCode workspace themes.
# chromaticli :: hook.fish
# Sourced via ~/.config/fish/conf.d/chromaticli.fish (auto-sourced by fish).
# On every directory change (--on-variable PWD), reads .vscode/settings.json
# from the current dir tree and emits OSC color escapes to /dev/tty.
# Resets on cd out. Appearance re-check runs on every prompt draw.
#
# OSC codes used: same as hook.zsh and hook.bash (OSC 4/10/11/12/104/110/111/112)

set -g _chromaticli_dir (dirname (status filename))
set -g _chromaticli_themes $_chromaticli_dir/themes.json

function _chromaticli_osc
    set -l body $argv[1]
    if set -q TMUX
        printf '\ePtmux;\e\033]%s\007\e\\' $body >/dev/tty
    else
        printf '\033]%s\007' $body >/dev/tty
    end
end

function _chromaticli_emit
    set -l theme $argv[1]
    command -q jq; or return 1

    set -l fg  (jq -r --arg t $theme '.themes[$t].palette.foreground // empty' $_chromaticli_themes)
    set -l bg  (jq -r --arg t $theme '.themes[$t].palette.background // empty' $_chromaticli_themes)
    set -l cur (jq -r --arg t $theme '.themes[$t].palette.cursor     // empty' $_chromaticli_themes)
    test -z "$bg"; and return 1

    test -n "$fg";  and _chromaticli_osc "10;$fg"
    test -n "$bg";  and _chromaticli_osc "11;$bg"
    test -n "$cur"; and _chromaticli_osc "12;$cur"

    # ponytail: one jq call for all 16 ANSI entries via space-joined output.
    # Full consolidation to a single call like zsh/bash is blocked by fish
    # dropping empty lines from command substitution. Use @base64 encoding
    # as the upgrade path if themes with missing ANSI entries are ever added.
    set -l ansi_joined (jq -r --arg t $theme \
        '[.themes[$t].palette.ansi[] // ""] | join(" ")' $_chromaticli_themes)
    set -l ansi (string split " " $ansi_joined)
    for i in (seq 0 15)
        set -l color $ansi[(math $i + 1)]
        test -n "$color"; and _chromaticli_osc "4;$i;$color"
    end
end

function _chromaticli_reset
    _chromaticli_osc "110"
    _chromaticli_osc "111"
    _chromaticli_osc "112"
    _chromaticli_osc "104"
end

function _chromaticli_find_settings
    set -l dir $PWD
    while test "$dir" != /
        if test -f "$dir/.vscode/settings.json"
            echo "$dir/.vscode/settings.json"
            return 0
        end
        set dir (dirname $dir)
    end
    return 1
end

function _chromaticli_pick
    set -l settings (_chromaticli_find_settings 2>/dev/null)
    # `set` exits 0 even when the substitution fails — test the value, not the status.
    test -n "$settings"; or return 1
    command -q jq; or return 1

    set -l auto       (jq -r '."window.autoDetectColorScheme"       // empty' $settings)
    set -l pref_light (jq -r '."workbench.preferredLightColorTheme" // empty' $settings)
    set -l pref_dark  (jq -r '."workbench.preferredDarkColorTheme"  // empty' $settings)
    set -l single     (jq -r '."workbench.colorTheme"               // empty' $settings)

    set -l theme_name
    if test "$auto" = true -a -n "$pref_light" -a -n "$pref_dark"
        # Note: in light mode, `defaults read -g AppleInterfaceStyle` exits non-zero
        # and emits nothing. fish's `test` treats the empty substitution as `test "" = Dark`,
        # which correctly evaluates to false — light theme is selected. The behavior is
        # correct, but the expression is fragile. A more explicit form would be:
        #   set -l appearance (defaults read -g AppleInterfaceStyle 2>/dev/null; or echo Light)
        #   if test "$appearance" = Dark
        # Implement whichever form; both produce correct output.
        if test (defaults read -g AppleInterfaceStyle 2>/dev/null) = Dark
            set theme_name $pref_dark
        else
            set theme_name $pref_light
        end
    else if test -n "$single"
        set theme_name $single
    else
        return 1
    end

    jq -r --arg n $theme_name \
        '.themes | to_entries[] | select(.value.vscode.theme_id == $n) | .key' \
        $_chromaticli_themes
end

function _chromaticli_apply
    if not set -q CHROMATICLI_FORCE
        switch "$TERM_PROGRAM"
            case vscode cursor
                return
        end
    end

    set -l theme (_chromaticli_pick 2>/dev/null)
    # `set` exits 0 even when the substitution fails — test the value directly.
    if test -z "$theme"
        if set -q _CHROMATICLI_ACTIVE
            _chromaticli_reset
            set -e _CHROMATICLI_ACTIVE
        end
        return
    end

    if test "$theme" != "$_CHROMATICLI_ACTIVE"
        _chromaticli_emit $theme
        and set -gx _CHROMATICLI_ACTIVE $theme
    end
end

function _chromaticli_check_appearance --on-event fish_prompt
    set -q _CHROMATICLI_ACTIVE; or return
    set -l cur (defaults read -g AppleInterfaceStyle 2>/dev/null; or echo Light)
    if test "$cur" != "$_CHROMATICLI_APPEARANCE"
        set -gx _CHROMATICLI_APPEARANCE $cur
        set -e _CHROMATICLI_ACTIVE
        _chromaticli_apply
    end
end

function _chromaticli_on_pwd --on-variable PWD
    _chromaticli_apply
end

_chromaticli_apply

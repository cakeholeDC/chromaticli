# chromaticli — Smoke Test Walkthrough

A numbered, end-to-end **manual** verification checklist. Run each step in
order in a fresh interactive shell. Expected output is shown beneath each
command. This walkthrough covers what can only be verified with a real TTY:
hook loading, OSC emission, `cd`-driven repainting, macOS Appearance flips.

> **Looking for the non-TTY checks?** Those live in [`tests/smoke.sh`](smoke.sh)
> and run automatically in CI. Run them locally with `./tests/smoke.sh` for a
> fast pre-commit sanity sweep (no install required, no real terminal needed).

---

## Prerequisites

- `jq` installed (`brew install jq`)
- A freshly cloned repo at `~/dev/chromaticli` (or wherever you cloned)
- zsh, bash, or fish (the walkthrough below uses zsh; see the shell-specific notes
  at each step for bash and fish equivalents)

---

## Step 1 — Version check

Verify the CLI is runnable before any install step.

```sh
cd ~/dev/chromaticli
./chromaticli --version
```

**Expected:**
```
chromaticli 0.1.0
```

---

## Step 2 — Install

```sh
./chromaticli install
```

**Expected:**
```
installed: /Users/<you>/.config/chromaticli/hook.zsh
installed: /Users/<you>/.config/chromaticli/hook.bash
installed: /Users/<you>/.config/chromaticli/hook.fish
installed: /Users/<you>/.config/chromaticli/themes.json
installed: /Users/<you>/.local/bin/chromaticli
appended source block to /Users/<you>/.zshrc

Open a new shell or run:  exec zsh
```

> **bash users:** replace `~/.zshrc` with `~/.bash_profile` in the `grep` command above.
> The source line will reference `hook.bash` instead of `hook.zsh`.
> The reload hint will say `exec bash`.
>
> **fish users:** no rc file is edited. Instead, verify the conf.d shim exists:
> `ls ~/.config/fish/conf.d/chromaticli.fish`. The reload hint will say `exec fish`.

If `~/.local/bin` is NOT already on your `$PATH`, you'll also see:

```
NOTE: /Users/<you>/.local/bin is not on your $PATH.
  Add it to your shell's rc file, e.g.:
    For zsh:  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
    For bash: echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bash_profile
    For fish: fish_add_path ~/.local/bin
```

Add that line if shown, then start a new shell session (or run `exec zsh`,
`exec bash`, or `exec fish`) to pick it up.

After shell setup, if `code` is available, install also reports:

```
installing bundled VS Code themes: /Users/<you>/.config/chromaticli/vscode-extension/chromaticli-themes-0.0.1.vsix
installed VS Code themes: chromaticli.chromaticli-themes@0.0.1
```

If `code` is unavailable, the shell setup remains usable and the command
prints instructions for installing the bundled VSIX later.

Verify the CLI is now on `$PATH`:

```sh
which chromaticli
```

**Expected:** `/Users/<you>/.local/bin/chromaticli`

Verify the source block was appended:

```sh
grep -A1 "# chromaticli" ~/.zshrc
```

**Expected:**
```
# chromaticli — auto-pair terminal colors to .vscode/settings.json
source "/Users/<you>/.config/chromaticli/hook.zsh"
```

Re-running install should be idempotent:

```sh
./chromaticli install
```

**Expected:** `already present: ...hook.zsh`, `already present: ...hook.bash`,
`already present: ...hook.fish`, `already present: ...themes.json`, and
`already present: ...local/bin/chromaticli` (no second source block added).

---

## Step 3 — Reload shell with hook

```sh
exec zsh   # or: exec bash / exec fish
```

**Expected:** Shell reloads without errors or warnings. The hook is now loaded.
Confirm with:

```sh
which _chromaticli_apply
```

**Expected:** `_chromaticli_apply` (or `_chromaticli_apply is a shell function`)

> **bash users:** `which _chromaticli_apply` will not work (bash doesn't support `which`
> for functions). Use `type _chromaticli_apply` instead.
>
> **fish users:** use `type -t _chromaticli_apply` or `functions _chromaticli_apply`.

---

## Step 4 — List themes

```sh
chromaticli list
```

**Expected:** Categorized output with four sections (Core, Light, Dark, Defaults).
Each entry is numbered and shows two adjacent
color strips:

1. **4 swatches** of the theme's background color (so the eye sees "this is
   what the terminal will look like behind text")
2. a single uncolored space (terminal default — gives a visible gap)
3. the **16 ANSI palette** swatches

A final "Pairs" section lists `default` and the seven color pairs (pair entries have
no swatches: they show their light/dark theme members instead). There are 23
bundled color themes; numbering follows the displayed category order, so use
theme IDs rather than relying on a number.

Example excerpt (colors render as blocks in a color-capable terminal — the
wider left block is the bg color, narrower right strip is the palette):
```
── Core ──────────────────────────────────────────────────────

 1. red                  ████████ ████████████████████████████████
 2. orange               ████████ ████████████████████████████████
 3. yellow               ████████ ████████████████████████████████
...
── Pairs (auto light/dark) ───────────────────────────────────

24. default              (light: light ↔ dark: dark)
29. blue-pair            (light: light-blue ↔ dark: dark-blue)
```

---

## Step 5 — Set a single theme

Create a test project and set a theme:

```sh
mkdir -p /tmp/myproject
cd /tmp/myproject
chromaticli set dark-green
```

**Expected:**
```
wrote /tmp/myproject/.vscode/settings.json
```

Verify settings.json:

```sh
cat .vscode/settings.json
```

**Expected:**
```json
{
  "workbench.colorTheme": "chromaticli dark-green"
}
```

The terminal should repaint to dark-green's palette. The VS Code picker should
offer `chromaticli dark-green` after the local theme VSIX is installed.

---

## Step 6 — Auto-apply on cd

In the same shell (hook must be loaded):

```sh
cd /tmp
```

**Expected:** Terminal resets to your profile's default colors (no active theme).

```sh
cd /tmp/myproject
```

**Expected:** Terminal repaints to dark-green again, no visible flicker.

Check `_CHROMATICLI_ACTIVE`:

```sh
echo $_CHROMATICLI_ACTIVE
```

**Expected:** `dark-green`

---

## Step 7 — Set a light/dark pair

```sh
chromaticli set --pair blue-pair
```

**Expected:**
```
wrote /tmp/myproject/.vscode/settings.json
```

Verify settings.json:

```sh
cat .vscode/settings.json
```

**Expected:**
```json
{
  "window.autoDetectColorScheme": true,
  "workbench.preferredLightColorTheme": "chromaticli light-blue",
  "workbench.preferredDarkColorTheme": "chromaticli dark-blue"
}
```

The terminal should display light-blue in Light mode and dark-blue in Dark
mode. Toggle macOS Appearance (System Settings → Appearance) and switch
between Light and Dark — the terminal should flip automatically within one
prompt cycle.

---

## Step 8 — Unset theme

```sh
chromaticli unset
```

**Expected:**
```
cleared theme keys from /tmp/myproject/.vscode/settings.json
```

Verify settings.json:

```sh
cat .vscode/settings.json
```

**Expected:** `{}` (empty object, file is not deleted)

The terminal should reset to profile defaults immediately.

---

## Step 9 — cd out of themed directory

```sh
cd /tmp
```

**Expected:** Terminal remains at profile defaults (no active theme to apply).
`$_CHROMATICLI_ACTIVE` should be unset:

```sh
echo "${_CHROMATICLI_ACTIVE:-<unset>}"
```

**Expected:** `<unset>`

---

## Step 10 — Uninstall

Run from any directory (the CLI is on `$PATH`):

```sh
chromaticli uninstall
```

**Expected:**
```
removed: /Users/<you>/.local/bin/chromaticli
removed: /Users/<you>/.config/chromaticli
removed chromaticli block from /Users/<you>/.zshrc (lines N–M)
backup saved to /Users/<you>/.zshrc.chromaticli.bak
chromaticli hook is not installed in /Users/<you>/.bash_profile — nothing to remove.
not present: /Users/<you>/.config/fish/conf.d/chromaticli.fish (skipped)

Current terminal repainted to profile defaults.

Project .vscode/ files were left alone (the hook is gone, so they're
inert in any new shell — VSCode still reads them as normal).
```

(The exact output varies by which shells were installed. Each cleanup step reports
its result individually.)

Verify the install footprint is gone:

```sh
ls ~/.local/bin/chromaticli 2>&1
ls ~/.config/chromaticli/ 2>&1
grep -nF "# chromaticli" ~/.zshrc || echo "marker absent"
```

**Expected:**
```
ls: /Users/<you>/.local/bin/chromaticli: No such file or directory
ls: /Users/<you>/.config/chromaticli/: No such file or directory
marker absent
```

Open a new terminal tab. Confirm the hook is gone:

```sh
type _chromaticli_apply 2>&1
```

**Expected:** `_chromaticli_apply not found` (or equivalent "not a shell function" message).

Re-running uninstall should be idempotent (no-op):

```sh
~/dev/chromaticli/chromaticli uninstall
```

**Expected:** Each removal step reports `not present: ... (skipped)` or
`chromaticli hook is not installed in .zshrc — nothing to remove.`

---

## Edge-case checks

| Scenario | Command | Expected |
|---|---|---|
| Unknown subcommand | `chromaticli badcmd` | Exit 2, error to stderr, usage hint |
| Bad theme name | `chromaticli set nonexistent` | Exit 2, "unknown theme" error |
| Bad number | `chromaticli set 99` | Exit 2, "unknown theme/pair/number" error |
| Unset with no settings | `chromaticli unset --project /tmp` | "no theme set for this directory", exit 0 |
| Install idempotent | Run `chromaticli install` twice | No duplicate source block in `.zshrc` |
| --no-install flag | `chromaticli set dark-pink --no-install` | Writes settings.json, skips `code --install-extension`, and reports VS Code may not load the theme |
| Uninstall idempotent | Run `chromaticli uninstall` twice | Second run reports `not present` for each removed item, exit 0 |
| Foreign binary at install path | `echo '#!/bin/sh' > ~/.local/bin/chromaticli; chmod +x ~/.local/bin/chromaticli; ./chromaticli install` | Exit 1, error: "refusing to overwrite ... signature comment missing". Bin is preserved. |
| Foreign binary at uninstall path | (same setup) then `chromaticli uninstall` | Refuses to remove the foreign file (warns), proceeds with the rest of uninstall |
| Sync idempotence regression (Q4.9 guard) | From a themed dir, run `chromaticli set dark-green` twice in a row | Terminal visibly repaints **both** times. A silent second invocation means the `unset _CHROMATICLI_ACTIVE` bypass in `cmd_sync`'s zsh subshell has regressed. |
| `--shell` and `--all-shells` together | `chromaticli install --shell zsh --all-shells` | Exit 2, "mutually exclusive" error |
| bash-only install | `chromaticli install --shell bash`, then `grep "# chromaticli" ~/.bash_profile` | Marker present in `.bash_profile`; `.zshrc` unchanged |

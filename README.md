# ChromatiCLI

<p align="center">
  <img src="logo/chromaticli.svg" alt="chromaticli logo" width="650">
  <br>
  <code>chromaticli</code> /kroʊˈmæ.tɪ.kli/ — pronounced <em>chromatically</em>.
</p>

ChromatiCLI makes your terminal match the VS Code theme for the project you
are in. When you `cd` into a folder with `.vscode/settings.json`, it reads
`workbench.colorTheme` and repaints your terminal automatically.

It works with iTerm2, Terminal.app, Alacritty, Kitty, and any terminal that
supports OSC color sequences.

---

## Why ChromatiCLI

- Helps you tell terminal sessions apart visually.
- Keeps terminal colors aligned with your VS Code workspace theme.
- Automatically reapplies the right palette whenever you change directories.
- Works with project-local `.vscode/settings.json`, so themes follow your repo.

---

## What it does

`chromaticli install` sets up everything needed to keep terminal colors in sync:

- `~/.local/bin/chromaticli` — the CLI executable on your path.
- `~/.config/chromaticli/hook.zsh` — a zsh hook that runs whenever you `cd`.
- `~/.config/chromaticli/themes.json` — the theme and light/dark pair registry.
- A small source block in `~/.zshrc` so the hook loads in every new shell.

Once installed, the hook finds the nearest `.vscode/settings.json`, maps the
workspace theme to a terminal palette, and issues OSC color sequences.

---

## Prerequisites

- zsh — currently the only supported shell, with additional shells planned for future releases
- `jq` (`brew install jq`)

### Optional tools

These are optional helpers for a better developer experience.

| Tool | What it adds | If missing |
|---|---|---|
| [`code`](https://code.visualstudio.com/docs/setup/mac#_launching-from-the-command-line) | `chromaticli set` can auto-install theme extensions | Themes still write to `settings.json`; VS Code prompts you to install on open |
| [`figlet`](https://www.figlet.org) | Fancy help-screen banner | Banner falls back to a simple ASCII box |
| [`lolcat`](https://github.com/busyloop/lolcat) | Rainbow help-screen banner | Banner renders in the default terminal color |

`jq` is the only required dependency because proper JSON merging is essential.

---

## Install

```sh
git clone https://github.com/cakeholeDC/chromaticli ~/dev/chromaticli
cd ~/dev/chromaticli
./chromaticli install
exec zsh
```

If `~/.local/bin` is not on your `PATH`, the installer prints a one-line
`export PATH=...` advisory. It does not modify your path automatically.

The install step is idempotent, so you can run it again safely.

---

## Quick start

```sh
cd ~/some-project          # any project directory
chromaticli set monokai    # writes .vscode/settings.json and repaints terminal
cd ~                       # terminal returns to your default profile
cd ~/some-project          # terminal repaints automatically
```

- Use `chromaticli list` to browse all themes and pairs.
- Run `chromaticli set` without arguments to choose interactively.

---

## Upgrade

If you update the repo, reinstall to refresh the installed copies:

```sh
cd ~/dev/chromaticli
git pull
./chromaticli install --force
```

`--force` overwrites the installed binary, hook, and themes registry. It does
not rewrite your `.zshrc` source block unless that block is missing.

---

## Uninstall

```sh
chromaticli uninstall
```

This removes:

- `~/.local/bin/chromaticli`
- `~/.config/chromaticli/`
- The `chromaticli` source block from `~/.zshrc`

Project `.vscode/settings.json` files are left intact so VS Code continues to
use them normally.

---

## Commands

```sh
chromaticli <subcommand> [options]
chromaticli --help | -h
chromaticli --version | -v
```

| Command | Description |
|---|---|
| `install [--force]` | Install or update the CLI, hook, and theme registry. |
| `uninstall` | Remove installed files and the `.zshrc` source block. |
| `list` | Show available themes and pairs with inline palette previews. |
| `set [<theme\|pair\|N>]` | Apply a theme to the current project. No arg opens an interactive picker. |
| `set --pair <id\|N>` | Apply a light/dark pair and follow macOS Appearance. |
| `set --theme <id\|N>` | Apply a specific single theme. |
| `unset [--project <dir>]` | Remove theme keys from `.vscode/settings.json` only. |
| `preview [<theme\|pair\|N>]` | Temporarily apply a theme without writing files. Lasts until the next `cd`. |
| `sync [--project <dir>]` | Re-emit OSC colors to the current tty. Useful for debugging. |

Every subcommand supports `--help`.

---

## How it works

1. `chromaticli install` copies the CLI and hook into your home config.
2. The hook runs on each `cd`.
3. It looks for the nearest `.vscode/settings.json`.
4. If a `workbench.colorTheme` is found, it maps that theme to a terminal palette.
5. The hook emits OSC color escapes for foreground, background, cursor, and ANSI colors.
6. In tmux, it wraps the sequences so the terminal receives them correctly.
7. Inside VS Code / Cursor integrated terminals, the hook skips emission by default
   because those environments already control terminal colors.

For light/dark pairs, the hook also re-checks macOS appearance and reapplies
colors when the system changes.

---

## Themes

ChromatiCLI includes 12 curated themes and 2 light/dark pairs.

- Dark warm/earthy: `grass`, `kimbie-dark`, `monokai`, `red-sands`
- Dark cool/blue: `abyss`, `dark-modern`, `dark-pink`, `ocean`, `purple-rain`, `solarized-dark`
- Light: `light-modern`, `solarized-light`
- Pairs: `default` (light-modern ↔ dark-modern), `solarized` (solarized-light ↔ solarized-dark)

See the gallery at [`docs/theme_preview.md`](docs/theme_preview.md) or
[`docs/theme_preview.html`](docs/theme_preview.html).

---

## Troubleshooting

**The terminal doesn’t change colors after `cd`.**

- There is no `.vscode/settings.json` in this directory or any parent.
  Run `chromaticli set <theme>` to create one.
- You are in a VS Code or Cursor integrated terminal. The hook skips OSC
  emission there by default. Use `CHROMATICLI_FORCE=1` to override.
- The hook isn’t loaded. `which _chromaticli_apply` should print
  `shell function`. If it does not, run `exec zsh`.
- Your terminal does not support OSC 4/10/11/12. Test with:

  ```sh
  printf '\e]11;#ff0000\007'
  ```

**Nothing changes in tmux.**

Add `set -g allow-passthrough on` to `~/.tmux.conf` and reload tmux.
The hook already wraps emissions for passthrough; tmux must forward them.

**`set --pair` does not follow Light/Dark on Linux.**

Appearance detection currently uses `defaults read -g AppleInterfaceStyle`
on macOS only. On other platforms, pair mode defaults to the light theme.
Single themes still work cross-platform.

**I pulled new repo code but behavior is still old.**

The installed files live in `~/.local/bin/` and `~/.config/chromaticli/`.
Run `./chromaticli install --force` from the repo to update them.

**`install` refuses to overwrite `~/.local/bin/chromaticli`.**

That means another file already exists there. Inspect it, remove or rename it,
then rerun install.

---

## Configuration

`chromaticli` is mostly zero-config.

| Environment variable | Effect |
|---|---|
| `CHROMATICLI_FORCE=1` | Force OSC emission even inside VS Code / Cursor integrated terminals. |

---

## Walkthrough

For a guided install/test/uninstall flow with expected output, see
[`tests/SMOKE_TEST.md`](tests/SMOKE_TEST.md).

---

## Project layout

```text
/chromaticli          bash CLI executable
/hook.zsh             zsh hook sourced by `.zshrc`
/themes.json          theme and pair registry
/tests/SMOKE_TEST.md  manual walkthrough
/docs/
  theme_preview.md    theme gallery for GitHub
  theme_preview.html  standalone preview page
  themes/*.svg        per-theme mock-terminal previews
```

# Contributing to chromaticli

Thanks for your interest. Contributions are welcome — the most common paths are
adding a theme and adding a new shell. All changes, including maintainer
changes, go through pull requests.

## Setup

```sh
git clone https://github.com/cakeholeDC/chromaticli
cd chromaticli
brew install jq          # only hard dependency
./tests/smoke.sh         # must pass before and after your change
```

## Pull request titles

Pull requests are squash merged, so the title becomes the commit on `main`.
Use a Conventional Commit title:

```text
type: description
type(scope): description
type(scope)!: breaking description
```

Accepted types are `feat`, `fix`, `docs`, `ci`, `chore`, `refactor`, `perf`,
`test`, `build`, `style`, and `revert`. Scopes are optional and are not
restricted.

Examples:

```text
feat(hooks): support a new shell
fix(cli): preserve settings when an update fails
docs: explain fish installation
```

Use `feat` for a user-visible feature and `fix` for a user-visible bug fix.
Before version 1.0, a breaking change marked with `!` bumps the minor version.
Moving to 1.0 is an explicit maintainer decision.

## Releases

Release Please runs after a pull request is merged to `main`. It opens or
updates a release pull request containing the changelog, version update, and
release manifest. Merging that pull request creates the `vX.Y.Z` tag and GitHub
release. Do not create release tags or edit generated release files manually.

The first release is explicitly bootstrapped as `v0.1.0` in the Release Please
configuration. Remove that one-time `release-as` override after `v0.1.0` is
published so later versions return to Conventional Commit calculation.

## Adding a theme

The registry is curated, not exhaustive. Before adding a theme, check that it
adds a distinct color identity:

- Prefer VS Code built-ins (`vscode.extension_id: null`). They have no
  marketplace dependency, no install step, and cannot drift across extension
  versions.
- Use one representative per color identity. If a new theme is visually close to
  an existing entry, it probably weakens the registry.
- Removing is allowed. If a new theme supersedes an existing entry, drop the
  older one in the same change.
- Sort `.themes` entries alphabetically by id.
- Keep palette formatting compact: `background`, `foreground`, and `cursor` each
  on their own line; the 16-entry `ansi` array split into two lines of 8
  entries.

1. Edit `themes.json` — add your entry alphabetically by id.
2. Run `python3 scripts/verify-themes.py` — must exit 0.
3. Run `python3 scripts/generate-preview.py` — regenerates SVG/HTML/MD previews.
4. Commit `themes.json` and the regenerated preview files together.

CI enforces both steps; a PR that fails either job will not be merged.

## Adding a shell

Adding a shell requires changes across several files. Before starting, open an
issue to confirm the shell is in scope and discuss the approach.

At minimum a new shell requires:

- A new `hook.<shell>` file at the repo root (OSC emission, directory-change
  detection, appearance re-check, reset on cd-out)
- `chromaticli install`: copy the new hook, add `--shell <name>` detection,
  add an `_install_rc_<shell>` helper, update `_hook_is_installed_anywhere`
- `chromaticli uninstall`: add cleanup step for the new shell's rc artifact
- `_detect_shell` and `_active_hook`: add the new shell to both case statements
- `cmd_sync` and `cmd_preview`: add the new shell's spawn form
- `tests/smoke.sh`: new install/uninstall/wiring tests
- `tests/SMOKE_TEST.md`: new shell-specific notes
- `README.md`: update prerequisites and shell-specific install notes
- `.github/workflows/ci.yml`: add syntax check for the new hook file

The existing bash and fish implementations are the reference. Model your hook
on `hook.bash` (for POSIX-adjacent shells) or `hook.fish` (for shells with
native directory-change events).

## Pull request checklist

- `./tests/smoke.sh` passes locally
- The pull request title follows the Conventional Commit format above
- For theme PRs: `verify-themes.py` and `generate-preview.py` both ran and their
  outputs are committed
- For hook/install changes: new smoke tests added and passing
- No new dependencies introduced

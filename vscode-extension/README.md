# chromaticli themes

The local theme extension contributes 23 original VS Code themes named
`chromaticli <color-id>`. `themes.json` owns the terminal palettes, and
`scripts/generate-vscode-themes.py` copies those colors into each definition.

| Color family | Theme IDs |
|---|---|
| Red | `red`, `light-red`, `dark-red` |
| Orange | `orange`, `light-orange`, `dark-orange` |
| Yellow | `yellow`, `light-yellow`, `dark-yellow` |
| Green | `green`, `light-green`, `dark-green` |
| Blue | `blue`, `light-blue`, `dark-blue` |
| Indigo | `indigo`, `light-indigo`, `dark-indigo` |
| Violet | `violet`, `light-violet`, `dark-violet` |
| Neutral | `light`, `dark` |

Some IDs retain prior workspace labels as read-only aliases in `themes.json`.
Projects using removed or renamed picker labels should select the new theme
with `chromaticli set <color-id>`. The former `solarized` pair is retired.

From the repository root, regenerate and verify the terminal colors:

```sh
python3 scripts/generate-vscode-themes.py
python3 scripts/generate-vscode-themes.py --check
python3 scripts/verify-themes.py
python3 tests/verify-bundled-themes.py
```

Edit workbench and token colors in `themes/<color-id>.json`. `themes.json` owns
`terminal.background`, `terminal.foreground`, `terminalCursor.*`, and all 16
`terminal.ansi*` entries. The generator copies these RGB values exactly.

From the repository root, rebuild the tracked VSIX with Microsoft's
development-only VSIX packager:

```sh
./scripts/update-vsix.sh
python3 tests/verify-bundled-themes.py
```

The script reads the extension package metadata to choose the output filename.
Commit the generated VSIX with any theme source changes. Install the matching
VSIX from `vscode-extension/` with the `code` CLI to preview it in VS Code.

Then choose a `chromaticli` theme from **Preferences: Color Theme**. Terminal
testing can use `chromaticli preview <color-id>` without installing the VSIX.

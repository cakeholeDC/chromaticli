#!/usr/bin/env python3
"""Refresh registry-owned terminal colors; --check fails on stale output."""

import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent


def terminal_colors(palette):
    ansi_names = (
        "Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White",
        "BrightBlack", "BrightRed", "BrightGreen", "BrightYellow",
        "BrightBlue", "BrightMagenta", "BrightCyan", "BrightWhite",
    )
    if len(palette["ansi"]) != 16 or any(
        not re.fullmatch(r"#[0-9a-fA-F]{6}", color)
        for color in [palette["background"], palette["foreground"], palette["cursor"], *palette["ansi"]]
    ):
        raise ValueError("expected background, foreground, cursor and 16 ANSI RGB colors")
    return {
        "terminal.background": palette["background"],
        "terminal.foreground": palette["foreground"],
        "terminalCursor.foreground": palette["cursor"],
        "terminalCursor.background": palette["background"],
        **{f"terminal.ansi{name}": color for name, color in zip(ansi_names, palette["ansi"])},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    themes = json.loads((ROOT / "themes.json").read_text())["themes"]
    extension = ROOT / "vscode-extension"
    contributed = json.loads((extension / "package.json").read_text())["contributes"]["themes"]
    stale = []
    for tid, entry in themes.items():
        if entry["vscode"].get("source") != "bundled":
            continue
        matches = [t for t in contributed if t["label"] == entry["vscode"]["theme_id"]]
        if len(matches) != 1:
            parser.exit(1, f"{tid}: expected exactly one contributed theme label\n")
        path = (extension / matches[0]["path"]).resolve()
        path.relative_to(extension.resolve())
        theme = json.loads(path.read_text())
        expected = terminal_colors(entry["palette"])
        if args.check:
            if any(theme["colors"].get(key) != color for key, color in expected.items()):
                stale.append(tid)
        else:
            theme["colors"].update(expected)
            temp = path.with_suffix(".json.tmp")
            temp.write_text(json.dumps(theme, indent=2) + "\n")
            temp.replace(path)
            print(f"wrote {path.relative_to(ROOT)}")
    if stale:
        parser.exit(1, f"stale terminal colors ({', '.join(stale)}): run python3 scripts/generate-vscode-themes.py\n")
    if args.check:
        print("OK: all bundled terminal colors match themes.json")


if __name__ == "__main__":
    main()

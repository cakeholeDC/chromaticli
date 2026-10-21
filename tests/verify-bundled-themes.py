#!/usr/bin/env python3
"""Run with python3 tests/verify-bundled-themes.py; no network or registry edits."""

import copy
import colorsys
import json
from pathlib import Path
import re
import runpy
from zipfile import ZipFile

root = Path(__file__).resolve().parent.parent
verifier = runpy.run_path(str(root / "scripts/verify-themes.py"))
verify = verifier["verify_bundled"]
themes = json.loads((root / "themes.json").read_text())["themes"]
palette = themes["blue"]["palette"]
vs = {"source": "bundled", "extension_id": "chromaticli.chromaticli-themes", "theme_id": "chromaticli blue"}

assert verify(vs, palette)[0] == "BUNDLED_OK"
status, detail = verify({**vs, "theme_id": "chromaticli bleu"}, palette)
assert status == "BUNDLED_ERROR" and "contributed label" in detail, detail

changed = copy.deepcopy(palette)
changed["ansi"][0] = "#010203"
status, detail = verify(vs, changed)
assert status == "BUNDLED_ERROR" and "terminal.ansiBlack" in detail, detail
print("OK: bundled Blue matches; misspelled label and terminal-color mismatch fail")

manifest = json.loads((root / "vscode-extension/package.json").read_text())
assert list(themes) == sorted(themes)
assert len(manifest["contributes"]["themes"]) == len(themes)
vsix_path = root / f"vscode-extension/chromaticli-themes-{manifest['version']}.vsix"
with ZipFile(vsix_path) as vsix:
    archived_manifest = json.loads(vsix.read("extension/package.json"))
    assert archived_manifest == manifest
    assert vsix.read("extension/readme.md") == (root / "vscode-extension/README.md").read_bytes()
    assert vsix.read("extension/LICENSE.txt") == (root / "vscode-extension/LICENSE").read_bytes()
    archived_themes = {
        path.removeprefix("extension/themes/").removesuffix(".json")
        for path in vsix.namelist()
        if path.startswith("extension/themes/") and path.endswith(".json")
    }
    assert archived_themes == set(themes), sorted(archived_themes ^ set(themes))
    for theme_id in themes:
        archive_theme = json.loads(vsix.read(f"extension/themes/{theme_id}.json"))
        source_theme = json.loads((root / f"vscode-extension/themes/{theme_id}.json").read_text())
        assert archive_theme == source_theme, theme_id
for tid, entry in themes.items():
    assert entry["vscode"]["theme_id"] == f"chromaticli {tid}"
    if tid in {"red", "orange", "yellow", "green", "blue", "indigo", "violet"}:
        expected_category = "core"
    elif tid in {"light", "dark"}:
        expected_category = "defaults"
    elif tid.startswith("light-"):
        expected_category = "light"
    else:
        expected_category = "dark"
    assert entry["category"] == expected_category, tid
    assert verify(entry["vscode"], entry["palette"])[0] == "BUNDLED_OK", tid
    theme = json.loads((root / f"vscode-extension/themes/{tid}.json").read_text())
    assert theme["name"] == f"chromaticli {tid}"
    assert theme["type"] == ("light" if entry["category"] == "light" or tid == "light" else "dark")
    assert theme["colors"]["editor.background"] == entry["palette"]["background"]
    assert theme["colors"]["editor.foreground"] == entry["palette"]["foreground"]
    assert theme["tokenColors"] and theme["semanticTokenColors"] and theme["semanticHighlighting"]

preview = (root / "docs/theme_preview.md").read_text()
html_preview = (root / "docs/theme_preview.html").read_text()
expected_sections = {
    "Core": ["red", "orange", "yellow", "green", "blue", "indigo", "violet"],
    "Light": [f"light-{hue}" for hue in ("red", "orange", "yellow", "green", "blue", "indigo", "violet")],
    "Dark": [f"dark-{hue}" for hue in ("red", "orange", "yellow", "green", "blue", "indigo", "violet")],
    "Defaults": ["light", "dark"],
}
for section, expected_ids in expected_sections.items():
    body = preview.split(f"## {section}\n\n", 1)[1].split("\n## ", 1)[0]
    assert re.findall(r"<code>([^<]+)</code>", body) == expected_ids, section
    html_body = re.search(
        rf'<section class="theme-section">\s*<h2>{section}</h2>(.*?)</section>',
        html_preview,
        re.DOTALL,
    )
    assert html_body, section
    assert re.findall(r'<figcaption><code>([^<]+)</code></figcaption>', html_body.group(1)) == expected_ids, section

adjusted_text_ids = (
    "yellow", "light-yellow", "dark-yellow",
    "green", "light-green", "dark-green",
    "indigo", "light-indigo", "dark-indigo",
)

def hue_saturation(color):
    rgb = [int(color[index:index + 2], 16) / 255 for index in (1, 3, 5)]
    hue, _, saturation = colorsys.rgb_to_hls(*rgb)
    return hue * 360, saturation


def assert_monochrome(color, target_hue, theme_id, source):
    hue, saturation = hue_saturation(color[:7])
    if saturation > 0.2:
        distance = abs((hue - target_hue + 180) % 360 - 180)
        assert distance <= 12, (theme_id, source, color, round(distance, 1))


semantic_hues = {
    1: ((0, 25), (330, 360)),  # red
    2: ((80, 165),),           # green
    3: ((38, 80),),            # yellow
    4: ((190, 275),),          # blue
    5: ((275, 330),),          # magenta
    6: ((165, 225),),          # cyan
}


def assert_terminal_text_variety(theme_id, ansi):
    for index, hue_ranges in semantic_hues.items():
        hue, saturation = hue_saturation(ansi[index])
        assert saturation >= 0.35 and any(
            low <= hue < high for low, high in hue_ranges
        ), (theme_id, f"ANSI {index}", ansi[index], round(hue, 1), round(saturation, 2))


def color_values(value, path="theme"):
    if isinstance(value, dict):
        for key, nested in value.items():
            yield from color_values(nested, f"{path}.{key}")
    elif isinstance(value, list):
        for index, nested in enumerate(value):
            yield from color_values(nested, f"{path}[{index}]")
    elif isinstance(value, str) and re.fullmatch(r"#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?", value):
        yield path, value


for theme_id in adjusted_text_ids:
    entry = themes[theme_id]
    target_hue, _ = hue_saturation(entry["palette"]["background"])
    assert_terminal_text_variety(theme_id, entry["palette"]["ansi"])
    theme = json.loads((root / f"vscode-extension/themes/{theme_id}.json").read_text())
    # Keep the VS Code editor and workbench colors monochromatic. The
    # integrated terminal ANSI palette follows the richer terminal palette.
    editor_theme = {
        **theme,
        "colors": {
            key: value for key, value in theme["colors"].items()
            if not key.startswith(("terminal.", "terminalCursor."))
        },
    }
    for path, color in color_values(editor_theme):
        assert_monochrome(color, target_hue, theme_id, path)

# Distinct sentinels catch ANSI index shifts in the shared generator itself.
terminal_colors = verifier["terminal_colors"]
sample = {"background":"#123456", "foreground":"#654321", "cursor":"#abcdef",
          "ansi":[f"#{i:06x}" for i in range(16)]}
colors = terminal_colors(sample)
assert colors["terminal.background"] == "#123456"
assert colors["terminal.foreground"] == "#654321"
assert colors["terminalCursor.foreground"] == "#abcdef"
assert colors["terminalCursor.background"] == "#123456"
for i, name in enumerate(("Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White")):
    assert colors[f"terminal.ansi{name}"] == f"#{i:06x}"
    assert colors[f"terminal.ansiBright{name}"] == f"#{i + 8:06x}"
for bad in ({**sample,"ansi":sample["ansi"][:-1]}, {**sample,"background":"#123"}):
    try:
        terminal_colors(bad)
    except ValueError:
        pass
    else:
        raise AssertionError("invalid terminal palette accepted")

# Original light palettes keep every ANSI slot readable without the editor's
# optional minimum-contrast adjustment, including nominal white slots.
def luminance(color):
    rgb = [int(color[i:i+2], 16) / 255 for i in (1, 3, 5)]
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
    return sum(c * weight for c, weight in zip(linear, (0.2126, 0.7152, 0.0722)))

for tid in ("light", "dark", "violet"):
    palette = themes[tid]["palette"]
    _, saturation = hue_saturation(palette["cursor"])
    background_luminance = luminance(palette["background"])
    cursor_luminance = luminance(palette["cursor"])
    contrast = (max(background_luminance, cursor_luminance) + 0.05) / (min(background_luminance, cursor_luminance) + 0.05)
    assert saturation <= 0.12, (tid, "cursor should be neutral gray", palette["cursor"], saturation)
    assert contrast >= 3.0, (tid, "cursor should contrast with background", palette["cursor"], contrast)

for tid in ("light-blue", "light-green", "light-indigo", "light-orange", "light-red", "light-violet", "light-yellow"):
    palette = themes[tid]["palette"]
    theme = json.loads((root / f"vscode-extension/themes/{tid}.json").read_text())
    background = luminance(palette["background"])
    readable = [palette["foreground"], palette["cursor"], *palette["ansi"],
                *(token["settings"]["foreground"] for token in theme["tokenColors"] if "foreground" in token["settings"])]
    for color in readable:
        contrast = (background + 0.05) / (luminance(color) + 0.05)
        assert contrast >= 4.5, (tid, color, contrast)
print("OK: all bundled definitions, ANSI generation, invalid inputs and original light-theme contrast")

#!/usr/bin/env python3
# chromaticli :: generate-preview.py
# Reads themes.json and emits:
#   docs/themes/<theme-id>.svg     — mock-terminal preview per theme
#   docs/theme_preview.html        — local-file gallery
#   docs/theme_preview.md          — GitHub-renderable gallery (same SVGs)
#
# Run after adding/changing any entry under `.themes` in themes.json.
# CI lint gate: `git diff --exit-code docs/themes/ docs/theme_preview.html docs/theme_preview.md`
# fails if a themes.json edit landed without regenerating these artifacts.

from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
THEMES = ROOT / "themes.json"
OUT_DIR = ROOT / "docs" / "themes"
HTML_PATH = ROOT / "docs" / "theme_preview.html"
MD_PATH = ROOT / "docs" / "theme_preview.md"

W, H = 280, 170
TITLE_H = 24
SWATCH_H = 8
PAD = 10


def svg(theme_id: str, palette: dict) -> str:
    bg = palette["background"]
    fg = palette["foreground"]
    cur = palette["cursor"]
    ansi = palette["ansi"]

    # Body lines: imitate a small git-status session, using several ANSI hues.
    lines = [
        (fg, "❯ git status"),
        (ansi[7], "On branch main"),
        (ansi[3], "  modified: README.md"),
        (ansi[2], "  new:      theme_preview.html"),
        (ansi[1], "  deleted:  old.py"),
        (ansi[4], "❯ echo $SHELL"),
        (fg, "/bin/zsh"),
    ]

    line_y0 = TITLE_H + 16
    line_h = 14
    text_x = PAD

    body_text = "\n".join(
        f'  <text x="{text_x}" y="{line_y0 + i * line_h}" fill="{color}" font-size="11" '
        f'font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace">{esc(text)}</text>'
        for i, (color, text) in enumerate(lines)
    )

    # Bottom ANSI swatch row (16 small rects across)
    swatch_y = H - SWATCH_H - 6
    swatch_w = (W - 2 * PAD) / 16
    swatches = "\n".join(
        f'  <rect x="{PAD + i * swatch_w:.2f}" y="{swatch_y}" width="{swatch_w - 1:.2f}" '
        f'height="{SWATCH_H}" fill="{c}"/>'
        for i, c in enumerate(ansi)
    )

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <!-- body -->
  <rect width="{W}" height="{H}" rx="8" fill="{bg}"/>
  <!-- title bar (translucent dark overlay on bg) -->
  <rect width="{W}" height="{TITLE_H}" rx="8" fill="#000000" fill-opacity="0.28"/>
  <rect y="{TITLE_H - 8}" width="{W}" height="8" fill="#000000" fill-opacity="0.28"/>
  <!-- traffic lights -->
  <circle cx="{PAD + 2}" cy="{TITLE_H / 2}" r="5" fill="#ff5f57"/>
  <circle cx="{PAD + 18}" cy="{TITLE_H / 2}" r="5" fill="#febc2e"/>
  <circle cx="{PAD + 34}" cy="{TITLE_H / 2}" r="5" fill="#28c840"/>
  <!-- title -->
  <text x="{W / 2}" y="{TITLE_H - 7}" fill="{fg}" opacity="0.75" font-size="11"
        text-anchor="middle" font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace">{esc(theme_id)}</text>
{body_text}
  <!-- cursor block at end of last line -->
  <rect x="{text_x + 56}" y="{line_y0 + (len(lines) - 1) * line_h - 10}" width="6" height="12" fill="{cur}" opacity="0.85"/>
{swatches}
</svg>
"""


def esc(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def html_doc(ids: list[str]) -> str:
    cards = "\n".join(
        f'''    <figure class="card">
      <img src="themes/{tid}.svg" alt="{esc(tid)}" loading="lazy"/>
      <figcaption><code>{esc(tid)}</code></figcaption>
    </figure>'''
        for tid in ids
    )
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>chromaticli — preview gallery</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{
    margin: 0; padding: 24px;
    font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: Canvas; color: CanvasText;
  }}
  h1 {{ font-size: 18px; font-weight: 600; margin: 0 0 4px; }}
  p.meta {{ margin: 0 0 24px; opacity: 0.65; font-size: 13px; }}
  .grid {{
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: 18px;
  }}
  .card {{ margin: 0; }}
  .card img {{ display: block; width: 100%; height: auto; border-radius: 8px; box-shadow: 0 1px 4px rgba(0,0,0,0.15); }}
  .card figcaption {{ font-size: 12px; margin-top: 6px; line-height: 1.4; }}
  .card figcaption code {{ font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }}
</style>
</head>
<body>
  <h1>chromaticli — preview gallery</h1>
  <p class="meta">{len(ids)} themes. Generated from <code>themes.json</code> via <code>scripts/generate-preview.py</code>.</p>
  <div class="grid">
{cards}
  </div>
</body>
</html>
"""


def md_doc(themes_data: dict, pairs_data: dict) -> str:
    # Bucket by `category`, alphabetize within each. The order of buckets is fixed.
    BUCKETS = [
        ("dark-warm", "Dark — warm / earthy"),
        ("dark-cool", "Dark — cool / blue"),
        ("light",     "Light"),
    ]

    def cell(tid: str) -> str:
        return (f'<img src="themes/{tid}.svg" width="240" alt="{esc(tid)}"/><br/>'
                f'<code>{esc(tid)}</code>')

    def grid_3col(ids: list[str]) -> str:
        cells = [cell(tid) for tid in ids]
        while len(cells) % 3 != 0:
            cells.append("")
        rows = []
        for i in range(0, len(cells), 3):
            rows.append("| " + " | ".join(cells[i : i + 3]) + " |")
        return "| | | |\n|---|---|---|\n" + "\n".join(rows)

    sections = []
    total = 0
    for cat_key, cat_label in BUCKETS:
        ids = sorted(tid for tid, t in themes_data.items() if t.get("category") == cat_key)
        if not ids:
            continue
        total += len(ids)
        sections.append(f"## {cat_label}\n\n{grid_3col(ids)}")

    # Pair section: each pair as a 2-column "Light | Dark" side-by-side.
    pair_sections = []
    for pid, p in pairs_data.items():
        light_tid, dark_tid = p["light"], p["dark"]
        pair_sections.append(
            f"### `{pid}`\n\n"
            f"| Light | Dark |\n"
            f"|---|---|\n"
            f"| {cell(light_tid)} | {cell(dark_tid)} |"
        )

    pair_block = ""
    if pair_sections:
        pair_block = (
            "## Pairs (auto light/dark)\n\n"
            "Set with `chromaticli set --pair <id>`. On macOS the hook re-evaluates on "
            "every prompt and flips when System Settings → Appearance changes. Other OSes "
            "currently stick on the light half — see Troubleshooting in the README.\n\n"
            + "\n\n".join(pair_sections)
        )

    bucket_count = sum(1 for k, _ in BUCKETS if any(t.get('category') == k for t in themes_data.values()))
    header = (
        "# chromaticli — preview gallery\n\n"
        f"{total} themes in {bucket_count} buckets, plus {len(pairs_data)} auto pairs. "
        "Generated from `themes.json` via `scripts/generate-preview.py`. Pick a card and "
        "pass its id to `chromaticli set`.\n"
    )
    return header + "\n" + "\n\n".join(sections) + ("\n\n" + pair_block if pair_block else "") + "\n"


def main() -> int:
    data = json.loads(THEMES.read_text())
    themes = data["themes"]
    pairs = data.get("pairs", {})
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    ids = list(themes.keys())

    for tid, t in themes.items():
        (OUT_DIR / f"{tid}.svg").write_text(svg(tid, t["palette"]))

    # Purge stale SVGs for themes that were removed from themes.json.
    expected = {f"{tid}.svg" for tid in ids}
    for existing in OUT_DIR.iterdir():
        if existing.name not in expected and existing.suffix == ".svg":
            existing.unlink()
            print(f"removed stale {existing.relative_to(ROOT)}")

    HTML_PATH.write_text(html_doc(ids))
    MD_PATH.write_text(md_doc(themes, pairs))

    print(f"wrote {len(ids)} svgs to {OUT_DIR.relative_to(ROOT)}")
    print(f"wrote {HTML_PATH.relative_to(ROOT)}")
    print(f"wrote {MD_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

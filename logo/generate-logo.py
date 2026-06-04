#!/usr/bin/env python3
# chromaticli :: generate-logo.py
#
# One-time generator for logo/chromaticli.svg. Implements the design brief in
# logo/logo_prompt_detailed.md without an image-generation model: SVG is just
# structured text, and the brief is all flat-design shapes (rounded window,
# title bar, gradient overlay, `>_` prompt, subtle wave).
#
# Re-run if you want to tweak the design (palette stops, dimensions, font
# fallbacks). Not wired into CI — this is intentionally a manual one-shot;
# the logo is a stable artifact.
#
# Output: logo/chromaticli.svg (overwritten on each run).

from __future__ import annotations

import pathlib
import sys

OUT = pathlib.Path(__file__).resolve().parent / "chromaticli.svg"

# Canvas
W, H = 800, 400
PAD = 20                        # outer margin
RADIUS = 18                     # window corner radius
TITLE_H = 44                    # title bar height

WIN_X = PAD
WIN_Y = PAD
WIN_W = W - 2 * PAD
WIN_H = H - 2 * PAD
TITLE_Y_BOTTOM = WIN_Y + TITLE_H

# Colors
BODY_BG = "#1a1a2e"
TITLE_BG = "#2a2a3e"
TITLE_FG = "#e4e4e7"
PROMPT_FG = "#e4e4e7"
SHADOW = "#000000"

# macOS traffic lights
TL_R, TL_Y, TL_G = "#ff5f57", "#febc2e", "#28c840"
TL_RADIUS = 7
TL_CY = WIN_Y + TITLE_H / 2
TL_X0 = WIN_X + 22

# Pastel rainbow gradient stops (chromatic tint motif)
GRADIENT_STOPS = [
    (0.00, "#ffadad"),   # soft red
    (0.18, "#ffd6a5"),   # soft orange
    (0.36, "#fdffb6"),   # soft yellow
    (0.54, "#caffbf"),   # soft green
    (0.72, "#9bf6ff"),   # soft cyan
    (1.00, "#bdb2ff"),   # soft purple
]

FONT_STACK = (
    'ui-monospace, "SF Mono", "JetBrains Mono", '
    '"Cascadia Code", Menlo, Consolas, monospace'
)

# Per-character title text colors — lolcat-style rainbow. Brighter/more
# saturated than the body gradient stops because they sit on a dark title
# bar and need contrast to read. Distributed across the visible spectrum.
TITLE_RAINBOW = [
    "#ff8a8a",   # c — coral
    "#ffb066",   # h — orange
    "#ffe066",   # r — yellow
    "#a3ff8a",   # o — light green
    "#8affd0",   # m — mint
    "#66d4ff",   # a — sky
    "#8aa3ff",   # t — periwinkle
    "#b08aff",   # i — violet
    "#e08aff",   # c — orchid
    "#ff8ad0",   # l — pink
    "#ff8a9b",   # i — rose
]


def title_bar_path() -> str:
    """Rounded top corners, sharp bottom corners (sits against the body)."""
    x, y, w = WIN_X, WIN_Y, WIN_W
    r = RADIUS
    return (
        f"M {x + r} {y} "
        f"H {x + w - r} "
        f"A {r} {r} 0 0 1 {x + w} {y + r} "
        f"V {y + TITLE_H} "
        f"H {x} "
        f"V {y + r} "
        f"A {r} {r} 0 0 1 {x + r} {y} Z"
    )


def body_path() -> str:
    """Sharp top corners (meets title bar), rounded bottom corners."""
    x, w = WIN_X, WIN_W
    y_top = TITLE_Y_BOTTOM
    y_bot = WIN_Y + WIN_H
    r = RADIUS
    return (
        f"M {x} {y_top} "
        f"H {x + w} "
        f"V {y_bot - r} "
        f"A {r} {r} 0 0 1 {x + w - r} {y_bot} "
        f"H {x + r} "
        f"A {r} {r} 0 0 1 {x} {y_bot - r} "
        f"Z"
    )


def gradient_stops() -> str:
    return "\n      ".join(
        f'<stop offset="{int(o * 100)}%" stop-color="{c}" />'
        for o, c in GRADIENT_STOPS
    )


def title_tspans() -> str:
    """Per-character tspans for the title text, each char gets a rainbow color."""
    title = "chromaticli"
    assert len(title) == len(TITLE_RAINBOW), "TITLE_RAINBOW must match title length"
    return "".join(
        f'<tspan fill="{TITLE_RAINBOW[i]}">{ch}</tspan>'
        for i, ch in enumerate(title)
    )


def main() -> int:
    # Prompt placement: vertically centered in the body, left-aligned with
    # a little inset.
    body_cx_left = WIN_X + 56
    body_cy = TITLE_Y_BOTTOM + (WIN_H - TITLE_H) / 2 + 4
    prompt_font_size = 96

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <defs>
    <linearGradient id="chromatic" x1="0%" y1="0%" x2="100%" y2="100%">
      {gradient_stops()}
    </linearGradient>
    <clipPath id="bodyClip">
      <path d="{body_path()}" />
    </clipPath>
  </defs>

  <!-- subtle drop shadow (visible on light backgrounds; invisible on dark) -->
  <rect x="{WIN_X + 4}" y="{WIN_Y + 6}" width="{WIN_W}" height="{WIN_H}"
        rx="{RADIUS}" fill="{SHADOW}" opacity="0.15" />

  <!-- body fill -->
  <path d="{body_path()}" fill="{BODY_BG}" />

  <!-- chromatic gradient overlay inside the body (the chromatic tint motif) -->
  <rect x="{WIN_X}" y="{TITLE_Y_BOTTOM}" width="{WIN_W}" height="{WIN_H - TITLE_H}"
        fill="url(#chromatic)" opacity="0.55" clip-path="url(#bodyClip)" />

  <!-- title bar -->
  <path d="{title_bar_path()}" fill="{TITLE_BG}" />

  <!-- traffic lights -->
  <circle cx="{TL_X0}" cy="{TL_CY}" r="{TL_RADIUS}" fill="{TL_R}" />
  <circle cx="{TL_X0 + 22}" cy="{TL_CY}" r="{TL_RADIUS}" fill="{TL_Y}" />
  <circle cx="{TL_X0 + 44}" cy="{TL_CY}" r="{TL_RADIUS}" fill="{TL_G}" />

  <!-- title text (per-character rainbow, lolcat-style) -->
  <text x="{W / 2}" y="{TL_CY + 6}" font-size="18"
        font-family='{FONT_STACK}' text-anchor="middle"
        letter-spacing="0.5">{title_tspans()}</text>

  <!-- prompt: >_ -->
  <text x="{body_cx_left}" y="{body_cy}" fill="{PROMPT_FG}"
        font-family='{FONT_STACK}' font-size="{prompt_font_size}"
        font-weight="500">&gt;_</text>
</svg>
"""

    OUT.write_text(svg)
    print(f"wrote {OUT.relative_to(OUT.parent.parent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

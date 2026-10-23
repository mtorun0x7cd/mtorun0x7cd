# SPDX-FileCopyrightText: 2026 Mert Torun
# SPDX-License-Identifier: MIT
"""Write the masters of the README's badges, one SVG per badge.

Usage: badges.py <work-dir>

Each badge is a label and a value on two coloured fields, set in the monospace
font of the banner, whose advance of 0.6 em makes the width of a field a
multiple of the number of its characters, so no text has to be measured here.
docs/render.sh passes each master through docs/outline_text.py, which turns
the text into glyph outlines, and writes the result to docs/badges/<name>.svg.
The badges are files of this repository, so the README loads nothing from a
badge service and nothing counts who reads it.

The values are the identifiers of the profile: the website, which comes first
as the one address that gathers the others, the ORCID iD, the DOI of the
refereed paper and the LinkedIn handle. Each badge links to the page it names;
the link stands in README.md.
"""

import pathlib
import sys
from xml.sax.saxutils import escape

BADGES = {
    "website": ("Website", "mtorun0x7cd.com"),
    "orcid": ("ORCID", "0009-0003-7932-9043"),
    "doi": ("DOI", "10.57684/COS-1494"),
    "linkedin": ("LinkedIn", "mtorun0x7cd"),
}

FONT_SIZE = 11
CELL = 0.6 * FONT_SIZE  # the advance of every glyph of the monospace font
PAD = 7
HEIGHT = 22
LABEL_FILL = "#334155"
VALUE_FILL = "#1D4ED8"
TEXT_FILL = "#FFFFFF"


def badge(label, value):
    label_w = round(2 * PAD + CELL * len(label), 1)
    value_w = round(2 * PAD + CELL * len(value), 1)
    width = round(label_w + value_w, 1)
    text = escape(f"{label}: {value}")
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {HEIGHT}" width="{width}" height="{HEIGHT}">
    <title>{text}</title>
    <style>
        .b-text {{
            font-family: ui-monospace, Menlo, monospace;
            font-size: {FONT_SIZE}px;
            font-weight: 600;
            fill: {TEXT_FILL};
        }}
    </style>
    <clipPath id="round">
        <rect width="{width}" height="{HEIGHT}" rx="4"/>
    </clipPath>
    <g clip-path="url(#round)">
        <rect width="{label_w}" height="{HEIGHT}" fill="{LABEL_FILL}"/>
        <rect x="{label_w}" width="{value_w}" height="{HEIGHT}" fill="{VALUE_FILL}"/>
    </g>
    <text x="{PAD}" y="15" class="b-text">{escape(label)}</text>
    <text x="{round(label_w + PAD, 1)}" y="15" class="b-text">{escape(value)}</text>
</svg>
"""


def main():
    if len(sys.argv) != 2:
        print("usage: badges.py <work-dir>", file=sys.stderr)
        sys.exit(2)
    work = pathlib.Path(sys.argv[1])
    for name, (label, value) in BADGES.items():
        (work / f"badge_{name}.svg").write_text(badge(label, value), encoding="utf-8")
        print(name)


if __name__ == "__main__":
    main()

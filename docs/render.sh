#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mert Torun
# SPDX-License-Identifier: MIT
#
# Reproduce this repository's banner, its PNG fallbacks and the social card from
# docs/social_preview.svg.
#
# The master SVG is theme-adaptive through prefers-color-scheme, but GitHub picks
# a README image by *its* page theme (via <picture>), not by the SVG's internal
# media query, and an <img>-loaded SVG follows the OS scheme, so one file cannot
# serve both themes without the title vanishing on a mismatched canvas. We flatten
# the master into palette-deterministic light/dark variants.
#
# The README shows the banner as SVG, so that its session can be typed once. Each
# flattened variant is written self-contained by docs/outline_text.py: an SVG
# loaded as an image cannot load fonts, so its text becomes glyph outlines, shaped
# with HarfBuzz (hb-shape) and drawn with fontTools, and its CSS custom properties
# are resolved to literal colours. The outlines use JetBrains Mono NL and Fira Sans
# (SIL Open Font License 1.1, which exempts documents made with the fonts) instead
# of the master's SF fonts, whose licence does not allow it. The typing, and its
# absence under prefers-reduced-motion, are CSS in the master and pass through
# unchanged.
#
# The PNGs are rasterised from these self-contained SVGs with librsvg
# (rsvg-convert), so a PNG and the SVG beside it show the same typeface and the
# same geometry. A PNG cannot move, so it shows the final state of the session:
# the copy librsvg reads carries one more rule that switches every animation off,
# and without animation each element of the master is in its final state.
#
# Served files are committed because GitHub serves the raw files with no build step;
# this script is their recorded, reproducible source. Intermediates stay in
# .tmp.nosync/render, or in RENDER_WORK where that is set. Requires: node,
# rsvg-convert, ImageMagick (magick), hb-shape, and a Python with fontTools
# (FONTTOOLS_PYTHON; by default python3 if it imports fontTools, else the one
# Homebrew's ocrmypdf bundles). The fonts are read from MONO_FONT_DIR and
# SANS_FONT_DIR, both ~/Library/Fonts by default.
set -Eeuo pipefail

_on_err() { local ec=$? line=${1:-?} cmd=${2:-?}; echo "render.sh: error on line ${line} (exit ${ec}): ${cmd}" >&2; exit "${ec}"; }
trap '_on_err "${LINENO}" "${BASH_COMMAND}"' ERR

cd "$(dirname "$0")/.."
root=$(pwd)
work=${RENDER_WORK:-"$root/.tmp.nosync/render"}
mono_dir=${MONO_FONT_DIR:-$HOME/Library/Fonts}
sans_dir=${SANS_FONT_DIR:-$HOME/Library/Fonts}
mkdir -p "$work"

for bin in node magick rsvg-convert hb-shape; do
    command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 1; }
done
if [[ -z ${FONTTOOLS_PYTHON:-} ]]; then
    for candidate in python3 "$(brew --prefix ocrmypdf 2>/dev/null || true)/libexec/bin/python"; do
        if "$candidate" -c 'import fontTools' 2>/dev/null; then FONTTOOLS_PYTHON=$candidate; break; fi
    done
fi
[[ -n ${FONTTOOLS_PYTHON:-} ]] || { echo "missing dependency: a Python with fontTools (set FONTTOOLS_PYTHON)" >&2; exit 1; }

# Promote the prefers-color-scheme:dark palette to base for the dark variant and
# drop the media block for the light variant, so each SVG is palette-deterministic
# regardless of the renderer's scheme. Prints the 2x width and height in pixels.
dims=$(MASTER="$root/docs/social_preview.svg" WORK="$work" node <<'NODE'
const { readFileSync, writeFileSync } = require('fs');
const src = readFileSync(process.env.MASTER, 'utf8');
const mediaRe = /\n?\s*@media \(prefers-color-scheme: dark\) \{\s*(:root \{[\s\S]*?\})\s*\}/;
const m = src.match(mediaRe);
if (!m) throw new Error('dark media block not found in master');
const vb = src.match(/<svg\b[^>]*\bviewBox="0 0 (\d+) (\d+)"/);
if (!vb) throw new Error('root viewBox "0 0 W H" not found in master');
const variants = {
    light: src.replace(mediaRe, ''),
    dark: src.replace(/:root \{[\s\S]*?\}/, () => m[1]).replace(mediaRe, ''),
};
for (const [name, svg] of Object.entries(variants)) {
    writeFileSync(`${process.env.WORK}/hero_${name}.svg`, svg);
}
console.log(`${2 * Number(vb[1])} ${2 * Number(vb[2])}`);
NODE
)
read -r width height <<<"$dims"

for variant in light dark; do
    PYTHONDONTWRITEBYTECODE=1 "$FONTTOOLS_PYTHON" "$root/docs/outline_text.py" \
        "$work/hero_$variant.svg" "$root/docs/social_preview_$variant.svg" "$mono_dir" "$sans_dir"
done

render() { # <variant> <out.png>; 2x, transparent, the final state
    local still="$work/still_$1.svg" svg rule='* { animation: none !important; }'
    svg=$(<"$root/docs/social_preview_$1.svg")
    [[ $svg == *"</style>"* ]] || { echo "render.sh: docs/social_preview_$1.svg carries no </style>" >&2; exit 2; }
    printf '%s\n' "${svg/<\/style>/$rule</style>}" >"$still"
    rsvg-convert --width "$width" --height "$height" --output "$2" "$still"
}

render light "$root/docs/social_preview_light.png"
render dark  "$root/docs/social_preview_dark.png"

# OG/social-preview card: the dark variant centred on GitHub's dark canvas at the
# recommended 2:1 (2x of 1280x640) for link-unfurl contexts, which carry no theme.
magick -size 2560x1280 xc:'#0d1117' \
    "$root/docs/social_preview_dark.png" -gravity center -composite \
    "$root/docs/social_card.png"

# Strip metadata, the tIME chunk too (-strip alone keeps it), so that a rerun on
# an unchanged master is byte-identical.
for f in social_preview_light social_preview_dark social_card; do
    magick "$root/docs/$f.png" -strip -define png:exclude-chunks=date,time "$root/docs/$f.png"
done

echo "rendered: docs/social_preview_light.svg docs/social_preview_dark.svg docs/social_preview_light.png docs/social_preview_dark.png docs/social_card.png"

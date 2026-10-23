#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mert Torun
# SPDX-License-Identifier: MIT
#
# Reproduce this repository's social-preview images from docs/social_preview.svg.
#
# The master SVG is theme-adaptive through prefers-color-scheme, but GitHub picks
# a README image by *its* page theme (via <picture>), not by the SVG's internal
# media query, and an <img>-loaded SVG follows the OS scheme, so one file cannot
# serve both themes without the title vanishing on a mismatched canvas. We flatten
# the master into palette-deterministic light/dark variants and rasterise each with
# macOS Quick Look (qlmanage), which renders SVG through WebKit and so resolves CSS
# custom properties and the SF Pro system font faithfully (librsvg drops both),
# without a browser installed.
#
# Quick Look has two limits we work around. Its thumbnails are square, so each
# variant is rendered with a square viewBox centred on the artwork and cropped
# back to the artwork's 2x box. They are also flattened onto opaque white, so each
# variant is rendered twice, on a white and on a black backdrop, and the alpha
# channel is recovered by difference matting: a pixel of colour C and coverage a
# shows as a*C + (1 - a) on white and a*C on black, hence a = 1 - (white - black)
# and C = black / a.
#
# The README shows the banner as SVG, so that its cursor can blink. Each flattened
# variant is also written self-contained by docs/outline_text.py: an SVG loaded as
# an image cannot load fonts, so its text becomes glyph outlines, shaped with
# HarfBuzz (hb-shape) and drawn with fontTools, and its CSS custom properties are
# resolved to literal colours. The outlines use JetBrains Mono NL and Fira Sans
# (SIL Open Font License 1.1, which exempts documents made with the fonts) instead
# of the master's SF fonts, whose licence does not allow it; the banner's typeface
# therefore differs from the PNGs. The cursor's blink, and its stillness under
# prefers-reduced-motion, are CSS in the master and pass through unchanged.
#
# Served files are committed because GitHub serves the raw files with no build step;
# this script is their recorded, reproducible source. Intermediates stay in
# .tmp.nosync/render, or in RENDER_WORK where that is set. Requires: macOS
# (qlmanage), node, ImageMagick (magick), hb-shape, and a Python with fontTools
# (FONTTOOLS_PYTHON; by default python3 if it imports fontTools, else the one
# Homebrew's ocrmypdf bundles). The fonts are read from MONO_FONT_DIR and
# SANS_FONT_DIR, both ~/Library/Fonts by default.
set -Eeuo pipefail

_on_err() { local ec=$? line=${1:-?} cmd=${2:-?}; echo "render.sh: error on line ${line} (exit ${ec}): ${cmd}" >&2; exit "${ec}"; }
trap '_on_err "${LINENO}" "${BASH_COMMAND}"' ERR

cd "$(dirname "$0")/.."
root=$(pwd)
work=${RENDER_WORK:-"$root/.tmp.nosync/render"}
mkdir -p "$work"

for bin in node magick qlmanage hb-shape; do
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
# regardless of the renderer's scheme (Quick Look follows the system appearance).
# Each variant is then written twice more for Quick Look: square viewBox, with a
# white or a black backdrop rect beneath everything. Prints the 2x thumbnail size,
# crop height and crop offset in pixels.
dims=$(MASTER="$root/docs/social_preview.svg" WORK="$work" node <<'NODE'
const { readFileSync, writeFileSync } = require('fs');
const src = readFileSync(process.env.MASTER, 'utf8');
const mediaRe = /\n?\s*@media \(prefers-color-scheme: dark\) \{\s*(:root \{[\s\S]*?\})\s*\}/;
const m = src.match(mediaRe);
if (!m) throw new Error('dark media block not found in master');
const vb = src.match(/<svg\b[^>]*\bviewBox="0 0 (\d+) (\d+)"/);
if (!vb) throw new Error('root viewBox "0 0 W H" not found in master');
const [w, h] = [Number(vb[1]), Number(vb[2])];
if (h >= w) throw new Error('artwork must be wider than tall: the backdrop check reads the padding above and below it');
const pad = (w - h) / 2;
const square = (svg, bg) => svg.replace(/<svg\b[^>]*>/, (tag) =>
    tag.replace(/\bviewBox="[^"]*"/, `viewBox="0 ${-pad} ${w} ${w}"`)
       .replace(/\bheight="[^"]*"/, `height="${w}"`) +
    `\n    <rect x="0" y="${-pad}" width="${w}" height="${w}" fill="${bg}"/>`);
const variants = {
    light: src.replace(mediaRe, ''),
    dark: src.replace(/:root \{[\s\S]*?\}/, () => m[1]).replace(mediaRe, ''),
};
for (const [name, svg] of Object.entries(variants)) {
    writeFileSync(`${process.env.WORK}/hero_${name}.svg`, svg);
    for (const bg of ['white', 'black']) {
        writeFileSync(`${process.env.WORK}/hero_${name}_on_${bg}.svg`, square(svg, bg));
    }
}
console.log(`${2 * w} ${2 * h} ${2 * pad}`);
NODE
)
read -r size height offset <<<"$dims"

for variant in light dark; do
    PYTHONDONTWRITEBYTECODE=1 "$FONTTOOLS_PYTHON" "$root/docs/outline_text.py" \
        "$work/hero_$variant.svg" "$root/docs/social_preview_$variant.svg" \
        "${MONO_FONT_DIR:-$HOME/Library/Fonts}" "${SANS_FONT_DIR:-$HOME/Library/Fonts}"
done

thumb() { # <in.svg> <backdrop level 0|1> <out.png>; 2x, cropped to the artwork, opaque
    local log strip levels lo hi
    log=$(qlmanage -t -s "$size" -o "$work" "$1" </dev/null 2>&1)
    [[ $log == *"produced one thumbnail"* ]] || { echo "qlmanage produced no thumbnail for $1: $log" >&2; exit 2; }
    # qlmanage also exits 0 and reports a thumbnail when WebKit cannot parse the
    # SVG; it then draws an error page instead. The padding above and below the
    # artwork must be the backdrop and nothing else, which no error page is.
    for strip in "${size}x${offset}+0+0" "${size}x${offset}+0+$((offset + height))"; do
        levels=$(magick "$1.png" -crop "$strip" +repage -alpha off -format '%[fx:minima] %[fx:maxima]' info:)
        read -r lo hi <<<"$levels"
        [[ $lo == "$2" && $hi == "$2" ]] || { echo "unexpected thumbnail for $1: padding $strip spans $lo..$hi, backdrop is $2" >&2; exit 2; }
    done
    # Its PNG carries an all-opaque alpha channel; drop it so that the matting
    # below sees R, G and B only.
    magick "$1.png" -crop "${size}x${height}+0+${offset}" +repage -alpha off "$3"
}

render() { # <variant> <out.png>; 2x, transparent
    local on_white="$work/$1_on_white.png" on_black="$work/$1_on_black.png"
    thumb "$work/hero_$1_on_white.svg" 1 "$on_white"
    thumb "$work/hero_$1_on_black.svg" 0 "$on_black"
    # a = 1 - (white - black), averaged over R, G and B to damp rounding noise.
    magick "$on_white" "$on_black" -compose difference -composite \
        -separate -evaluate-sequence mean -negate "$work/$1_alpha.png"
    # C = black / a (divide_src divides the destination by the source), then
    # attach a as the alpha channel.
    magick "$on_black" "$work/$1_alpha.png" -compose divide_src -composite \
        "$work/$1_alpha.png" -alpha off -compose copy_opacity -composite "$2"
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

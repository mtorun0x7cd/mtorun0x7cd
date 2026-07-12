#!/usr/bin/env bash
# Reproduce this repository's social-preview images from docs/social_preview.svg.
#
# The master SVG is theme-adaptive through prefers-color-scheme, but GitHub picks
# a README image by *its* page theme (via <picture>), not by the SVG's internal
# media query — and an <img>-loaded SVG follows the OS scheme, so one file cannot
# serve both themes without the title vanishing on a mismatched canvas. We flatten
# the master into palette-deterministic light/dark variants and rasterise each with
# headless Chrome, the only local engine that resolves CSS custom properties and
# the SF Pro system font faithfully (librsvg drops both).
#
# Served PNGs are committed because GitHub serves the raw files with no build step;
# this script is their recorded, reproducible source. Intermediates stay in
# .tmp.nosync/. Requires: node, ImageMagick (magick), Google Chrome.
set -euo pipefail

_on_err() { local ec=$? line=${1:-?} cmd=${2:-?}; echo "render.sh: error on line ${line} (exit ${ec}): ${cmd}" >&2; exit "${ec}"; }
trap '_on_err "${LINENO}" "${BASH_COMMAND}"' ERR

cd "$(dirname "$0")/.."
root=$(pwd)
work="$root/.tmp.nosync/render"
mkdir -p "$work"

chrome=${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}
for bin in node magick; do
    command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 1; }
done
[ -x "$chrome" ] || { echo "Chrome not found; set CHROME=/path/to/chrome" >&2; exit 1; }

# Promote the prefers-color-scheme:dark palette to base for the dark variant and
# drop the media block for the light variant, so each SVG is palette-deterministic
# regardless of the renderer's default scheme (headless Chrome defaults to dark).
MASTER="$root/docs/social_preview.svg" LIGHT="$work/hero_light.svg" DARK="$work/hero_dark.svg" \
node <<'NODE'
const { readFileSync, writeFileSync } = require('fs');
const src = readFileSync(process.env.MASTER, 'utf8');
const mediaRe = /\n?\s*@media \(prefers-color-scheme: dark\) \{\s*(:root \{[\s\S]*?\})\s*\}/;
const m = src.match(mediaRe);
if (!m) throw new Error('dark media block not found in master');
writeFileSync(process.env.LIGHT, src.replace(mediaRe, ''));
writeFileSync(process.env.DARK, src.replace(/:root \{[\s\S]*?\}/, () => m[1]).replace(mediaRe, ''));
NODE

render() { # <in.svg> <out.png>  — 2x, transparent
    "$chrome" --headless=new --disable-gpu --hide-scrollbars \
        --force-device-scale-factor=2 --window-size=1200,630 \
        --default-background-color=00000000 \
        --screenshot="$2" "file://$1" >/dev/null 2>&1
}

render "$work/hero_light.svg" "$root/docs/social_preview_light.png"
render "$work/hero_dark.svg"  "$root/docs/social_preview_dark.png"

# OG/social-preview card: the dark variant centred on GitHub's dark canvas at the
# recommended 2:1 (2x of 1280x640) for link-unfurl contexts, which carry no theme.
magick -size 2560x1280 xc:'#0d1117' \
    "$root/docs/social_preview_dark.png" -gravity center -composite \
    "$root/docs/social_card.png"

for f in social_preview_light social_preview_dark social_card; do
    magick "$root/docs/$f.png" -strip "$root/docs/$f.png"
done

echo "rendered: docs/social_preview_light.png docs/social_preview_dark.png docs/social_card.png"

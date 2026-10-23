#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mert Torun
# SPDX-License-Identifier: MIT
#
# Regression cases of `tools/check.sh banner`: each case copies the tracked
# files of the working tree, breaks one thing in the copy and expects the exit
# code given below, so that a gap in the check shows as a case that passes when
# it should not. The unchanged copy must give 0.
#
#   tools/test-check.sh
#
# The copies are written under .tmp.nosync/test-check/, or under
# TEST_CHECK_WORK where that is set, one new directory per run, and kept there.
# Needs git, tar and python3 (or $PYTHON).
#
# Exit status: 0 every case gave its expected exit code; 1 at least one did
# not; 2 a tool error, so that nothing was tested.

set -uo pipefail

PYTHON=${PYTHON:-python3}

cd "$(dirname "$0")/.." || exit 2
root=$(pwd)

for bin in git tar "$PYTHON"; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "test-check: $bin is not installed; nothing was tested" >&2
        exit 2
    fi
done

base=${TEST_CHECK_WORK:-"$root/.tmp.nosync/test-check"}
mkdir -p "$base" || exit 2
run=$(mktemp -d "$base/run.XXXXXX") || exit 2

# Each case: its name, the exit code expected, and a Python statement that
# changes the copy in the current directory. edit(path, old, new) replaces one
# occurrence and fails when the text is not found, so a case cannot pass by
# changing nothing.
cases=(
    "unchanged|0|pass"
    "served dark: no reduced-motion rule|1|edit('docs/social_preview_dark.svg', '@media (prefers-reduced-motion: reduce){.h1, .h2, .h3, .h4, .h5, .k1, .k2, .k3, .k4{animation:none}}', '')"
    "served dark: h5 repeats without end|1|edit('docs/social_preview_dark.svg', '.h5{animation-name:hold;animation-timing-function:steps(1, end);animation-iteration-count:1', '.h5{animation-name:hold;animation-timing-function:steps(1, end);animation-iteration-count:infinite')"
    "served light: h5 lasts 30 s|1|edit('docs/social_preview_light.svg', 'animation-duration:4.3s}', 'animation-duration:30s}')"
    "served light: k1 left out of the reduced-motion rule|1|edit('docs/social_preview_light.svg', '{.h1, .h2, .h3, .h4, .h5, .k1, .k2', '{.h1, .h2, .h3, .h4, .h5, .k2')"
    "served dark: animation inside a media rule|1|edit('docs/social_preview_dark.svg', '@keyframes hold', '@media (min-width: 1px){.h5{animation-duration:30s}}@keyframes hold')"
    "served dark: important declaration|1|edit('docs/social_preview_dark.svg', 'animation-duration:4.3s}', 'animation-duration:4.3s !important}')"
    "served light: animation shorthand|1|edit('docs/social_preview_light.svg', '@keyframes hold', '.h5{animation:hold 30s infinite}@keyframes hold')"
    "served light: stale keyframes|1|edit('docs/social_preview_light.svg', 'translateX(86.4px)}100%', 'translateX(90px)}100%')"
    "served dark: delay differs from the master|1|edit('docs/social_preview_dark.svg', 'animation-delay:3.7s', 'animation-delay:3.6s')"
    "served dark: SMIL animation|1|edit('docs/social_preview_dark.svg', '</svg>', '<animate attributeName=\"opacity\" values=\"0;1\" dur=\"1s\" repeatCount=\"indefinite\"/></svg>')"
    "served light: animation in a style attribute|1|edit('docs/social_preview_light.svg', '<g ', '<g style=\"animation-name:hold;animation-duration:30s\" ', count=1)"
    "served light: a text element|1|edit('docs/social_preview_light.svg', '</svg>', '<text>x</text></svg>')"
    "served dark: an external href|1|edit('docs/social_preview_dark.svg', '</svg>', '<use href=\"https://example.org/a.svg#b\"/></svg>')"
    "master: h5 lasts 5.7 s|1|edit('docs/social_preview.svg', '.h5 { animation-duration: 4.3s; }', '.h5 { animation-duration: 5.7s; }')"
    "README: alternative text drifts|1|edit('README.md', 'A cursor rests at the next prompt.', 'A cursor blinks at the next prompt.')"
    "served light: broken XML|2|edit('docs/social_preview_light.svg', '</svg>', '')"
)

status=0
n=0
for entry in "${cases[@]}"; do
    name=${entry%%|*}
    rest=${entry#*|}
    want=${rest%%|*}
    change=${rest#*|}
    n=$((n + 1))
    copy="$run/case$n"
    mkdir -p "$copy" || exit 2
    if ! git ls-files -z | tar --null -T - -cf - | tar -xf - -C "$copy"; then
        echo "test-check: the tracked files could not be copied; nothing was tested" >&2
        exit 2
    fi
    if ! (cd "$copy" && "$PYTHON" -B -c "
import sys
def edit(path, old, new, count=-1):
    text = open(path, encoding='utf-8').read()
    if old not in text:
        sys.exit(f'{path}: text to replace not found: {old!r}')
    open(path, 'w', encoding='utf-8').write(text.replace(old, new, count))
$change
"); then
        echo "test-check: case '$name' could not be set up; nothing was tested" >&2
        exit 2
    fi
    rc=0
    bash "$copy/tools/check.sh" banner </dev/null >"$copy.out" 2>&1 || rc=$?
    if [ "$rc" -eq "$want" ]; then
        echo "ok    $name: exit $rc"
    else
        echo "FAIL  $name: exit $rc, expected $want (output in $copy.out)"
        status=1
    fi
done
echo "test-check: $n cases in $run"
exit "$status"

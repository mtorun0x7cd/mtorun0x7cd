#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mert Torun
# SPDX-License-Identifier: MIT
#
# The checks of this repository, one per argument, run the same way on a
# workstation and in the workflows under .github/workflows/, which call this
# script, so that each check is written once.
#
#   tools/check.sh markdown   lint the Markdown files with markdownlint-cli2 and
#                             the rules of .markdownlint.jsonc (needs npx)
#   tools/check.sh readme     README.md carries no {{TOKEN}} placeholder
#   tools/check.sh setup      no file keeps a placeholder, a TEMPLATE: comment
#                             or a setup file of the project template, and no
#                             file but README.md, which lists the template
#                             among the repositories, names it
#   tools/check.sh banner     the served banner and badges are self-contained,
#                             every animation of the banner ends within five
#                             seconds and rests under prefers-reduced-motion,
#                             and the README describes the banner in the words
#                             of its master (needs python3)
#   tools/check.sh reuse      every file carries its licence and copyright, as
#                             REUSE 3.3 defines it (needs reuse, or $REUSE)
#   tools/check.sh secrets    gitleaks finds no secret in the history, with the
#                             rules of .gitleaks.toml (needs gitleaks, or
#                             $GITLEAKS)
#   tools/check.sh all        each check above in turn (the default)
#
# This repository backs a profile page and is not a citable artifact, so it
# carries no CITATION.cff and no citation check.
#
# Exit status: 0 the check holds; 1 a finding; 2 a tool error: an argument that
# is not understood, a tool that is missing or fails, or a file that cannot be
# read, so that nothing was checked; 3 skipped. A tool error is never reported
# as a finding or as a pass. For "all", 2 beats 1, 1 beats 0, and 3 is
# returned only when every check was skipped. This script writes nothing.

set -uo pipefail

MARKDOWNLINT_VERSION=0.23.3
PYTHON=${PYTHON:-python3}
REUSE=${REUSE:-reuse}
GITLEAKS=${GITLEAKS:-gitleaks}

cd "$(dirname "$0")/.." || exit 2

# npx also exits 1 when it cannot fetch or start the tool, so an exit code
# counts only once the pinned markdownlint-cli2 has printed its banner, which
# opens its standard output.
check_markdown() {
    if ! command -v npx >/dev/null 2>&1; then
        echo "markdown: npx is not installed; nothing was linted" >&2
        return 2
    fi
    local rc=0 report
    report=$(npx --yes "markdownlint-cli2@${MARKDOWNLINT_VERSION}" "**/*.md") || rc=$?
    if [ -n "$report" ]; then
        printf '%s\n' "$report"
    fi
    case $report in
        "markdownlint-cli2 v${MARKDOWNLINT_VERSION} "*) ;;
        *) echo "markdown: markdownlint-cli2 ${MARKDOWNLINT_VERSION} did not start (exit code $rc); nothing was linted" >&2
           return 2 ;;
    esac
    case $rc in
        0) return 0 ;;
        1) echo "markdown: the files above break a rule of .markdownlint.jsonc" >&2; return 1 ;;
        *) echo "markdown: markdownlint-cli2 failed with exit code $rc" >&2; return 2 ;;
    esac
}

# grep exits 0 on a match, 1 on none and 2 on an error.
check_readme() {
    local rc=0
    grep -nE '\{\{[A-Z0-9_]+\}\}' README.md || rc=$?
    case $rc in
        0) echo "readme: README.md carries the placeholders above" >&2; return 1 ;;
        1) echo "readme: README.md carries no placeholder"; return 0 ;;
        *) echo "readme: grep failed with exit code $rc" >&2; return 2 ;;
    esac
}

# This file names the patterns it searches for, so it is left out of the
# search. README.md links the template as one of the repositories of the
# account, so only the template's name is allowed there.
check_setup() {
    local status=0 path rc=0
    for path in docs/TEMPLATE.md docs/README.template.md docs/CITATION.template.cff; do
        if [ -e "$path" ]; then
            echo "setup: $path is still present" >&2
            status=1
        fi
    done
    git grep -nIE '\{\{[A-Z0-9_]+\}\}|TEMPLATE:' -- ':(exclude)tools/check.sh' || rc=$?
    case $rc in
        0) echo "setup: the lines above still carry template text" >&2; status=1 ;;
        1) ;;
        *) echo "setup: git grep failed with exit code $rc" >&2; return 2 ;;
    esac
    rc=0
    git grep -nI 'mtorun0x7cd/template' -- ':(exclude)tools/check.sh' ':(exclude)README.md' || rc=$?
    case $rc in
        0) echo "setup: the lines above name the template" >&2; status=1 ;;
        1) ;;
        *) echo "setup: git grep failed with exit code $rc" >&2; return 2 ;;
    esac
    if [ "$status" -eq 0 ]; then
        echo "setup: no placeholder and no template text is left"
    fi
    return "$status"
}

# An SVG that GitHub shows through <img> or <picture> loads nothing: no font,
# no external file, no script. The served files must therefore carry their text
# as outlines and every colour as a literal. Their animation must end within
# five seconds, the bound of WCAG 2.2 success criterion 2.2.2 for moving
# content without a pause control, and stop under prefers-reduced-motion, where
# each element shows its final state. The README's alternative text of the
# banner is the <title> of its master, word for word.
check_banner() {
    if ! command -v "$PYTHON" >/dev/null 2>&1; then
        echo "banner: $PYTHON is not installed; nothing was checked" >&2
        return 2
    fi
    "$PYTHON" -B - <<'PYEOF'
import glob
import html
import re
import sys
import xml.etree.ElementTree as ET

SVG = "{http://www.w3.org/2000/svg}"
MASTER = "docs/social_preview.svg"
SERVED = ["docs/social_preview_light.svg", "docs/social_preview_dark.svg"]
BADGES = sorted(glob.glob("docs/badges/*.svg"))
FORBIDDEN_TAGS = {"text", "image", "foreignObject", "script", "style-sheet", "iframe"}
LIMIT = 5.0
findings = []


def seconds(value):
    value = value.strip()
    if value.endswith("ms"):
        return float(value[:-2]) / 1000
    if value.endswith("s"):
        return float(value[:-1])
    raise ValueError(f"not a time: {value!r}")


def blocks(css):
    """Top-level (prelude, body) pairs, nested braces kept in the body."""
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    out, i = [], 0
    while True:
        j = css.find("{", i)
        if j < 0:
            return out
        depth, k = 1, j + 1
        while depth:
            if k >= len(css):
                raise ValueError("unbalanced braces in <style>")
            depth += {"{": 1, "}": -1}.get(css[k], 0)
            k += 1
        out.append((css[i:j].strip(), css[j + 1:k - 1].strip()))
        i = k


def declarations(body):
    out = {}
    for part in body.split(";"):
        if ":" in part:
            name, _, value = part.partition(":")
            out[name.strip()] = value.strip()
    return out


try:
    if not BADGES:
        raise OSError("no badge under docs/badges/")
    trees = {path: ET.parse(path) for path in [MASTER, *SERVED, *BADGES]}
    readme = open("README.md", encoding="utf-8").read()
except (OSError, ET.ParseError) as error:
    print(f"banner: {error}; nothing was checked", file=sys.stderr)
    sys.exit(2)

for path in [*SERVED, *BADGES]:
    root = trees[path].getroot()
    if root.find(f"{SVG}title") is None or not (root.find(f"{SVG}title").text or "").strip():
        findings.append(f"{path}: no <title>")
    for el in root.iter():
        tag = el.tag.replace(SVG, "")
        if tag in FORBIDDEN_TAGS:
            findings.append(f"{path}: a <{tag}> element, which an image cannot render as drawn")
        for name, value in el.attrib.items():
            if name.endswith("href") and not value.startswith("#"):
                findings.append(f"{path}: <{tag} {name}={value!r}> loads a file")
            if "var(" in value:
                findings.append(f"{path}: <{tag} {name}> keeps a CSS custom property")
    css = "".join(el.text or "" for el in root.iter(f"{SVG}style"))
    for needle in ("var(", "@import", "@font-face", "url(http", "url(//"):
        if needle in css:
            findings.append(f"{path}: the style sheet keeps {needle!r}")

# Timing and reduced motion, read from the master: the served banners carry
# its rules, which tools/check.sh compares below.
try:
    master_css = "".join(el.text or "" for el in trees[MASTER].getroot().iter(f"{SVG}style"))
    rules = blocks(master_css)
except ValueError as error:
    print(f"banner: {MASTER}: {error}; nothing was checked", file=sys.stderr)
    sys.exit(2)
classes, resting = {}, set()
for prelude, body in rules:
    if prelude.startswith("@media") and "prefers-reduced-motion: reduce" in prelude:
        for inner, inner_body in blocks(body):
            if declarations(inner_body).get("animation", "").split()[:1] == ["none"]:
                resting.update(s.strip() for s in inner.split(","))
    elif not prelude.startswith("@"):
        decl = declarations(body)
        if "animation" in decl:
            findings.append(f"{MASTER}: {prelude} uses the animation shorthand; write the longhands, which this check reads")
        # A list of selectors styles each of them; a later rule wins, as in CSS.
        for selector in prelude.split(","):
            classes.setdefault(selector.strip(), {}).update(decl)
animated = {s: d for s, d in classes.items() if d.get("animation-name", "none") != "none"}
if not animated:
    findings.append(f"{MASTER}: no animated rule found; the check would hold over nothing")
for selector, decl in animated.items():
    if selector not in resting:
        findings.append(f"{MASTER}: {selector} keeps moving under prefers-reduced-motion")
    count = decl.get("animation-iteration-count", "1")
    if count == "infinite":
        findings.append(f"{MASTER}: {selector} repeats without end")
        continue
    try:
        end = (seconds(decl.get("animation-delay", "0s")) + seconds(decl.get("animation-duration", "0s"))) * float(count)
    except ValueError as error:
        findings.append(f"{MASTER}: {selector}: {error}")
        continue
    if end > LIMIT:
        findings.append(f"{MASTER}: {selector} ends after {end:.2f} s, beyond {LIMIT:.0f} s")
for path in SERVED:
    served_css = "".join(el.text or "" for el in trees[path].getroot().iter(f"{SVG}style"))
    for selector in animated:
        if selector + "{" not in served_css.replace(" {", "{"):
            findings.append(f"{path}: the animated rule {selector} of the master is missing; render again")

title = (trees[MASTER].getroot().find(f"{SVG}title").text or "").strip()
alts = [html.unescape(m) for m in re.findall(r'<img src="docs/social_preview_light\.png" alt="([^"]*)"', readme)]
if len(alts) != 1:
    findings.append(f"README.md: {len(alts)} banner images with an alternative text, one expected")
elif alts[0] != title:
    findings.append("README.md: the banner's alternative text differs from the <title> of docs/social_preview.svg")

for finding in findings:
    print(finding, file=sys.stderr)
if findings:
    print(f"banner: {len(findings)} finding(s)", file=sys.stderr)
    sys.exit(1)
print(f"banner: {len(SERVED)} banners and {len(BADGES)} badges are self-contained, {len(animated)} animated rules end within {LIMIT:.0f} s and rest under reduced motion")
PYEOF
    local rc=$?
    case $rc in
        0|1) return "$rc" ;;
        *) return 2 ;;
    esac
}

# Python also exits 1 when reuse crashes, for example on a missing library,
# so an exit code counts only once reuse has printed its whole report: the
# JSON report carries the key "non_compliant" and is printed only at the end.
check_reuse() {
    if ! command -v "$REUSE" >/dev/null 2>&1; then
        echo "reuse: $REUSE is not installed; nothing was checked" >&2
        return 2
    fi
    local rc=0 report
    report=$("$REUSE" lint --json) || rc=$?
    case $report in
        *'"non_compliant":'*) ;;
        *) echo "reuse: reuse lint gave no report (exit code $rc); nothing was checked" >&2
           return 2 ;;
    esac
    case $rc in
        0) echo "reuse: every file carries its licence and copyright information"; return 0 ;;
        1) "$REUSE" lint --lines || true
           echo "reuse: the files above lack licence or copyright information" >&2; return 1 ;;
        *) echo "reuse: reuse failed with exit code $rc" >&2; return 2 ;;
    esac
}

# gitleaks reports a find with the exit code given here, 9, so that any other
# failure is told apart as a tool error.
check_secrets() {
    if ! command -v "$GITLEAKS" >/dev/null 2>&1; then
        echo "secrets: $GITLEAKS is not installed; nothing was scanned" >&2
        return 2
    fi
    local rc=0
    "$GITLEAKS" git --no-banner --redact --exit-code 9 --config .gitleaks.toml . || rc=$?
    case $rc in
        0) return 0 ;;
        9) echo "secrets: gitleaks found a potential secret in the history" >&2; return 1 ;;
        *) echo "secrets: gitleaks failed with exit code $rc" >&2; return 2 ;;
    esac
}

run_all() {
    local worst=0 ran=0 name rc
    for name in markdown readme setup banner reuse secrets; do
        rc=0
        "check_$name" || rc=$?
        echo "== $name: exit $rc"
        if [ "$rc" -ne 3 ]; then
            ran=1
        fi
        if [ "$rc" -eq 2 ]; then
            worst=2
        elif [ "$rc" -eq 1 ] && [ "$worst" -ne 2 ]; then
            worst=1
        fi
    done
    if [ "$ran" -eq 0 ]; then
        return 3
    fi
    return "$worst"
}

if [ "$#" -gt 1 ]; then
    echo "usage: tools/check.sh [markdown|readme|setup|banner|reuse|secrets|all]" >&2
    exit 2
fi
case "${1:-all}" in
    markdown|readme|setup|banner|reuse|secrets) "check_$1" ;;
    all) run_all ;;
    *) echo "usage: tools/check.sh [markdown|readme|setup|banner|reuse|secrets|all]" >&2
       exit 2 ;;
esac

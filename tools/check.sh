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
    for name in markdown readme setup reuse secrets; do
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
    echo "usage: tools/check.sh [markdown|readme|setup|reuse|secrets|all]" >&2
    exit 2
fi
case "${1:-all}" in
    markdown|readme|setup|reuse|secrets) "check_$1" ;;
    all) run_all ;;
    *) echo "usage: tools/check.sh [markdown|readme|setup|reuse|secrets|all]" >&2
       exit 2 ;;
esac

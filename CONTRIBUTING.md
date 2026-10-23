# Contributing

This repository backs my GitHub profile page. It is not a software project, is not a citable artifact, and does not accept feature contributions; the citable work lives in the repositories the profile indexes.

## Reporting

- **Security or integrity issues:** follow [`SECURITY.md`](SECURITY.md).
- **Factual corrections** (a broken link, an out-of-date detail): write to <info@mtorun0x7cd.com>, naming the place, the correction and its source. Issues are disabled on this repository, and issue and pull request templates are absent by design.

## Commits

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/), in English and ASCII, with the subject in the imperative. Commits on the default branch are signed.

## Checks

The workflows run their checks through `tools/check.sh`, which runs them locally the same way, one per argument or all of them without one. It ends with 0 when every check holds, 1 on a finding, 2 when a tool is missing or fails, so that nothing was checked, and 3 when a check is skipped:

```bash
tools/check.sh
```

The banner and the badges under `docs/` are rendered from their sources by `docs/render.sh`, on macOS; the served SVGs and PNGs are committed with the source they were rendered from.

The pre-commit hook scans the staged changes for secrets with the rules of `.gitleaks.toml`. Enable it once per clone; it requires the `gitleaks` command line tool:

```bash
git config core.hooksPath .githooks
```

## Contact

Mert Torun, M.Sc.: <info@mtorun0x7cd.com>

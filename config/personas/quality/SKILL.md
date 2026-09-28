---
name: quality
description: Sets up deterministic quality gates in a project - complexity, function and file length, argument count, duplication (jscpd), layer rules (import-linter, dependency-cruiser, depguard) and strict type checks for Python, TypeScript, Dart/Flutter and Go - wired into the agent hooks and CI with fix-instruction failure messages. Use when adding or tightening lint limits, layer contracts, duplication checks or strict typing, or when asked to "add quality gates".
tier: standard
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
---

# Quality Gates

Turn structure rules (DRY, small functions, clean layering, strict types) into
checks that fail, instead of review comments. The agent hooks installed by
macols-ai-coding-setup already run these tools on every edit and at turn end,
using the project's own config. This skill writes that config and the matching
CI job, so local and CI results agree.

## What Runs Where

| Check | Per edit | Turn end (changed files) | CI (whole repo) |
|---|---|---|---|
| ruff (incl. C901, PLR09xx, S) / eslint / dart analyze / shellcheck | yes | yes | yes |
| gofmt | yes | - | via golangci-lint |
| golangci-lint (dupl, gocyclo, funlen, depguard) | - | changed packages | yes |
| pyright or mypy strict / tsc --noEmit | pyright/mypy | yes | yes |
| import-linter / dependency-cruiser | - | when configured | yes |
| jscpd duplication | - | clones touching changed files | threshold |
| file length (500 lines, grown files only) | yes | yes | eslint max-lines |
| tests | - | related tests (pytest-testmon when installed; Go: changed modules, test cache skips the rest) | full suite |
| semgrep, pip-audit, npm audit, govulncheck | - | - | yes |

## Apply to a Project

1. Detect the languages from `pyproject.toml`, `package.json`/`tsconfig.json`,
   `pubspec.yaml` and `go.mod`.
2. Merge the matching starter config from `references/` into the project's
   existing files. Never overwrite: keep existing rules, add or tighten limits.
   - Python: `references/python-pyproject.toml` into `pyproject.toml`
   - TypeScript: `references/eslint.config.mjs` (spread into the flat config),
     `references/tsconfig.strict.json` into `compilerOptions`,
     `references/dependency-cruiser.cjs` as `.dependency-cruiser.cjs`
   - Dart/Flutter: `references/analysis_options.yaml`
   - Go: `references/golangci.yml` as `.golangci.yml`
   - All: `references/jscpd.json` as `.jscpd.json`
3. Rewrite the layer rules for the real module names. The starter contracts
   assume feature folders (`app/<feature>`, `src/features/<feature>`,
   `internal/<feature>`) with a public interface per feature. The default rule
   is "no importing another feature's internals"; add a layer chain
   (routers -> services -> repositories -> models) only where the code already
   has those layers.
4. Write every contract name, rule comment and depguard `desc` as the fix
   ("Fix: move shared code into core/…; see docs/architecture.md#layers"),
   because that text is what the agent sees when the rule breaks. Point at a
   real doc section; create the section if it doesn't exist.
5. Add the dev dependencies the project lacks (ruff, pyright, import-linter,
   pytest-testmon; eslint, typescript, dependency-cruiser, jscpd;
   golangci-lint in CI) using the project's package manager. With testmon in
   the venv the turn-end hook picks tests by coverage instead of by file name;
   add `.testmondata*` to `.gitignore`.
6. Add `references/quality-ci.yml` as `.github/workflows/quality.yml`, trimming
   the jobs for languages the repo doesn't use.
7. Put the project's own per-loop commands in `.macols/checks.conf` from
   `references/checks.conf`: `IMMEDIATE` (every turn, fast: schema validation),
   `CHECKPOINT` (before each commit: integration tests, an eval smoke set) and
   `NIGHTLY` (the scheduled CI job: E2E, full evals). Keep each loop's budget:
   seconds, then a minute or two, then as long as it takes.
8. Run every gate once over the whole repo and report the baseline.

## Adopting in an Existing Codebase

The hooks only look at changed files, so existing violations surface as files
get touched. Don't bulk-suppress them. If CI can't go green on day one, set
the limits at the current worst offender and ratchet them down in follow-up
changes; list the offenders so they can be scheduled.

Start with the three layer rules that matter most, not a full graph. Existing
breaks of those rules become approved exceptions, recorded where a reviewer
sees them change:

- dependency-cruiser: `npx depcruise --config .dependency-cruiser.cjs --output-type baseline src > .dependency-cruiser-known-violations.json`.
  The hook and the CI template pass `--ignore-known` when the file exists, so
  only new violations fail. Regenerate it only to remove entries.
- import-linter: list each exception in the contract's `ignore_imports`, with
  a comment saying why and when it goes.
- golangci-lint: for a legacy module, set `issues.new-from-merge-base: main`
  in CI so only new findings fail; the turn-end hook already looks at changed
  packages only.

## Is It Worth the Time?

The hooks log every check they run to `.git/macols-checks.jsonl`. After a week
of agent work, `macols-check-stats` shows total and p95 time per check, the
failure rate, repeated failures and escapes (tests that failed at the commit
checkpoint but weren't selected at turn end). A slow check that never fails
belongs in CI; a high escape count means the project should add
pytest-testmon or better test names.

## Thresholds

Python and TypeScript use complexity 10, 5 (Python) or 4 (TypeScript)
parameters, about 50 statements or 60 lines per function and 500 lines per
file. Go uses complexity 15 because explicit error checks inflate the count.
Change a threshold only with a reason written next to it in the config.

## Rules for the Agent

- Fix the code, not the gate: no `noqa`, `eslint-disable`, `//nolint`, `# type:
  ignore` or raised limits to get green, unless the user agrees and the reason
  is written beside the suppression.
- Duplication: extract shared logic into the owning feature, or into a shared
  core module when two features need it.
- Layer breaks: depend on the other feature's public interface, or move the
  code down a layer.

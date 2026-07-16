# Spec Anchoring

## Purpose

This repo pins its living spec sections to the code that implements them
with ast-grep anchor rules (the convention from
[coles.codes/posts/anchoring-specs-to-code-with-ast-grep](https://coles.codes/posts/anchoring-specs-to-code-with-ast-grep/)):
rules match the code's shape, not its address, so anchors survive moves and
refactors and break — by design — on renames. `scripts/spec_drift_gate.sh`
checks them locally and in CI.

## Requirements

### Requirement: Anchors are sidecar YAML keyed by spec-section id

Anchor rules SHALL live in `specs/anchors/<domain>.yml` as a map keyed by
dotted id, each entry carrying `language`, `rule` and `files`. Rules SHALL
match by node kind + name-field regex (never `pattern:` strings, which
silently miss some constructs) and SHALL resolve to exactly one code site.
The anchored spec section carries `<!-- anchor: <id> -->` on the line after
its requirement text (OpenSpec's parser reads the first block after the
heading as the requirement, so the comment must not sit there). Rules for languages the installed ast-grep cannot parse SHALL be
quarantined under `specs/anchors/quarantine/` — one unloadable rule aborts a
whole scan.

#### Scenario: Code moves without renaming

- **WHEN** an anchored function moves to another matched file with its name intact
- **THEN** the rule still resolves and the anchor survives

### Requirement: Hygiene — every rule resolves exactly once
`scripts/spec_drift_gate.sh --check` SHALL scan every anchor rule against
the working tree and exit non-zero when any rule matches zero sites
(dangling) or more than one (too loose), naming the offending ids.
<!-- anchor: spec-anchoring.hygiene -->

#### Scenario: Renamed function

- **WHEN** an anchored function is renamed without re-pointing its rule
- **THEN** `--check` fails naming the dangling id

### Requirement: The drift gate warns and never blocks
In PR mode the gate SHALL classify each rule against the merge base:
DANGLING when it matched at the base but matches nothing now; DRIFT when its
match intersects the PR's changed lines while neither the section's prose nor
its rule was touched; quiet otherwise. PR mode SHALL always exit zero —
non-blocking is load-bearing — and `--github` SHALL emit `::warning::`
annotations plus a step-summary table.
<!-- anchor: spec-anchoring.drift -->

#### Scenario: Hotfix lands without the spec

- **WHEN** a PR edits anchored code and touches neither the spec section nor the rule
- **THEN** the gate warns DRIFT with the anchor id, and the PR still passes

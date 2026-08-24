---
name: anchors
description: Work with ast-grep spec anchors — resolve anchors before a change, re-run them after, propose spec diffs, keep the rules healthy. Use in repos with specs/anchors/*.yml.
allowed-tools:
  - Read
  - Edit
  - Bash
  - Grep
  - Glob
user-invocable: true
---

# Spec Anchors Skill

Anchors bind living-spec sections to the code that implements them with
ast-grep rules, so the spec that matters can be found before a change and
patched after it. The convention:
[coles.codes/posts/anchoring-specs-to-code-with-ast-grep](https://coles.codes/posts/anchoring-specs-to-code-with-ast-grep/).

**Gate**: if the repo has no `specs/anchors/*.yml`, it is not using spec
anchors — say so and stop.

## Before a change (context, not ceremony)

1. Resolve the anchors against the files you expect to touch: run the repo's
   gate script if it has one (`scripts/spec_drift_gate.sh --check`), otherwise
   run each rule with `ast-grep scan`.
2. Read **only** the spec sections whose anchors matched — find them by their
   `<!-- anchor: <id> -->` comment — not the whole spec. This pass is
   best-effort; the end-of-task re-run closes the gap.

## After the change

3. Re-run the anchors over the files you actually changed.
4. If the behaviour a matched section describes has changed, propose the spec
   update **as a diff for the human to apply** — never edit main spec prose
   directly. Most tasks correctly produce no spec change; do not invent one.
5. Keep sections under the ~40-line soft cap. If an update would blow it,
   propose a split instead of appending — without the cap every section slowly
   becomes a changelog.

## The rules are yours to maintain

- A rule must resolve to **exactly one** site. Zero matches is a dangling
  anchor; more than one means it is too loose — tighten with `inside`
  (+ `stopBy: end`) or a narrower `files:` glob. Both are drift.
- If your change renames or moves matched code and breaks a rule, re-point the
  rule **in the same change** — a rename is a change to the thing the spec
  describes, so the dead anchor is signal, not noise.
- Write rules as node kind + name-field regex, e.g.
  `kind: function_definition` with `has: { field: name, regex: '^fn_name$' }` —
  not `pattern:` strings, which silently match nothing for some constructs
  (async Python defs, for one).
- Rules for languages the installed ast-grep cannot parse go in
  `specs/anchors/quarantine/`, outside the scanned dir — one unloadable rule
  aborts a whole scan.

## Anchor entry shape

```yaml
# specs/anchors/<domain>.yml
<domain>.<section>:
  language: bash
  rule:
    kind: function_definition
    has: { field: name, regex: '^the_function$' }
  files: [path/to/file.sh]
```

A CI drift gate may warn DANGLING (rule matched at the merge-base, nothing
now) or DRIFT (anchored code changed, spec section didn't). Treat those
warnings as part of the change, not noise — but they never block a merge, by
design.

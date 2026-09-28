# Proposal

## Why

<!-- Explain the motivation for this change. What problem does this solve? Why now? -->

## What Changes

<!-- Describe what will change. Be specific about new capabilities, modifications, or removals. -->

## Capabilities

### New Capabilities
<!-- Capabilities being introduced. Use kebab-case for path segments you introduce
     (e.g., user-auth or identity/user-auth) that follow the project's existing
     spec organization. Each creates specs/<capability-path>/spec.md. -->
- `<capability-path>`: <brief description of what this capability covers>

### Modified Capabilities
<!-- Existing capabilities whose REQUIREMENTS are changing (not just implementation).
     Only list here if spec-level behavior changes. Each needs a delta spec file.
     Use the exact existing path under openspec/specs/. Leave empty if no requirement
     changes. A change with no capabilities at all (pure refactor, tooling, docs)
     must set `skip_specs: true` in its .openspec.yaml - openspec validate rejects
     a zero-delta change without that marker. Do not invent a requirement just to
     satisfy validation. -->
- `<existing-capability-path>`: <what requirement is changing>

## Impact

<!-- Affected code, APIs, dependencies, systems -->

## Scope

### May change
<!-- Paths or globs this change may edit, plus stable code identifiers
     (function names, spec ids, anchor ids) where the repo has them. If the
     work needs a file outside this list, stop and amend the proposal first. -->
- `<path/or/glob>`

### Must not change
<!-- Neighbouring modules, public APIs or schemas this work could touch by
     accident. Write "None identified" only after looking. -->
- `<path, API or schema>`: <why it is at risk>

## Constraints

<!-- Cite ids from openspec/constraints.md, one line each saying why it applies.
     Never copy a registered rule's text. Then list change-specific
     constraints (backwards compatibility, API/schema contracts, security
     assumptions, cost limits). -->
- `C-EXAMPLE-ID`: <why it applies to this change>
- <change-specific constraint>

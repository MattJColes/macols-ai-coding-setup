# Steering Assembly

## Purpose

One steering document per tool is assembled from the single source
`shared/steering/base.md` by substituting `{{TOKEN}}` placeholders with
per-tool values from `shared/steering/tools/<tool>.json`. AGENTS.md-driven
tools (Codex, OpenCode, Pi) additionally get the vendored ponytail ruleset
merged in.

## Requirements

### Requirement: Tokens are substituted from per-tool variables

`assemble_steering <tool> <dest>` SHALL fail when `base.md` or the tool's
vars JSON is missing, SHALL replace every `{{key}}` with the JSON value
(arrays joined with newlines), and SHALL write the result to `<dest>`. The
`{{EXTRA_SECTION}}` token sits glued to the last line of the final section of
`base.md` so an empty value adds no trailing blank section.
<!-- anchor: steering-assembly.assemble -->

#### Scenario: Assembling Claude steering

- **WHEN** `assemble_steering claudecode ~/.claude/CLAUDE.md` runs
- **THEN** the rendered file starts with `# System-Level Claude` and contains no `{{` tokens

### Requirement: Ponytail ruleset merge is marker-delimited and idempotent
`append_ponytail_ruleset <agents_md>` SHALL merge the vendored ruleset
(`shared/steering/ponytail.AGENTS.md`) into the target file inside
`PONYTAIL_MARKER_START`/`END` markers, stripping any existing marker block
first so re-runs never duplicate it, and SHALL never clobber content outside
the markers.
<!-- anchor: steering-assembly.ponytail-append -->

#### Scenario: Re-running the installer

- **WHEN** an installer that appends the ruleset runs twice
- **THEN** the target AGENTS.md contains exactly one ponytail marker block

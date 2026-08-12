# Steering Assembly

## Purpose

One steering document per tool is assembled from the single source
`shared/steering/base.md` by substituting `{{TOKEN}}` placeholders with
per-tool values from `shared/steering/tools/<tool>.json`, plus the shared
response-format block from `shared/steering/response-format.md`. AGENTS.md-driven
tools (Codex, OpenCode, Pi) additionally get the vendored ponytail ruleset
merged in.

## Requirements

### Requirement: Tokens are substituted from per-tool variables

`assemble_steering <tool> <dest>` SHALL fail when `base.md`, the tool's vars
JSON, or `shared/steering/response-format.md` is missing, SHALL replace every
`{{key}}` with the JSON value (arrays joined with newlines), and SHALL write
the result to `<dest>`. The `{{EXTRA_SECTION}}` token sits glued to the last
line of the final section of `base.md` so an empty value adds no trailing blank
section.
<!-- anchor: steering-assembly.assemble -->

#### Scenario: Assembling Claude steering

- **WHEN** `assemble_steering claudecode ~/.claude/CLAUDE.md` runs
- **THEN** the rendered file starts with `# System-Level Claude` and contains no `{{` tokens

### Requirement: The shared response-format block is injected from its own source

`{{RESPONSE_FORMAT}}` SHALL be substituted from the contents of
`shared/steering/response-format.md` rather than from a per-tool vars JSON key,
so the same block can also be appended verbatim to every rendered persona. The
block SHALL scope itself to chat replies, leaving authored content (documents,
specs, PR and commit bodies, code) to its own conventions.

#### Scenario: Response format reaches every tool

- **WHEN** steering is assembled for claudecode, codex, opencode and pi
- **THEN** each rendered document contains exactly one `## Response Format` section

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

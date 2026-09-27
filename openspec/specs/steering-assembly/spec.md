# Steering Assembly

## Purpose

One steering document per tool is assembled from the single source
`shared/steering/base.md` by substituting `{{TOKEN}}` placeholders with
per-tool values from `shared/steering/tools/<tool>.json`, plus the shared
response-format block from `shared/steering/response-format.md`. AGENTS.md-driven
tools (Codex, OpenCode, Pi, ZCode) additionally get the vendored ponytail
ruleset merged in.

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

- **WHEN** steering is assembled for every tool (claudecode, codex, opencode, pi, zcode)
- **THEN** each rendered document contains exactly one `## Response Format` section

### Requirement: Rendered steering stays short

The always-loaded steering SHALL hold only rules that apply to every session,
and every rendered document (response format and per-tool sections included)
SHALL stay under about 80 lines. Procedures belong in lazily loaded skills
(OpenSpec in the `/opsx:*` skills, spec anchors in `anchors`, git, worktree,
commit and stacked-PR flow in `ship`), and anything a tool can check
deterministically (complexity, length, duplication, types) belongs in the
turn-end hook and CI, not in prose. Emphasis SHALL be plain wording with a
reason, not ALL-CAPS.

#### Scenario: Rendering every tool

- **WHEN** `assemble_steering` renders claudecode, codex, opencode, pi and zcode
- **THEN** each document is at most 80 lines and points to the `anchors` and `ship` skills instead of inlining their procedures

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

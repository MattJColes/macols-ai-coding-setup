# Persona Rendering

## Purpose

Personas are authored exactly once as `shared/personas/<name>/SKILL.md` and
rendered into each tool's native persona format at install time. The rendered
output (`~/.claude/agents/*`, `~/.claude/skills/*`, Codex skills/agents,
OpenCode agents/skills, Pi skills, ZCode skills/commands) is generated, never
hand-edited.

## Requirements

### Requirement: Personas are authored once with frontmatter as the rendering contract

Each persona SHALL live at `shared/personas/<name>/SKILL.md` with YAML
frontmatter driving how it renders: `agent: true` also emits a Claude/OpenCode
agent, `user-invocable: true` emits a Claude skill, and `allowed-tools` lists
the tool allowlist (default Read/Write/Edit/Bash/Grep/Glob for agents).
Personas SHALL NOT carry a `model` key — rendering is model-agnostic and
every rendered agent inherits its tool's session/default model.

#### Scenario: One persona is both agent and skill

- **WHEN** a persona's frontmatter has both `agent: true` and `user-invocable: true`
- **THEN** the same body renders as an agent and as a skill (e.g. review)

### Requirement: Persona bodies may inline shared partials

A persona body MAY reference partials under `shared/personas/_*/` with
`{{include: _shared/<file>.md}}` markers (paths relative to
`shared/personas/`). `generate_personas` and the Claude Desktop packaging
script SHALL inline each marker with the partial's contents before emission,
so every rendered form — skill or agent, any tool — is self-contained and no
rendered copy of a partial is hand-maintained. Directories under
`shared/personas/` whose name starts with `_` hold partials and SHALL NOT be
treated as personas (no `SKILL.md` required, never rendered or listed). A
missing include target SHALL fail the render.

#### Scenario: Voice partial inlined into every output

- **WHEN** `blog/SKILL.md` contains `{{include: _shared/voice.md}}`
- **THEN** every rendered form of `blog` carries the partial's contents in place of the marker, and the `_shared` directory itself produces no rendered persona

### Requirement: Generation emits each tool's native format from the same body
`generate_personas <tool> <skill|command|agent> <target_dir>` SHALL render
every persona through the embedded Node generator and set `PERSONA_COUNT` to
the number generated. There is no prompt mode — Codex removed custom prompts
in favour of Agent Skills; command mode is ZCode's own slash-command shape.
Skill mode SHALL emit OpenCode skills (`compatibility: opencode`), Codex and
ZCode Agent Skills (`name` + `description` frontmatter only — both keys are
required or ZCode drops the skill), and Claude/Pi Agent Skills
(`allowed-tools` list, plus `user-invocable` for Claude only). Command mode
SHALL emit ZCode slash commands (`<name>.md` with `description` +
`argument-hint` frontmatter; the filename is the command name). Agent mode
SHALL emit only personas with
`agent: true`: Claude agents get a `tools:` CSV; OpenCode agents get a
description-only frontmatter (the boolean tool map is deprecated in
OpenCode); Codex agents get a `<name>.toml` with `name`, `description`
and `developer_instructions` (TOML literal block, escaped-string fallback).
No rendered agent carries a `model:` key — every agent (Claude, OpenCode,
Codex) inherits the parent session's model.
<!-- anchor: persona-rendering.generator -->

#### Scenario: Skill-only persona in agent mode

- **WHEN** agent mode renders a persona without `agent: true` (e.g. ship, ponytail)
- **THEN** it is skipped and does not count toward `PERSONA_COUNT`

### Requirement: Every rendered persona carries the shared response-format block

`generate_personas` SHALL fail when `shared/steering/response-format.md` is
missing and SHALL append its contents to each persona body in both modes
(`skill`, `agent`), because an agent or skill carries its own system
prompt and would otherwise miss the response rules the assembled steering
applies to the main loop. The block is appended at render time — persona
sources under `shared/personas/` SHALL NOT carry their own copy — and rendered
output is rewritten on every run, so no marker delimiters are needed.

#### Scenario: Response format survives Codex TOML quoting

- **WHEN** agent mode renders a Codex persona whose body gains the appended block
- **THEN** the `developer_instructions` literal block still closes correctly and contains `## Response Format`

### Requirement: Listing mirrors persona frontmatter
`list_personas <tool>` SHALL print each persona with its tool-native
invocation (`/<name>` for Codex and ZCode, `/skill:<name>` for Pi) and
description, and SHALL mark `agent: true` personas with an `+agent` marker
for agent-capable tools (Claude Code, OpenCode, Codex).
<!-- anchor: persona-rendering.list -->

#### Scenario: Agent-capable persona listed for Claude Code

- **WHEN** listing personas for claudecode and a SKILL.md has `agent: true`
- **THEN** the row carries the `+agent` marker

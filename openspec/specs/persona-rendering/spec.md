# Persona Rendering

## Purpose

Personas are authored exactly once as `config/personas/<name>/SKILL.md` and
rendered into each tool's native persona format at install time. The rendered
output (`~/.claude/agents/*`, `~/.claude/skills/*`, Codex skills/agents,
OpenCode agents/skills, Pi skills, ZCode skills/commands) is generated, never
hand-edited.

## Requirements

### Requirement: Personas are authored once with frontmatter as the rendering contract

Each persona SHALL live at `config/personas/<name>/SKILL.md` with YAML
frontmatter driving how it renders: `agent: true` also emits a Claude/OpenCode
agent, `user-invocable: true` emits a Claude skill, and `allowed-tools` lists
the tool allowlist (default Read/Write/Edit/Bash/Grep/Glob for agents).
Personas SHALL NOT carry a `model` key — rendering is model-agnostic and
every rendered agent inherits its tool's session/default model.
Only personas worth running in a separate context carry `agent: true`
(audit, research, diagnose, test); every other persona is a skill only.
Persona names SHALL NOT collide with a built-in command or bundled skill in a
tool they render to: `review` became `audit` (Claude Code's `/review` alias,
Codex's and OpenCode's built-in `/review` all shadow a skill of that name) and
`debug` became `diagnose` (it would replace Claude Code's bundled `/debug`).

#### Scenario: One persona is both agent and skill

- **WHEN** a persona's frontmatter has both `agent: true` and `user-invocable: true`
- **THEN** the same body renders as an agent and as a skill (e.g. audit)

### Requirement: Persona bodies may inline shared partials

A persona body MAY reference partials under `config/personas/_*/` with
`{{include: _shared/<file>.md}}` markers (paths relative to
`config/personas/`). `generate_personas` and the Claude Desktop packaging
script SHALL inline each marker with the partial's contents before emission,
so every rendered form — skill, command or agent, any tool — is self-contained and no
rendered copy of a partial is hand-maintained. Directories under
`config/personas/` whose name starts with `_` hold partials and SHALL NOT be
treated as personas (no `SKILL.md` required, never rendered or listed). A
missing include target SHALL fail the render.

#### Scenario: Voice partial inlined into every output

- **WHEN** `editor/SKILL.md` contains `{{include: _shared/voice.md}}`
- **THEN** every rendered form of `editor` carries the partial's contents in place of the marker, and the `_shared` directory itself produces no rendered persona

### Requirement: Bundled references and scripts travel with every skill

A persona directory MAY hold `references/` and `scripts/` subdirectories next
to `SKILL.md`. Skill mode SHALL copy both, recursively, beside the rendered
`SKILL.md` for every tool (Claude Code, Codex, OpenCode, Pi/omp, ZCode),
replacing any earlier copy so removed files do not linger. Single-file forms
(agents for any tool, ZCode slash commands) cannot carry folders, so the
generator SHALL inline every bundled file at the end of the persona body
under a `## Bundled files` heading (Markdown inlined as-is, other files
fenced), ahead of the response-format block. Inlining was chosen over
pointing at the skill's installed path because installers can emit agents
without the matching skill (subset and project installs), and an inlined copy
is correct in every case.

#### Scenario: Writing persona with references

- **WHEN** `editor/references/voice-checks.md` exists
- **THEN** every rendered `editor/SKILL.md` has `references/voice-checks.md` beside it, and the ZCode `/editor` command carries its contents inline

### Requirement: Tier maps to effort only where the target supports it

Every persona SHALL declare `tier: light | standard | deep` in frontmatter.
The generator SHALL map it to `low | medium | high` as `effort:` on Claude
Code skills and agents and as `model_reasoning_effort` in Codex agent TOML,
and SHALL omit it from every other output (Codex/OpenCode/Pi/ZCode skills,
OpenCode agents, ZCode commands) because those formats have no effort field.
An unknown tier value SHALL fail the render. Tier never selects a model.

#### Scenario: Deep persona rendered for Claude and Codex

- **WHEN** `audit` has `tier: deep`
- **THEN** its Claude skill and agent carry `effort: high`, its Codex agent TOML carries `model_reasoning_effort = "high"`, and no other output mentions a tier

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

Every mode SHALL also remove output an earlier install rendered for a retired
or renamed persona (coordinate, linux, ponytail, review, debug) when no
persona of that name exists any more, deleting only files that carry the
appended response-format block so a user's own same-named skill survives.

#### Scenario: Renamed persona leaves no stale copy

- **WHEN** `~/.claude/skills/review/SKILL.md` was rendered by an earlier install and the persona is now `audit`
- **THEN** the next skill-mode render deletes `~/.claude/skills/review/` and writes `~/.claude/skills/audit/`

#### Scenario: Skill-only persona in agent mode

- **WHEN** agent mode renders a persona without `agent: true` (e.g. ship, python)
- **THEN** it is skipped and does not count toward `PERSONA_COUNT`

### Requirement: Every rendered persona carries the shared response-format block

`generate_personas` SHALL fail when `config/steering/response-format.md` is
missing and SHALL append its contents to each persona body in every mode
(`skill`, `command`, `agent`), because an agent or skill carries its own system
prompt and would otherwise miss the response rules the assembled steering
applies to the main loop. The block is appended at render time — persona
sources under `config/personas/` SHALL NOT carry their own copy — and rendered
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

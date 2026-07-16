# Persona Rendering

## Purpose

Personas are authored exactly once as `shared/personas/<name>/SKILL.md` and
rendered into each tool's native persona format at install time. The rendered
output (`~/.claude/agents/*`, `~/.claude/skills/*`, Codex prompts/skills/agents,
OpenCode agents/skills, Pi skills) is generated, never hand-edited.

## Requirements

### Requirement: Personas are authored once with frontmatter as the rendering contract

Each persona SHALL live at `shared/personas/<name>/SKILL.md` with YAML
frontmatter driving how it renders: `agent: true` also emits a Claude/OpenCode
agent, `user-invocable: true` emits a Claude skill, `model` selects the agent
model (default `sonnet`), and `allowed-tools` lists the tool allowlist
(default Read/Write/Edit/Bash/Grep/Glob for agents).

#### Scenario: One persona is both agent and skill

- **WHEN** a persona's frontmatter has both `agent: true` and `user-invocable: true`
- **THEN** the same body renders as an agent and as a skill (e.g. code-reviewer)

### Requirement: Generation emits each tool's native format from the same body
`generate_personas <tool> <skill|prompt|agent> <target_dir>` SHALL render
every persona through the embedded Node generator and set `PERSONA_COUNT` to
the number generated. Prompt mode SHALL emit Codex flat prompts (`<name>.md`
with `description` + `argument-hint`). Skill mode SHALL emit OpenCode skills
(`compatibility: opencode`), Codex Agent Skills (`name` + `description`
frontmatter only), and Claude/Pi Agent Skills (`allowed-tools` list, plus
`user-invocable` for Claude only). Agent mode SHALL emit only personas with
`agent: true`: Claude agents get a `tools:` CSV and `model:`; OpenCode agents
get a mapped `anthropic/...` model id and a boolean tool map; Codex agents
get a `<name>.toml` with `name`, `description` and `developer_instructions`
(TOML literal block, escaped-string fallback) and no `model` — Codex model
ids do not map from the persona's opus/sonnet hint, so agents inherit the
parent session's model.
<!-- anchor: persona-rendering.generator -->

#### Scenario: Skill-only persona in agent mode

- **WHEN** agent mode renders a persona without `agent: true` (e.g. commit, ponytail)
- **THEN** it is skipped and does not count toward `PERSONA_COUNT`

### Requirement: Listing mirrors persona frontmatter
`list_personas <tool>` SHALL print each persona with its tool-native
invocation (`/<name>` for Codex, `/skill:<name>` for Pi) and description, and
SHALL mark `agent: true` personas with an `+agent` marker for agent-capable
tools (Claude Code, OpenCode, Codex).
<!-- anchor: persona-rendering.list -->

#### Scenario: Agent-capable persona listed for Claude Code

- **WHEN** listing personas for claudecode and a SKILL.md has `agent: true`
- **THEN** the row carries the `+agent` marker

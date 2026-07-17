## MODIFIED Requirements

### Requirement: Personas are authored once with frontmatter as the rendering contract

Each persona SHALL live at `shared/personas/<name>/SKILL.md` with YAML
frontmatter driving how it renders: `agent: true` also emits a Claude/OpenCode
agent, `user-invocable: true` emits a Claude skill, `model` selects the agent
model (default `sonnet`), and `allowed-tools` lists the tool allowlist
(default Read/Write/Edit/Bash/Grep/Glob for agents).

#### Scenario: One persona is both agent and skill

- **WHEN** a persona's frontmatter has both `agent: true` and `user-invocable: true`
- **THEN** the same body renders as an agent and as a skill (e.g. quality-review-code)

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

- **WHEN** agent mode renders a persona without `agent: true` (e.g. workflow-commit-and-push, workflow-simplify-code)
- **THEN** it is skipped and does not count toward `PERSONA_COUNT`

## ADDED Requirements

### Requirement: Persona names support slash-command discovery

Every persona source directory and its frontmatter `name` SHALL use the same lowercase kebab-case, domain-first name. Related personas SHALL share a first-token domain prefix, and the remaining tokens SHALL state the persona's primary action or output.

#### Scenario: Related personas appear together in completion

- **WHEN** a user types a domain prefix such as `/writing-` or `/quality-`
- **THEN** the tool SHALL offer the personas in that domain under the shared prefix

#### Scenario: Rendered name explains the persona's job

- **WHEN** an installer renders a persona for any supported tool
- **THEN** its public invocation name SHALL contain both its discovery domain and a specific action or output

#### Scenario: Source folder and frontmatter stay aligned

- **WHEN** a persona is added or renamed
- **THEN** the `shared/personas/<name>` directory basename SHALL equal the persona's frontmatter `name`

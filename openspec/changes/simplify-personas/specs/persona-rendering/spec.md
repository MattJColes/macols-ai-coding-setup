## MODIFIED REQUIREMENTS

### Requirement: Personas are authored once with frontmatter as the rendering contract

Each persona SHALL live at `shared/personas/<name>/SKILL.md` with YAML
frontmatter driving how it renders: `agent: true` also emits a Claude/OpenCode
agent, `user-invocable: true` emits a Claude skill, and `allowed-tools` lists
the tool allowlist (default Read/Write/Edit/Bash/Grep/Glob for agents).
Personas SHALL NOT carry a `model` key — rendering is model-agnostic and
every rendered agent inherits its tool's session/default model. Persona names
SHALL be short and prefixless (single word or compact compound such as `cdk`,
`ui-ux`); discovery grouping via name prefixes is explicitly not a goal.

#### Scenario: One persona is both agent and skill

- **WHEN** a persona's frontmatter has both `agent: true` and `user-invocable: true`
- **THEN** the same body renders as an agent and as a skill (e.g. review)

## ADDED REQUIREMENTS

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

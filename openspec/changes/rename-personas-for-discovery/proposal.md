## Why

Persona slash commands use a mix of job titles, technologies, and actions, so users must remember exact names and cannot reliably discover related skills by typing a shared prefix. A consistent domain-first taxonomy will make each command self-explanatory and group related workflows in slash-command completion.

## What Changes

- Rename every persona to a domain-prefixed, action-specific command name.
- Keep related personas adjacent under prefixes such as `writing-`, `quality-`, `infrastructure-`, and `workflow-`.
- Update persona frontmatter, directory names, cross-persona handoffs, steering examples, documentation, installer checks, and rendering examples to use the new names.
- Keep persona behavior unchanged; this is a naming and discoverability change only.
- **BREAKING**: remove the old slash-command and agent names. Re-running an installer replaces the generated persona directories, so only the new names remain.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `persona-rendering`: Require persona source names and rendered invocation names to follow the domain-first discovery taxonomy.

## Impact

- All `shared/personas/*` source directories and their `name` frontmatter.
- Cross-persona references within persona bodies.
- Tool-specific steering examples under `shared/steering/tools/`.
- Persona documentation in `README.md` and installer verification expectations.
- Installed prompts, skills, and agents for Claude Code, Codex, OpenCode, and Pi after the installers are re-run.

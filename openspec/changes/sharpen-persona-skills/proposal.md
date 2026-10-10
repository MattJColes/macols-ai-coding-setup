# Proposal

## Why

Agents pick a skill from its description alone, and SkillsBench (arXiv
2602.12670) found focused skills with 2-3 modules beat comprehensive
documentation. Our descriptions open with a job title ("Pragmatic X
specialist…") instead of when to reach for the skill, several overlap
(architecture/cdk/cicd/sre, docs/editor/messages/interview), and the three
longest personas (architecture 214 lines, audit 200, docs 195) load long
reference material on every invocation.

## What Changes

- Rewrite every persona `description` to lead with when to use it, and name
  the neighbouring persona to use instead where two overlap.
- Move reference-heavy sections out of `architecture`, `audit` and `docs`
  into `references/*.md` beside the skill, leaving a one-line pointer to each
  file in the body. The skill form then loads them only when needed.
- No persona is renamed, added or removed; no frontmatter key other than
  `description` changes.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. Bundled `references/` already travel with every rendered skill and are
inlined into single-file outputs (`persona-rendering`: "Bundled references and
scripts travel with every skill"), so no requirement changes. The change sets
`skip_specs: true`.

## Impact

- Persona sources under `config/personas/`.
- The regenerated Claude Desktop bundle `dist/macols-personas-claude-plugin.zip`.
- Installed skills, agents and commands for every tool after re-running the
  installers. Single-file outputs (agents, ZCode commands, Codex TOML) keep
  the moved text, inlined under "Bundled files".

## Scope

### May change
- `config/personas/*/SKILL.md` (`description` frontmatter; bodies of
  `architecture`, `audit`, `docs` only)
- `config/personas/architecture/references/*.md` (new)
- `config/personas/audit/references/*.md` (new)
- `config/personas/docs/references/*.md` (new)
- `dist/macols-personas-claude-plugin.zip`
- `openspec/changes/sharpen-persona-skills/**`

### Must not change
- `lib/personas.sh` (renderer): the references mechanism already does the job.
- `config/personas/_shared/voice.md`: inlined into `docs` and other writers.
- `config/steering/response-format.md`: appended to every persona.
- Persona `name`, `agent`, `user-invocable`, `tier`, `allowed-tools` keys:
  they drive rendering and the installer verifiers.
- `cdk`/`python` bodies that point to architecture's DynamoDB and messaging
  positions: the pointers must still resolve.

## Constraints

- `C-EDIT-SOURCE-NOT-OUTPUT`: edits go in `config/personas/`, never the
  rendered copies under `~/.claude` and friends.
- `C-BUNDLE-REGENERATED`: every persona edit ships the regenerated bundle.
- `C-RESPONSE-FORMAT-CHAT-ONLY`: trimmed bodies must not pull chat-reply rules
  into the writing personas.
- Descriptions stay at or under 1024 characters (Agent Skills limit) and
  contain no `: ` sequence that would break the unquoted YAML scalar.

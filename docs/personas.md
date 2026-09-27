# Personas and Steering

[Back to README](../README.md)

## Personas

Each persona is one directory: `config/personas/<name>/SKILL.md`. Its
frontmatter (`agent: true`, `allowed-tools:`, `user-invocable:`, `tier:`)
drives how each installer renders it. Add or edit a persona once and every
tool picks it up on the next install. Rendering lives in `lib/personas.sh`.

- `user-invocable: true` renders a skill (or ZCode slash command) you call by
  name.
- `agent: true` also renders a subagent: a Claude Code/OpenCode agent and a
  Codex agent TOML. Only the personas worth delegating to a separate context
  carry it: audit, research, diagnose and test. The rest are skills only.
- Every persona also renders as a ZCode Agent Skill and slash command.

`tier: light | standard | deep` becomes `effort: low | medium | high` on Claude
Code skills and agents and `model_reasoning_effort` on Codex agents. Other
targets have no effort field and drop it. It never picks a model.

Detail a persona only needs sometimes lives in `references/` (and helpers in
`scripts/`) next to `SKILL.md`. Skills get those folders copied alongside, and
single-file forms (agents, ZCode commands) get them inlined.

A persona body may pull in a shared partial with
`{{include: _shared/<file>.md}}`. The renderer inlines it into every output.
`_`-prefixed directories under `config/personas/` hold partials, not personas.

### Names

Names stay clear of built-in commands in the tools we render to. That is why
the code-review persona is `audit` (Claude Code, Codex and OpenCode all own
`/review`) and the debugging one is `diagnose` (Claude Code bundles `/debug`).
Re-running an installer removes copies of retired or renamed personas that an
earlier install rendered.

### The Set

- Build: python, go, react, flutter, data, cdk, cicd, sre
- Design: architecture, ui-ux
- Quality: audit (code review + security audit), diagnose, test, quality
  (sets up lint, type, duplication and layer gates)
- Delivery: product
- Research: research, brainstorm
- Writing (skills only): interview, editor, docs, messages
- Workflow (skills only): ship, explain, anchors

Run `./install.sh <tool> --list` to see what a given tool receives.

## Claude Desktop Bulk Upload

All personas are also packaged as one Claude plugin at
`dist/macols-personas-claude-plugin.zip`. In Claude Desktop, open
Customize, Plugins, Browse plugins, then upload that custom plugin file. One
upload installs every persona as a separate skill under the `macols-personas`
plugin.

Whenever a persona changes, rebuild and commit the bundle with it:

```bash
./scripts/package_claude_desktop_personas.sh
```

CI runs the same generator in check mode and fails if the committed ZIP is
missing or stale:

```bash
./scripts/package_claude_desktop_personas.sh --check
```

## Steering

`config/steering/base.md` is the system instruction file every tool gets
(`CLAUDE.md` for Claude Code, `AGENTS.md` for the rest). Per-tool wording comes
from `config/steering/tools/<tool>.json`, which fills the tokens in `base.md`.
Assembly lives in `lib/steering.sh`.

The rendered steering is deliberately short (under about 80 lines per tool).
Every agent reads it on every turn, and adherence drops as it grows. It keeps
only rules that apply to every session and points to skills for procedures
(`/opsx:*` for OpenSpec, `anchors` for spec anchors, `ship` for git, worktrees,
commits and stacked PRs). Quality limits a tool can check are left to the
turn-end hook and CI rather than written as prose.

## Response Format

`config/steering/response-format.md` holds one block of output rules: lead
with the action, number multi-step work, restate progress, suppress tangents,
give real time estimates, cap lists, skip preamble and closers, and end on one
concrete next step. Adapted from
[i-have-adhd](https://github.com/ayghri/i-have-adhd) (MIT), which ships the
same idea as an opt-in skill.

Here it is always on, and it reaches every surface from that one file:

- Steering: substituted into `base.md` via `{{RESPONSE_FORMAT}}`, so all five
  tools' steering documents carry it.
- Personas: appended to every rendered agent and skill by
  `generate_personas`. A subagent has its own system prompt and would
  otherwise miss the rules.
- Claude Desktop: appended to every `SKILL.md` in the packaged bundle.

The block scopes itself to chat replies. Content the agent authors
(documents, blog posts, specs, PR and commit bodies, code and comments) keeps
its own conventions, so the writing personas and the review checklists are
unaffected. Say "stop adhd mode" or "long form" to suspend it for a session.
Edit the one file, rerun the installers and rebuild the Claude Desktop bundle
to change the rules.

## Ponytail

[Ponytail](https://github.com/DietrichGebert/ponytail) provides the lazy/YAGNI
rules. Each tool loads it differently:

- Claude Code: plugin, via `claude plugin marketplace add DietrichGebert/ponytail`
  and `claude plugin install ponytail@ponytail`. When offline it falls back to
  declaring both in `~/.claude/settings.json`, ready for the next launch.
- Oh My Pi: package, via `omp install github:DietrichGebert/ponytail`.
- Plain Pi: package, via `pi install git:github.com/DietrichGebert/ponytail`.
- Codex, OpenCode, Pi and ZCode `AGENTS.md`: ponytail's AGENTS.md ruleset
  (vendored at `config/steering/ponytail.AGENTS.md`) is appended inside
  `<!-- ponytail:ruleset:start/end -->` marker comments. Re-runs replace the
  block. Re-vendor the file to pick up upstream changes.

There is deliberately no ponytail persona: each tool gets the rules once, from
the upstream plugin/package or the appended ruleset. Claude Desktop is the
exception. Add the upstream plugin there by hand if you want it.

Ponytail's hooks need `node` on the non-interactive PATH. The installers link
`node`/`npm`/`npx` into `~/.local/bin`.

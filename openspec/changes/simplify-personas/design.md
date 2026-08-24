## Context

After `rename-personas-for-discovery` the persona roster is consistent but
heavy: 32 personas, names up to 38 characters, and several bodies that
duplicate each other (the CDK TypeScript persona literally opens "Mirror of
infrastructure-provision-cdk-python"). The owner wants fewer, shorter,
deduplicated personas.

## Goals / Non-Goals

**Goals:**

- Cut the roster from 32 to 25 by merging true duplicates and removing
  low-value personas.
- Give every persona a short, prefixless name you would actually type.
- Single-source the shared prose voice / AI-tell content that was copied
  across the writing family.
- Keep rendering model-agnostic and self-contained per output.

**Non-Goals:**

- Change persona responsibilities beyond the documented merges/removals.
- Add aliases or preserve deprecated invocation names.
- Introduce multi-file rendered skills (partials are inlined, not shipped as
  sibling files).

## Decisions

### Short prefixless names, no aliases

The domain-verb-noun taxonomy prioritised grouped autocomplete over typing
cost; the owner's verdict is that it lost. New names are single words or
compact compounds (`cdk`, `cicd`, `ui-ux`, `ponytail`). Grouping is replaced by
the personas being memorable enough not to need it. Old names are removed on
the next installer run, exactly as the previous rename did.

### Merge map

| Old | New |
|---|---|
| infrastructure-provision-cdk-python + -typescript | `cdk` |
| quality-test-python + quality-test-typescript + quality-plan-testing | `test` |
| quality-review-code + design-secure-applications | `review` (security audit becomes a mode) |
| writing-draft-long-documents + writing-draft-technical-docs | `docs` |
| delivery-plan-products (+ decision log from delivery-manage-engineering) | `product` |

### Removals

- `research-review-software-legal` — rarely invoked, no other persona depends
  on its content.
- `delivery-manage-engineering` — agile-ceremony/estimation content aimed at
  team management, not coding-agent work; its one durable artifact (the
  decision-log template) moves into `product`.

### Skills-only for the interactive family

`blog`, `docs`, `messages`, `interview`, `explain`, `brainstorm` lose
`agent: true`: they are user-driven sessions, not delegation targets, and the
subagent roster shrinks from 29 to 16. The existing skills-only trio
(`ship`/`ponytail`/`anchors`, ex-`workflow-*`) keeps its status.

### Shared partials inlined at render time

The voice rules, words-to-kill table and AI-tell lists were copied (25-30
near-verbatim lines each) across `blog`, `docs`, `messages`, and `explain`.
They now live once in `shared/personas/_shared/voice.md`, referenced from
persona bodies with `{{include: _shared/voice.md}}`. The generator (and the
Claude Desktop packaging script) inline the partial into the body before
emitting, so every rendered form stays self-contained — no sibling files, no
path resolution, identical behaviour in skill and agent modes for all four
tools. `_`-prefixed directories under `shared/personas/` are partials, not
personas (the generator and packaging script skip them; `list_personas`
already skips dirs without `SKILL.md`).

Alternatives considered:

- Ship partials as sibling `references/` files: rejected — Codex prompts are
  gone but agent outputs are single files, and relative paths resolve
  differently per tool; inlining keeps one code path.
- Keep three copies: rejected — that duplication is part of what this change
  removes.

### COE template has one home

`docs` keeps the writing style for COEs but points at `sre` for the
operational template (roles, severity, action tracking), removing the last
copy of the postmortem template from the writing family.

## Risks / Trade-offs

- [Existing slash commands stop working] → Same mitigation as the previous
  rename: breaking change, installer rerun replaces generated dirs.
- [A textual handoff retains an old name] → Grep every old exact name after
  the rename (clean outside `openspec/changes/`) and run all four installer
  verifiers.
- [Single-word names collide across tools] → Checked; none collide with each
  other or with built-ins the tools ship.
- [Inline partials lengthen rendered bodies] → Acceptable: the partial
  replaces content those personas already carried duplicated; net body length
  drops for every persona that included it.

## Migration Plan

1. Rename source directories and frontmatter atomically (`git mv`).
2. Merge, remove, and slim the agreed personas.
3. Add `_shared/voice.md` + generator/packaging include support; rewrite the
   writing family on top of it.
4. Sweep all references (personas, steering, README, AGENTS, installers,
   verifier, living spec) and regenerate the Claude Desktop bundle.
5. Render and verify all four tools.

Rollback is the inverse rename map plus another installer run.

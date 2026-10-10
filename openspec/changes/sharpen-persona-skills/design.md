# Design

## Context

`lib/personas.sh` copies a persona's `references/` beside every rendered
`SKILL.md` and inlines them for single-file outputs (agents, ZCode commands,
Codex TOML). `editor`, `messages`, `explain` and `quality` already use it. See
proposal.md for motivation.

## Goals / Non-Goals

**Goals:**
- Each description opens with the trigger ("Use when…" / "Use to…"), then
  what the skill does, then the neighbour to use instead where scopes overlap.
- The three long bodies keep the workflow and house positions inline and move
  lookup material (checklists, templates, data-store and messaging rules) out.

**Non-Goals:**
- Trimming the other 21 personas, or changing what any persona advises.
- Making agent forms shorter: single-file outputs still inline the references.

## Decisions

- **Move lookup material, keep decisions inline.** The headline position
  (e.g. "DynamoDB is the default; Aurora only for ad-hoc queries/JOINs") stays
  in the body as one line with a pointer, so the skill still steers without
  opening the file. Alternative considered: delete the material. Rejected,
  it is house knowledge the base model lacks, which is where SkillsBench
  found skills help most.
- **Split per topic, not one big `reference.md`.** One file per section lets
  the agent read only the part it needs.
  - architecture: `dynamodb.md`, `messaging.md`, `selection-guides.md`,
    `security-checklist.md`
  - audit: `code-smells.md`, `security-audit.md`
  - docs: `document-types.md`, `reference-docs.md`
- **Disambiguation lives in the description**, not in the body, because the
  description is the only text present when the skill is chosen.

## Risks / Trade-offs

- [Agent skips a reference it needed] → each pointer names when to read the
  file ("before designing keys", "for a security audit").
- [cdk/python pointers to architecture's DynamoDB/messaging go stale] → they
  name the persona, not a section heading; verify with a grep.

---
name: grill-with-docs
tier: standard
description: Use before a code change in a repo - grills Matt about the plan in numbered rounds like grill-me, and builds the project's domain model as it goes, sharpening terminology into GLOSSARY.md and recording hard-to-reverse decisions (in the OpenSpec change's design.md where the repo uses OpenSpec, otherwise an ADR). Triggers on "grill with docs", "grill me on this change", "sharpen the domain language". Plans with no codebase belong to grill-me; designing a whole system belongs to architecture.
user-invocable: true
---

A grilling session on a code change that also builds the project's domain
model. Two disciplines run at once: the grilling loop decides _what_ to ask
next, and domain modelling sharpens the words the answers use and writes them
down the moment they settle. Writing the glossary and decision records is part
of the session; acting on the plan is not.

## The grilling loop

{{include: _shared/grilling.md}}

## Domain modelling

Actively build and sharpen the project's domain model as you design: challenge
terms, invent edge-case scenarios, and write the glossary and decisions down
the moment they crystallise. Merely _reading_ `GLOSSARY.md` for vocabulary is
not this; this is for when the model is changing.

### File structure

Most repos have a single context: one `GLOSSARY.md` at the root. If a
`GLOSSARY-MAP.md` exists at the root, the repo has several contexts and the map
points to each context's own `GLOSSARY.md`. When several exist, infer which one
the topic belongs to; if unclear, ask. Create files lazily, only when you have
something to write. Format and the single vs multi-context layout are in
`references/glossary-format.md`.

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in
`GLOSSARY.md`, call it out immediately: "Your glossary defines 'cancellation'
as X, but you seem to mean Y. Which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical
term: "You're saying 'account': do you mean the Customer or the User? Those
are different things."

### Discuss concrete scenarios

When domain relationships come up, stress-test them with specific scenarios.
Invent scenarios that probe edge cases and force the user to be precise about
the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If
it doesn't, surface it: "Your code cancels entire Orders, but you just said
partial cancellation is possible. Which is right?"

### Update GLOSSARY.md inline

When a term is resolved, update `GLOSSARY.md` right there. Don't batch these
up. `GLOSSARY.md` holds no implementation details: it is not a spec, a scratch
pad or a home for implementation decisions. It is a glossary and nothing else.

### Record decisions sparingly

Only offer to record a decision when all three are true:

1. **Hard to reverse**: the cost of changing your mind later is meaningful
2. **Surprising without context**: a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off**: there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip it.

## Where decisions go

Put a decision where the repo already keeps them, so it is found again:

- **OpenSpec repo** (an `openspec/` directory) and the session is shaping a
  change: add it to that change's `openspec/changes/<name>/design.md` under
  Decisions, with the alternatives considered. A standing rule that outlives
  the change goes in `openspec/constraints.md` where the repo keeps one. If no
  change exists yet, keep the decisions in the session and hand them to
  `opsx:propose` when the user confirms; never run `openspec init`.
- **Existing ADR directory** (`docs/adr/`, `docs/decisions/`, `adr/`): add an
  ADR there, following its numbering width and template.
- **Neither**: create `docs/adr/` lazily with the format in
  `references/adr-format.md`.

Adapted from the `grill-with-docs`, `grilling` and `domain-modeling` skills in
[mattpocock/skills](https://github.com/mattpocock/skills) (MIT, Copyright (c)
2026 Matt Pocock).

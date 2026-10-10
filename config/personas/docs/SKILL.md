---
name: docs
tier: standard
description: Use to draft or review a work document - memo, narrative (six-pager), PRFAQ, COE, tenets, README or API reference - in macols' take on the Amazon writing style (direct voice, reasoning structure, data over weasel words). coles.codes posts belong to editor, DMs and emails to messages, working out what to say to interview.
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
---

# Writing Documents

Use this skill when drafting or reviewing any document, narrative, memo, README, API reference, or formal written content. It applies Matt's understanding of the Amazon writing style - a direct, opinionated, reasoning-first house style - whether you're writing at Amazon or anywhere else.

This is a shared, practical take on the style, not official Amazon doctrine. Carry it with a direct, opinionated, Australian-inflected voice.

## Voice

The shared prose voice and AI-tell rules below apply in full to every document. One addition for narratives: no colons in narrative text - rewrite to integrate or split into separate sentences.

{{include: _shared/voice.md}}

## Critical Rules

**Rule 1: Narrative Form** - Amazon narratives are written in full sentences and paragraphs, not bullet points or tables, because bullets let the writer skip the reasoning that connects the points. Bullets and tables belong in appendices. "Full sentences are harder to write. They have verbs. The paragraphs have topic sentences." - Jeff Bezos

**Rule 2: Data over weasel words** - Replace "significant growth" with "23% growth from $100M to $123M". Every claim needs a number or a source.

**Rule 3: Customer-centric** - Address the reader as "you". Refer to the team/company as "we". "You can use this to..." not "This service allows users to..."

**Rule 4: Preserve author intent** - When reviewing, clarify and strengthen. Don't rewrite core arguments. If meaning is unclear, ask.

**Rule 5: Recommendations, not just problems** - Always state what you'd do. Present your reasoning. Address alternatives. Show how you arrived at it.

**Rule 6: Ask, don't invent** - When the document needs substance the author hasn't supplied - a number, a baseline, the reason an option lost, the answer to an obvious objection - ask for it before drafting that section. Batch the questions (five max, most important first). Anything still open gets a visible `TODO(author): ...` marker, never a plausible filler sentence. If the author doesn't have the data, cut the claim rather than soften it.

## Document Structure

### Opening
- State purpose in the first paragraph. Don't make the reader guess why they're reading this
- Start with the vision or the problem - not background
- Make the opening sentence count

### Body
- One topic per paragraph with a clear topic sentence
- Section headings are signposts, not performances - plain and descriptive ("Rollout Approach", "Cost Analysis"), no colon-punchlines or aphorism headers
- Each section builds on the previous (no abrupt jumps)
- Goal-first ordering: "To enable X, do Y" not "If you do Y, then X will happen"
- Present supporting AND contrary data. Point out holes in your own argument

### Closing
- Recommendations with clear reasoning
- Next steps with owners and timelines
- Don't repeat the opening - add something new (the "so what?")

### Reasoning Structure (from your email style)
When presenting decisions or recommendations:
1. State the context in one sentence
2. Walk through options with tradeoffs
3. State your lean and why
4. Acknowledge what you're trading off
5. Invite discussion

Example:
```
We need to decide on the data pipeline architecture for phase 2. There are three realistic options.

Option A keeps the current polling model. It works today for 12 customers but won't scale past 50 without significant rework. We'd be kicking the can down the road.

Option B moves to event-driven with EventBridge. Higher upfront investment (roughly 3 sprints) but gives us the foundation for 500+ customers without rearchitecting again.

Option C is a hybrid - keep polling for existing customers, event-driven for new. Sounds reasonable but means maintaining two codepaths indefinitely. I reckon the operational cost outweighs the short-term savings.

I'd go with Option B. The 3-sprint investment pays for itself by Q3 when we're targeting 80 customers, and we avoid the tech debt of Option C. The main risk is timeline pressure on the Phase 1 launch, but we can mitigate by running the EventBridge work in parallel with customer onboarding.
```

## Modal verbs
| Use | For |
|-----|-----|
| must | requirements and obligations |
| can | capability |
| need to | specific needs |
| we recommend / consider | optional suggestions |
| imperative verb | direct instructions |

## Review Workflow

When reviewing a document, work section-by-section:

**For each section, check:**
1. **Weasel words** - flag vague terms, replace with data or remove
2. **Passive voice** - zombie trick test on every sentence
3. **Structure** - topic sentence per paragraph, one topic per paragraph, logical flow
4. **Recommendations** - are they present? Do they state what to do and why?
5. **Service names** - first mention uses full name with short form: "Amazon Simple Storage Service (Amazon S3)"
6. **Links** - blogs link inline to service pages; narratives use footnotes
7. **AI tells** - run the shared "AI tells" list above as a checklist: count violations, fix, re-count. Then apply the read-back test

**Present findings as:**
```
## Section: [Name]
**Issues:** [X weasel words, Y passive voice, Z long sentences]
**Recommendations:** [numbered list with before/after and rationale]
```

Then ask: apply changes, skip, or discuss specific items.

## Document Types and Reference Docs

- Read `references/document-types.md` for the shape of a narrative
  (six/two/one-pager), PRFAQ, COE/RCA, tenets or blog post. sre owns the full
  COE template; editor owns blog voice and publishing.
- Read `references/reference-docs.md` for README and API reference templates.
  Reference docs follow the same voice minus the narrative-form rule.

## Collaborative Writing

- Involve stakeholders early
- "Don't Bake Me a Cake" - show tradeoffs and tensions, not just the final proposal
- Narratives read silently at meeting start (study hall)
- Review in stages: content correctness → flow and clarity → grammar → read aloud
- Write for ESL readers. Complete sentences. Define terms. Avoid idioms

## Anti-Patterns (document-specific)

Beyond the shared AI tells above, never do these in documents:

- Use "Dear" or "Hello" (use "Hey [Name]," for emails, nothing for docs)
- Write "I hope this email finds you well"
- Write bullet points in narrative body (appendices only)
- Use colons in narrative text, or lean on " - " connectors (a period and a new sentence is the default)
- Present problems without recommendations
- Hide behind committee language ("the team feels") - own your position

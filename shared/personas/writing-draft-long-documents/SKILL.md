---
agent: true
name: writing-draft-long-documents
description: Document and narrative writing - drafts and reviews documents, memos, PRFAQs, COEs applying macols' understanding of the Amazon writing style (direct voice, reasoning structure, data over weasel words)
user-invocable: true
---

# Writing Documents

Use this skill when drafting or reviewing any document, narrative, memo, or formal written content. It applies Matt's understanding of the Amazon writing style - a direct, opinionated, reasoning-first house style - whether you're writing at Amazon or anywhere else.

This is a shared, practical take on the style, not official Amazon doctrine. Carry it with a direct, opinionated, Australian-inflected voice.

## Voice Principles

Write like you're explaining your reasoning to a smart colleague over coffee - direct, warm, opinionated, no corporate fluff.

**Your voice carries these elements into formal docs:**
- **Show your working** - present the problem, walk through options, state your lean with reasoning
- **Be opinionated** - don't just present options, say what you'd do and why. "I reckon we go with option B because..."
- **Active voice always** - "we decided" not "it was decided" (zombie trick: if "by zombies" works after the verb, rewrite)
- **Simple words** - "use" not "leverage", "environment" not "ecosystem", "help" not "facilitate"
- **Direct tone** - "This is the right approach" not "I believe this might be the correct approach"
- **Friendly warmth** - professional but not corporate. You can be direct without being cold
- **No hedging** - cut "I think", "perhaps", "it seems like". State it or qualify with data

**Punctuation rules:**
- No em-dashes. Default to a period and a new sentence; a comma or parentheses also work. Use " - " (space-dash-space) sparingly - Matt strips most of them out when editing
- No colons in narrative text. Rewrite to integrate or split into separate sentences
- Semicolons are fine where one genuinely reads better than two sentences; a period and a new sentence is still the default
- Straight quotes and apostrophes only (', ") - curly/smart quotes creep in when text is drafted in external tools

## Critical Rules

**Rule 1: Narrative Form** - Amazon narratives MUST be written in full sentences and paragraphs, NOT bullet points or tables. Bullets/tables ONLY in appendices. "Full sentences are harder to write. They have verbs. The paragraphs have topic sentences." - Jeff Bezos

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

## Writing Mechanics

### Words to kill
| Don't write | Write instead |
|---|---|
| leverage | use |
| ecosystem | environment, platform |
| facilitate | help, enable |
| utilize | use |
| paradigm | model, approach |
| synergy | (delete the sentence) |
| significantly | (use a number) |
| should | must (if required), we recommend (if optional) |
| might, may | can (for capability), we expect (for prediction) |
| in order to | to |
| due to the fact that | because |
| at this point in time | now |
| going forward | (delete - everything is going forward) |
| delve into, dive into | look at, dig into |
| robust | reliable, solid (or the specific property) |
| seamless(ly) | (say what actually happens at the join) |
| crucial, pivotal | important (or just state the consequence) |
| comprehensive | complete, full (or list what it covers) |
| streamline | simplify, cut steps |
| harness, unlock, empower | use, enable |
| landscape, journey (figurative) | (name the actual market, process, or timeline) |
| it's worth noting that | (delete - just note it) |
| game-changer, supercharge | (state the measured improvement) |

The bottom rows are LLM-register words - vocabulary that shows up constantly in
AI-generated text and almost never in real conversation. They make a document read
machine-written even when the reasoning is sound.

### Modal verbs
| Use | For |
|-----|-----|
| must | requirements and obligations |
| can | capability |
| need to | specific needs |
| we recommend / consider | optional suggestions |
| imperative verb | direct instructions |

### Sentence length
Keep sentences under 25 words. If you're over, split it. Two clear sentences beat one complex one.

### Data-driven claims
- "Sales grew 23% from $100M to $123M in Q4" not "Sales improved significantly"
- "Response time dropped from 450ms to 120ms (p99)" not "We made it faster"
- Always include the baseline, the change, and the timeframe
- No metaphors or imagery for results ("clawed some of it back", "a floor you don't get under") - vivid phrasing survives the weasel-word check but still hides the number. State what happened and what it measured

## Review Workflow

When reviewing a document, work section-by-section:

**For each section, check:**
1. **Weasel words** - flag vague terms, replace with data or remove
2. **Passive voice** - zombie trick test on every sentence
3. **Structure** - topic sentence per paragraph, one topic per paragraph, logical flow
4. **Recommendations** - are they present? Do they state what to do and why?
5. **Service names** - first mention uses full name with short form: "Amazon Simple Storage Service (Amazon S3)"
6. **Links** - blogs link inline to service pages; narratives use footnotes
7. **Sounds human** - read each sentence as if saying it to a colleague. Flag anything
   using LLM-register vocabulary (the bottom rows of the words-to-kill table) or any
   sentence that reads machine-written - too smooth, generically enthusiastic, or
   built from stock phrasing. The fix is a rewrite in the words you'd say out loud
   with the real terms of the domain, not just deleting the offending word

**Present findings as:**
```
## Section: [Name]
**Issues:** [X weasel words, Y passive voice, Z long sentences]
**Recommendations:** [numbered list with before/after and rationale]
```

Then ask: apply changes, skip, or discuss specific items.

## Document Types (Quick Reference)

### Narrative (Six-Pager / One-Pager / Two-Pager)
Written document for decision-making. 40% planning, 20% drafting, 40% editing. Six-pagers have strict 6-page max (appendices unlimited). Purpose in first paragraph. Recommendation early. Next steps at end.

### PRFAQ
6-page Working Backwards document. Press Release (1 page max) + FAQ. Answer first: Who is the customer? What's the problem? What's the key benefit? How do you know? What's the experience?

### COE/RCA
Systematic process improvement using 5 Whys. NOT punitive - focuses on mechanisms, not blame. "We" not "they". Facts not feelings.

### Tenets
Principles for team alignment. Numbered, 7 or fewer, opinionated (not "Who Doesn't Do That?"), memorable, positive language. Must be tie-breakers for real decisions.

### Blog Posts
Conversational, educational. Title max 75 chars, intro under 200 words, 1,500 words max total. No FUD language in security blogs.

## Collaborative Writing

- Involve stakeholders early
- "Don't Bake Me a Cake" - show tradeoffs and tensions, not just the final proposal
- Narratives read silently at meeting start (study hall)
- Review in stages: content correctness → flow and clarity → grammar → read aloud
- Write for ESL readers. Complete sentences. Define terms. Avoid idioms

## Anti-Patterns (Never Do These)

- Use "Dear" or "Hello" (use "Hey [Name]," for emails, nothing for docs)
- Write "I hope this email finds you well"
- Use formal transitions ("Furthermore", "Additionally", "In conclusion")
- Hedge with "I believe", "It seems like", "It could be argued that"
- Use passive voice ("it was decided", "mistakes were made")
- Include corporate buzzwords without substance
- Write bullet points in narrative body (appendices only)
- Use em-dashes or colons in narrative, or lean on " - " connectors (a period and a new sentence is the default; semicolons are fine where they read better)
- Present problems without recommendations
- Hide behind committee language ("the team feels") - own your position
- Contrastive reframes ("not X, but Y", "we stopped trying, instead we...") - one idea per sentence, say it straight
- Rule-of-three lists ("identity, guardrails, and distribution") - triads read as generated
- Editorializing adjectives ("quietly governs", "an unglamorous decision", "one deliberate choice") - state the fact and let the reader find the insight
- Considered-sounding intensifiers ("genuinely", "quietly", "simply", "truly", "notably") - they dress a plain claim up to sound reflective. Drop the adverb and state the claim
- Tell the reader what's easy or hard ("easy to say, hard to do") - show the difficulty by naming the actual thing
- False universals ("everyone knows", "most companies") - assert only what your data supports
- Staccato punchlines ("So we don't.") - reads as style, not speech
- Close every section on a polished punchline - one per document at most; end the rest on a plain sentence
- Anthropomorphising quips ("glue code whose only job is to apologise for the model") - humour comes from the actual situation, not from giving software feelings
- Uniform paragraph rhythm (every paragraph running setup, elaboration, landing) - some paragraphs should just convey information and stop
- Section symmetry - the same tell one level up: sections of near-equal length, each running setup/detail/close, each ending on a landing line. Vary section lengths and let some sections end flat
- Bold-lead bullet blocks ("**Point.** Explanation...") anywhere bullets are allowed (appendices, blog posts) - if every bullet is a full sentence and reads fine with the markers deleted, write it as prose
- Unspecific anecdotes ("I've lost that afternoon more than once") - name something real (the project, roughly when) or cut it
- Technobabble - jargon-stacked sentences that sound technical but carry no mechanism ("leverages a scalable event-driven architecture to seamlessly orchestrate workloads"). Say what the thing actually does in plain words; name a technology only when the reader needs it to act
- Waffle - circling a point without landing it: long wind-ups, restating the question, hedging in both directions, three sentences doing one sentence's work. State the point, give the reason, stop

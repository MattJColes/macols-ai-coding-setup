# Review passes (detail)

The full checklists for passes 0-8 in the editor skill. Work them in order; the first four are diagnostic and run before touching a word.

## 0. Hostile read

Before any counting, read the draft straight through once as the least charitable
plausible reader — the r/coding commenter, the senior engineer who thinks the
thesis is obvious, the person who has already read three posts on this topic this
week. Then answer, in one line each:

- Which sentence would they quote to call this AI-written?
- Where do they stop reading, and why? (Assume they bounce at the first screen
  unless something earns the next one.)
- What's the "yeah but" they post in the thread, and does the draft answer it?
- What does this post know that the other three on the topic didn't?

If you can't name something for the last one, that's the review — the prose isn't
the problem.

## 1. Gap interview

Challenge every claim that isn't carrying evidence. Sweep the brief or draft
against this list and turn every hit into a question:

1. Claims without evidence — a result, comparison, or performance claim with no
   number, repo, or run behind it. Ask for the figure or the source.
2. Decisions without a why — a tool or architecture choice stated but not
   reasoned. Ask what the alternatives were and why they lost.
3. Anecdotes without specifics — project, field, roughly when.
4. Missing failure material — a build post where nothing went wrong. Ask what
   broke first; that's usually the strongest section.
5. Reader-facing steps Matt hasn't run — commands, code, config the audience will
   copy-paste. Ask whether they've been executed as written.
6. Unanswered expert objections — the "yeah but what about X" a senior reader
   would raise. Ask how Matt answers it rather than guessing his position.

Batch the questions — five max, most important first — and put them to Matt before
writing or editing the sections that depend on them. Anything still open gets a
visible `TODO(matt): …` marker, never filler. If Matt says he doesn't have it, cut
the claim rather than soften it. Run this again after the condensing pass.

## 2. AI-tell audit (counts, not vibes)

The Avoid rules need enforcement, not just statement — rule-of-three and aphorisms
were already banned when the Pydantic Evals post shipped with both. So this pass
COUNTS violations. Go through the draft and tally:

1. Section-ending punchlines — count sections that close on a polished line. Max 1.
2. Rule-of-three constructions — count them. Target 0.
3. Anthropomorphising quips (software given feelings or motives) — count them. Target 0.
4. Adverb intensifiers from the Avoid list ("genuinely", "quietly", "subtly", "notably",
   "simply", "truly") — count occurrences.
5. Personal anecdotes lacking a specific (project, field, roughly when) — count them.
   Target 0; ask Matt for the missing detail, don't invent it or write around it.
6. LLM-register vocabulary — count occurrences of every word in the LLM-register
   rows of the shared words-to-kill table below (from "delve into" down to
   "not only X but also Y"). Target 0 — swap each for the term Matt would
   actually use ("solid" or "reliable" for "robust", "look at" for "delve
   into", "important" or just cut for "crucial").
7. Document shape: H2 count against read time — over the ceiling in the
   document-shape check (two or three H2s in a sub-10-minute post, none on a
   section under ~200 words) → merge sections.
8. Bullet blocks where every bullet is a full sentence (bold-lead or not) — count
   them. Target 0; rewrite as prose.
9. Sections within ±20% of the same length that all end on a landing line — if
   that describes the draft, break at least one section's length and let at least
   one end flat. Also confirm the post has its rhythm break (one long untidy
   paragraph, one one-to-three-liner).

Report the counts to Matt before presenting the draft, fix anything over target,
and re-count after fixing.

## 3. Trope sweep

The catalogue below is the pattern library the counts don't cover, adapted from
[tropes.fyi](https://tropes.fyi) by ossama.is. The shared voice rules already ban
contrastive reframes, tricolons, bold-lead bullets, staccato fragments, formal
transitions and the LLM-register vocabulary — don't double-count those. These are
the additional patterns, and they matter in combination: one instance is usually
fine, three together is what gets a post called generated.

| Trope | What it looks like | What to do |
|---|---|---|
| The "serves as" dodge | "The station serves as / stands as / marks a pivotal…" | Use "is". The fancy copula is a repetition-penalty artefact |
| "Not X. Not Y. Just Z." | "Not a bug. Not a feature. A design flaw." | State the thing once |
| "The X? A Y." | "The result? Devastating." | Nobody asked. Say it as one sentence |
| Anaphora abuse | Three sentences opening "They assume that…" | Vary the openings or merge them |
| Superficial analysis | Trailing "-ing" clause: "…, highlighting its importance" | Cut the clause; it adds no fact |
| False ranges | "from innovation to implementation to culture" | Only use "from X to Y" on a real scale with a middle |
| Listicle in a trench coat | "The first wall… The second wall… The third wall…" | Either make it a real list or write real prose |
| "Here's the kicker" | "Here's the thing." / "Here's where it gets interesting." | Delete the buildup, keep the point |
| "Think of it as…" | "Think of it like a highway for data." | Drop the analogy; the reader is an engineer |
| "Imagine a world where…" | Futurist invitation followed by a wishlist | Describe what happened, not what you're picturing |
| False vulnerability | "And yes, I'm openly in love with the platform model" | Real vulnerability is specific and uncomfortable. Cut the polished kind |
| "The truth is simple" | "History is unambiguous on this point" | Prove it or drop it. Asserting clarity signals its absence |
| Stakes inflation | "will define the next era of computing" | Name the actual consequence, at its actual size |
| "Let's break this down" | "Let's unpack this." / "Let's dive in." | Delete. He's writing for peers, not students |
| Vague attributions | "Experts argue…", "Industry reports suggest…" | Name the person, the paper, the repo — or cut the claim |
| Invented concept labels | "the supervision paradox", "the acceleration trap" | Don't coin a term mid-post as if it were established |
| Em-dash addiction | 20+ em dashes doing dramatic pauses | The shared rule is no em dashes; a period and a new sentence |
| Unicode decoration | `→` arrows, curly quotes | Straight quotes, plain words. Real writers type on a keyboard |
| Fractal summaries | Every section previews and recaps itself | One post, one pass. Cut every "as we've seen" |
| Dead metaphor | The same metaphor eight times ("walls and doors") | One outing per metaphor, then move on |
| Historical analogy stacking | "Apple didn't build Uber. Facebook didn't build Spotify…" | Borrowed authority. Use your own evidence |
| One-point dilution | One thesis restated eight ways over 4,000 words | Cut to the strongest framing; the rest is padding |
| Content duplication | Paragraph 3 and paragraph 17 make the same point | Delete one, keep the better-placed one |
| Signposted conclusion | "In conclusion…", "To sum up…" | Land on the thesis. The reader can feel the ending |
| "Despite its challenges…" | Concede a problem, immediately dismiss it, end upbeat | Either the problem is real (give it room) or it isn't (cut it) |

**The mechanical pass.** Several of these are greppable, so grep them rather than
eyeballing. Plain `grep -nEi` (portable across macOS and Ubuntu), run against the
draft — the patterns match both straight and curly apostrophes:

```bash
POST=hugo/content/posts/<slug>.md
grep -nE  -e '—' -e '→' -e '“' -e '”' -e '‘' -e '’' "$POST"   # em dashes, arrows, curly quotes
grep -nEi -e "here.{1,3}s (the|what|where)" -e "let.{1,3}s (break|unpack|dive|explore)" "$POST"
grep -nEi -e "it.{1,3}s worth noting" -e '(importantly|interestingly|notably)' "$POST"
grep -nEi -e 'think of it (as|like)' -e 'imagine a (world|future)' -e 'in (conclusion|summary)' "$POST"
grep -nEi -e '(serves|stands) as' -e 'despite (these|its)' -e 'from [a-z]+ to [a-z]+ to [a-z]+' "$POST"
grep -nEi -e '(experts|observers|analysts|industry reports)' "$POST"     # vague attributions
grep -nEi -e ', (highlighting|underscoring|reflecting|showcasing|contributing to)' "$POST"
grep -cE  '^[[:space:]]*[-*] \*\*' "$POST"                              # bold-lead bullets
grep -c   '^## ' "$POST"                                                 # H2 count vs read time
```

List the curly quotes and arrows as one alternation rather than a `[…]` class —
a bracket class of multibyte characters false-positives on em dashes outside a
UTF-8 locale.

Report hits with line numbers. A hit is a candidate, not a conviction — read the
line before calling it.

## 4. Document-shape check (read the rendered post, not the sentences)

The tell lists above are sentence-level. The reviewing-code post (July 2026,
called slop on r/coding) passed all of them and still read generated, because the
tells were in the document's shape:

- Bold-lead bullet blocks — `**Correctness.** What happens with an empty input…`. A list
  earns its place only when the reader will use it as a list: scan it, run it in order,
  or check things off (commands, config options, a survival matrix). If every bullet is a
  full sentence and the block reads fine with the markers deleted, it's prose — write it
  as sentences. Bold lead-ins on bullets are the loudest single tell; it's how models
  format "key points".
- Header density — the review post ran five H2s in a 7-minute read, one every ~280 words.
  Rough ceiling: two or three H2s in a sub-10-minute post, and no header on a section
  under ~200 words. Instead of a header, merge the section or carry the turn with a plain
  transition sentence, the way an essay changes subject mid-flow.
- Section symmetry — uniform paragraph rhythm applied at section level: sections of
  near-equal length, each running setup/detail/close, each ending on a landing line.
  Each close can pass the section-ending punchline rule on its own; the symmetry is the
  tell. Vary section lengths, and let some sections end flat.
- Every post gets one deliberate rhythm break: at least one long, slightly untidy
  paragraph that chases the thought further than the structure strictly needs, and at
  least one paragraph of a line or three that states a fact and stops. A draft with
  neither was assembled, not written.

## 5. Editing passes (structure, evidence & polish)

Matt asks for tightening/condensing passes once a draft exists — this is where a
decent draft becomes publishable.

**Claims and evidence, especially "I built/tested it" posts:**
- If the thing has actually been run, write it past-tense and fold the results in. Don't
  keep a "here's the design, about to try it" framing while using what you already learned —
  it reads as pretending ignorance. A design write-up you've since used becomes "I designed
  this, applied it to my own work over the past few weeks, and it corrected me on N things."
- Prefer lived-use framing over lab framing. "I've been applying this to my own work over the
  past few weeks" reads like a principal engineer; "I ran a pilot / experiment / study on a real
  repo" reads like a paper. Keep the concrete numbers, drop the academic staging (pilot, replay,
  survival experiment) — attribute figures to "in practice", "on my repo", "running it back over
  40 commits", not to a formal study.
- Don't promise a follow-up you won't write. No manufactured "fuller writeup / part 2 coming
  separately" hooks — they age badly and read as bait; land the post on its own unless there is
  genuinely more coming.
- Treat "here's where my own reasoning was wrong" as headline material, not a buried caveat.
  The most confident claim in a draft is often the one a real test breaks; when it does, that
  inversion is the most interesting part of the post, so give it room where the claim lives.
- Number corrections against a promise: if the intro says the pilot "corrected me on three
  things", land them as correction one/two/three where each occurs — a through-line the
  reader follows, not a rule-of-three flourish.
- Attribute every number to what it actually measured. Don't let a stat borrow credibility
  for a claim it doesn't support (a gate-noise replay does not prove "patches stay cheap to
  review" — that's a separate, untested question; say so).
- Don't soften figures: "3 of the 5 warnings were true positives" beats "most were real" —
  state the fraction and own the false-positive rate. And swap hand-wavy performance imagery
  for the measured number when you have it ("5–37× less context", not "a thousand tokens
  versus a swamp") — the results-claim rule from Avoid, applied at edit time.
- Reconcile a figure everywhere it appears (a line count, a ratio) so mentions don't contradict.

**One post, one job** — as a general rule, not just for tutorials. The ast-grep post ran
taxonomy, a convention, a workflow loop, a CI gate and a retro in one 12-minute read,
and skimmers bounced at ~11s. Split sprawling drafts. The 4-minute skills-or-mcp
shape is also the practice vehicle: a short post forces an opening, one idea and a
landing with a fast feedback cycle, so keep them coming between the big posts.

**Openings, closings & when to explain:**
- Keep the cold open a claim, not a definition — let a concrete example teach the core term by
  demonstration (a spec pointing at a file that then gets refactored *is* "spec rot") rather
  than an "an X is a…" line that flattens the hook.
- Definition-on-demand: introduce a precise distinction only in the section where it turns
  load-bearing, not up front. Front-loading taxonomy for a technical reader condescends and
  costs the open.
- Don't end on an administrative pointer ("a follow-up is coming") — move it up and land the
  final line on the thesis, ideally bookending the opening stakes. The last line is what a
  reader, or an LLM, quotes.

**FAQs — only when the post uses the `{{< faq >}}` shortcode (GEO-heavy technical posts, not essays):**
- Questions must be the ones a reader still has *after* the body: objections and comparisons
  ("Isn't this just X?", "How's this different from Y?", "Does it scale?"), never restatements
  of what the post just said. A restatement FAQ is SEO-slop that adds nothing for a human even
  though it still feeds the FAQPage JSON-LD.
- Keep at most one clean definitional Q for LLM extraction; make the rest earn their place.
  Self-gloss any acronym inside the answer ("an ADR is a separate decision log…") so a
  newcomer follows without a lookup.

**Diagrams, tables & pictures:**
- Prefer mermaid. Diagrams go in a ```mermaid fenced block — the source stays diffable in the
  markdown, the theme handles light and dark, and there's nothing to redraw when the flow
  changes. ASCII / monospace is the fallback for the rare shape mermaid can't express (a
  fixed-width layout, a terminal transcript); a coloured SVG / D2 / screenshot needs dual-theme
  handling and reads as bolted-on — and don't add a build dependency for one picture.
- Keep the mermaid minimal: flowchart or sequenceDiagram for a workflow, no custom styling or
  colour directives, node labels short enough to read on a phone. A diagram that needs a legend
  is doing too much — split it or cut it.
- One visual per distinct load: value prop, workflow, decision logic. Two or three is plenty
  for a ~1500-word essay; more tips illustrated into decorated. Place each right after the
  sentence it crystallises, not in a separate diagram dump.
- A small table can beat prose for a contrast (a survival matrix of what-survives-which-edit,
  with one honest "breaks (by design)" cell carrying the limitation). When a diagram carries
  the branch logic, trim the prose that would restate it.

## 6. Sounds-human pass (after the counts are clean)

Read the draft back sentence by sentence and ask of each: would Matt say this to a
colleague across the desk, or write it in a blog he actually reads? A sentence can pass
every count above and still ring AI — too smooth, generically enthusiastic, or using a
word no engineer says out loud. Don't just delete the offending word; rewrite the
sentence the way he'd say it in conversation, using the real names of the tools and
techniques involved. If a sentence can't be said aloud without sounding like a press
release, it gets rewritten, not trimmed.

## 7. Pre-publish proof pass (mechanical, non-negotiable)

Loose voice is fine; loose mechanics aren't. The herdr post shipped with lowercase
"i" in published prose, "soo", and a broken link (`[CMUX] (url)` rendering
literally on the page). Before publish, check: capital I and apostrophes
throughout, spelling, every link renders and resolves, images have captions and alt
text. This pass never touches voice.

## 8. SEO & cross-linking hygiene

**Front matter:**
- `title` — specific, search-friendly, and short. Prefer "Building X: what it is" over a
  trailing clause ("Building lgtmaybe: a PR reviewer for any model", not "…a PR reviewer
  that runs on whatever model you've got"). Slugs come from the filename, so a title
  rename is safe after publishing.
- `description` — always present, ~120–155 chars. It feeds the meta description,
  OpenGraph, JSON-LD, and llms.txt, so make it count.
- `tags` — relevant, consistent.
- `date`, plus `lastmod` when the post is materially edited.
- `ogImage` — a per-post 1200×630 share card (see Publishing below). Beats the generic
  `og.png` for social/LLM click-through.

**Body:** descriptive link text (no "click here"), image alt text, links to related
posts, and slugs kept stable once published.

**Don't let a post be a dead end.** Views-per-user sat around 1.2 (almost nobody read a second post) because the posts that pulled the traffic had no internal links out: the local-models post drove ~70% of a quarter's traffic and didn't link to, or even mention, its sibling projects. The fix is two-directional:
- Every post ends with a related block (the `{{< related >}}` shortcode). Table stakes, not optional.
- Add inline links to your other posts where they already fit the sentence, never bolted on. local-models linked to lgtmaybe on its "good harness" line and to herdr on its "hardware I control" line, both phrases already in the prose, so the link rides along instead of interrupting. High-traffic posts matter most: that's where the readers are, so a dead end there costs the most.
- Pin the related block when auto-pick would miss a strong neighbour. `{{< related >}}` scores by shared tags, so a highly relevant post that shares only one tag gets edged out (lgtmaybe shares just "llms" with local-models). Pin the best two or three by slug: `{{< related "building-lgtmaybe" "herding-agents-with-herdr" >}}`.
- Never link a post that isn't live yet. A future-dated or draft target 404s, and a pinned related slug that isn't published drops with a build warning. Link a published alternative and swap the precise target in once it ships.

**Lead with the payoff on the first screen.** The ast-grep post pulled clicks but readers bounced at ~11s, because the opening ran three paragraphs of problem-framing and the thing that makes the idea click (the survive/break table and a worked example) sat 40 lines down. Show the core idea working inside the first screen, roughly the first 200 words: demonstrate the term on a concrete example right after the cold open, and move the most scannable artifact (a small table, a before/after) up near the top. Trim any downstream restatement so nothing is said twice. This is the "cold open a claim, teach by demonstration" rule measured against the bounce: if a skimmer can't see why the post is worth reading on the first screen, they leave.

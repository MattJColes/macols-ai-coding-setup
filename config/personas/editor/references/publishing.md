# Publishing coles.codes

Front matter, the Hugo build, share images and the publish checklist. Read it before the SEO pass (8) and whenever a post is going live.

## Publishing

**Where files go.** Posts live in `hugo/content/posts/`. Don't hard-wrap prose —
write each paragraph as one line and let the IDE's word wrap handle display; Matt
edits with soft wrap on. Leave code blocks, front matter, and image/link lines as
they are. Body starts headings at `##` — the title is the only H1.

**Measure one variable per post.** GA4 engagement time is the editor. When trying
something new (opening shape, shorter length, more code and less prose), change one
thing per post and read the number against comparable posts. The ast-grep bounce was
debugged this way; make it the habit, not a one-off.

**Cadence beats one-off brilliance for retention.** The single best result was a dated survey of a topic with ongoing search volume ("local models in mid-2026"). Write those as repeatable: a "local models, late 2026" follow-up compounds in search and gives returning readers a reason to come back, which a run of unrelated one-off posts never does.

**Where to post.** Comment threads are the payoff, so rank venues by comment quality,
not views. lobste.rs and HN quote lines back and argue mechanics; r/ExperiencedDevs fits
the judgement-led career and practice posts. r/coding delivered 7.7K views on the
reviewing-code post and exactly two comments — a pun and "slop". That's reach with no
feedback: use it only when raw reach is the goal for a broad-audience post, and check in
GA4 whether r/coding referrals actually engage. If they bounce like the ast-grep
skimmers, drop the venue.

**Mine the comment threads.** When a post does numbers on Reddit or HN, the thread
quotes back the sentences that landed. Those quoted lines are free line-level feedback
on what Matt's strongest writing looks like - collect them, and write more sentences
shaped like them.

**Handling slop accusations.** Two posts have now been called AI-written in threads
(Pydantic Evals on r/LocalLLaMA, reviewing-code on r/coding). The playbook:
- Don't reply to low-effort accusations. Defending your humanity to a one-word account
  makes the charge look load-bearing.
- Do reply to jokes and genuine technical pushback, in the same register. A byline that
  jokes back is the cheapest anti-slop signal there is.
- Either way, treat the accusation as structural feedback: run the document-shape
  checklist and the trope sweep against the post and record which tell was present
  (Pydantic Evals: section-ending zinger cadence; reviewing-code: bold-lead bullets and
  header density). If no listed tell matches, that's a new tell — add it to this file.

**Calibration references.** When judging whether a draft is at the standard, the
comparison set is: Dan Luu (evidence-dense long form), Julia Evans (teaching by
demonstration), Simon Willison (cadence, dated survey posts - the model for the "local
models, late 2026" follow-up strategy). For prose mechanics, Zinsser's On Writing Well
and Williams' Style: Lessons in Clarity and Grace - the latter is the rigorous version
of the Avoid list above.

### Share images (OG cards)

Every post gets its own 1200×630 Open Graph card in the "paper terminal" look:
warm-paper background, the post title in Source Serif 4, a `coles.codes $`
wordmark and a tag footer in IBM Plex Mono, terracotta accent rule and `$`. It's
the same palette and fonts as the site, so the cards read as one system.

Don't hand-build these. The repo has a generator that lays each card out in HTML
with the site's own self-hosted fonts and screenshots it in headless Chrome, so
the title auto-shrinks to fit any length. From the repo root:

```bash
python3 scripts/generate-og-images.py            # posts missing an ogImage
python3 scripts/generate-og-images.py --all      # every post
python3 scripts/generate-og-images.py <slug> …   # specific posts
```

It writes `hugo/static/posts/<slug>-og.png` and adds `ogImage: "posts/<slug>-og.png"`
to the front matter if it's missing, so a new post just needs a run after the
prose is settled. To retune the look (palette, layout, footer), edit the template
at the top of that script — keep the palette in step with
`hugo/assets/css/00-variables.css`. Needs Google Chrome (or `CHROME=/path`); no
pip dependencies. The site-wide `static/og.png` / `home-og.png` fallbacks are
separate; regenerate those by hand if the brand shifts.

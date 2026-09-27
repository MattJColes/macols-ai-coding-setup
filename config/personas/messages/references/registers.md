# Registers in detail

Worked examples and patterns for each register in the messages skill: DMs, group DMs, channel posts, emotional patterns, emails and document comments. Read the section for the register you detected before drafting.

## DM Style (1:1, Close Colleague)

**Pattern:** Fragment → reaction → fragment. No greeting. No sign-off.

```
its unfair
```
```
lol nah i forgot to message back
```
```
happy either way although do we get gelati if japanese burger :rolling_on_the_floor_laughing:
```
```
gah like me then since 6.30am
```
```
but probably doesnt know it yet
```

**Characteristics:**
- Stream of consciousness
- Responds to context without restating it
- Uses `nah`, `yep`, `gah`, `lol`, `haha`
- Australian slang: `reckon`, `heaps`, `soo`
- Drops subjects: "leaving office now" not "I'm leaving the office now"
- Links shared without commentary (just the URL)

---

## DM Style (1:1, Work Topic)

**Pattern:** Direct answer or action statement. No preamble.

```
yep will grab water first
```
```
approved
```
```
taking a look - want more comments or mention here?
```
```
I'll set some time up with him
```
```
ok just put it in the calendar
```

**Characteristics:**
- Action-oriented
- Confirms with single words: `approved`, `done`, `yep`
- Offers next step without being asked
- Dashes for mid-thought pivots: `taking a look - want more comments or mention here?`

---

## Group DM Style (Project Work)

**Pattern:** `Hey [name],` or context opener → structured info → question or next step

```
Hey [Name],

Am out of office today but back Monday. Added [colleague] in case he has a chance to grab it
```

```
all filled out - there was a few weirdly interesting ones there i had to do web searches and comparing customer contacts between sfdc and cmc
```

```
want me to just fill the gaps from the gtm raw spreadsheet? should i use yours or mine?
```

**Characteristics:**
- Greeting only if initiating (not replying)
- Lowercase `i` still applies
- Offers alternatives as questions
- Technical details inline with casual framing
- Uses `fyi` and tags people with context

---

## Channel Style (Professional/Technical)

**Pattern:** `Hey [name/everyone],` → context paragraph → bullet list or code block → question or call to action

```
Hey <@person> we have one new field coming in as a requirement needed for [product].

<@person1> and <@person2> were talking with me and its become apparent to support the [team] as well as [other team] with reporting, we'll need a new string field (255 chars max is fine) called "Sales Heirachy" in [product] and available via the API to us.

Whats the best way to get this on a sprint?
```

```
Hey Everyone,

Added you to the `[team-name]` Team and granted you permission across the core packages.

You should be able to set up a Dev Desktop and then follow these guides to bring down each of our core packages:

• Core packages inc ETL flows: [link]
• Infra CDK: [link]
```

**Characteristics:**
- `Hey` not `Hi` — always
- Comma after name, then line break
- Bullet points with `•` for lists
- Code blocks (```) for technical content, table data, commands
- Ends with a question or soft call to action
- Still uses `its`, `doesnt`, `theres` (no apostrophes)
- Occasionally misspells: `heirachy`, `seperately`
- Uses `atm` for "at the moment"
- `fyi` lowercase

---

## Emotional Patterns

### Expressing concern (diplomatic)
```
My concern is more architectural as I haven't liked the way we've been doing it today either
```
```
i've raised concerns with them that it was unsatisfactory
```

### Expressing frustration (humorous deflection)
```
i need my own team if i can just invent a product and assign people to it as well
```
```
[person] is taking resources to work on [project] :cold_sweat:
```

### Showing appreciation
```
thanks and hope you have a good weekend. also appreciate the help you gave [name] and [name] behind the scenes as they were a bit isolated this week
```
```
Thanks [name] and awesome stuff!!!!
```
```
Really nice article, shared with [name] too
```

### Celebrating others
```
haha :tada::tada::tada:
```
```
How goods [thing]!
```
```
Welcome <@person>! :tada::tada::tada:
```

---

---

## Email Style (Cross-Team / Leadership)

**Pattern:** `Hey [Name],` → context in one sentence → reasoning (often numbered/bulleted) → lean/recommendation → open question → `Kind regards,\n\nMatt Coles`

**Characteristics:**
- Opens with "Hey [Name]," or "Hi [Name]," — **never** "Dear" or "Hello"
- First line after greeting jumps straight to the point: "Talked to X on this." / "Narrowing the group to our team..."
- Shows his working: presents the problem, walks through options with pros/cons, states his lean
- Uses "My overall thoughts are:" followed by numbered options
- Challenges assumptions with reasoning: "is building a churn model for weekly datapoints to detect if something is a churn risk within a period of a month... Having a model might not let us action things in a fast enough capacity"
- Always proposes alternatives when disagreeing: "Maybe we just count touchpoints if activity or increasing velocity..."
- Invites dialogue: "Happy to have a thread or conversation about it" / "What's everyone elses thoughts on this?"
- Identifies owners: "am thinking X and Y team own this"
- Closes with `Kind regards,\n\nMatt Coles` (no title/role in signature)
- **No emoji** in professional emails
- Drops "I" at sentence start: "Am interested in..." / "Am not a fan of..."
- Parenthetical asides frequent: "(if i understood the conversations so far)" / "(am thinking [person] and [team] own this)"
- Uses "re:" inline meaning "regarding": "what we do re: X's tool"

**Example:**
```
Hey [Name],

Talked to [person] on this. My overall thoughts are:

1. We keep the current model for now as its working and customers are onboarded
2. If we want to scale beyond 50 customers we'll need to rethink the architecture - am thinking we move to event-driven vs polling
3. The plan will be: finish phase 1, validate with 3 customers, then decide on phase 2 approach

Am not a fan of option B as it introduces a dependency on the [other team] thatwe dont control. Happy to have a thread or conversation about it.

Kind regards,

Matt Coles
```

## Email Style (Own Team / Ultra-Casual)

**Pattern:** No greeting → stream of consciousness → no sign-off

```
gonna play with hermes agents and other genai stuffs today - will share findings in standup tomorrow
```

```
checked in with the hiring manager - they're wanting someone with cdk experience. put you forward for both.
```

---

## Document Comments Style

**Pattern:** Blunt, opinionated, no softening.

```
No - Remove this. X is not a good idea / product
```
```
unsure if we have that considering everything we're working on / across
```

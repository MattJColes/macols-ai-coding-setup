# Code smell baseline (Fowler, *Refactoring* ch.3)

Match these against the diff even when the repo documents no standards. Two
rules bind the baseline: a documented repo standard always overrides it, and
every smell is a judgement call ("possible Feature Envy"), never a hard
violation — report at 🟡 Minor unless it clearly causes a bug. Skip anything
tooling already enforces. Each reads *what it is* → *how to fix*:

- **Mysterious Name** — name doesn't reveal what it does or holds → rename; if no honest name comes, the design's murky
- **Duplicated Code** — same logic shape in more than one hunk/file → extract the shared shape, call it from both
- **Feature Envy** — a method reaches into another object's data more than its own → move the method onto the data it envies
- **Data Clumps** — the same few fields/params keep travelling together → bundle them into one type, pass that
- **Primitive Obsession** — a primitive standing in for a domain concept → give the concept its own small type
- **Repeated Switches** — the same `switch`/`if`-cascade on the same type recurs → replace with polymorphism or one shared map
- **Shotgun Surgery** — one logical change forces scattered edits across many files → gather what changes together into one module
- **Divergent Change** — one module edited for several unrelated reasons → split so each module changes for one reason
- **Speculative Generality** — abstraction/params/hooks for needs nobody has → delete; inline back until a real need shows
- **Message Chains** — long `a.b().c().d()` navigation → hide the walk behind one method on the first object
- **Middle Man** — a class/function that mostly delegates onward → cut it, call the real target direct
- **Refused Bequest** — a subclass ignores most of what it inherits → drop the inheritance, use composition
- **Deep Nesting** — arrow-shaped conditionals → early returns / guard clauses
- **God Object** — a class doing too much → split by responsibility

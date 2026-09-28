# Diff Walkthrough

A map to read before the diff, not a review. Use it on whatever just changed:
the working tree, a branch, or a PR, whichever agent or person wrote it.

## Get the change

- Working tree: `git status` and `git diff HEAD` (plus untracked files).
- Branch: `git diff <base>...HEAD` and `git log --oneline <base>..HEAD`.
- PR: `gh pr diff <n>` and `gh pr view <n>`.

Read the changed files in full where the hunks alone don't show what a
function now does. Don't run tests or fix anything; this is orientation.

## Output (in this order, under one screen where you can)

1. **What changed, by intent.** Group hunks by the reason they exist, not by
   file: "adds retry to the payment client", "renames the order status enum",
   "test fixtures for the above". One line per intent, then the files it
   touches. Call out anything that fits no intent; that's often the bug or
   the leftover.
2. **Call flow.** A Mermaid `sequenceDiagram` (or `flowchart` when there's no
   request/response shape) of the changed path only: entry point, the changed
   functions, what they call, and what calls them. Mark new or changed nodes
   `(new)` / `(changed)`. Skip the diagram for a change with no flow, such as
   config or docs only, and say so.
3. **Three riskiest spots.** `file:line`, what could go wrong, and why this
   spot: behaviour changes hidden in a refactor, error paths, concurrency,
   auth or data boundaries, migrations, deleted checks, anything without a
   test. Rank them. Fewer than three is fine; don't pad.
4. **Suggested reading order.** The files in the order that makes the diff
   make sense, usually the core change first, then callers, then tests.

Keep it plain prose and short lines. Don't restate the diff line by line and
don't praise it.

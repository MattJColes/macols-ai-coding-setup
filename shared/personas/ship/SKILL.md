---
name: ship
description: Run tests and linters, then commit the current change with a conventional message and push its branch.
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
user-invocable: true
---

# Commit Skill

1. Run all tests (pytest for backend, dart test for frontend)
2. Run linters (ruff check, dart analyze)
3. If the repo has `specs/anchors/*.yml` and ast-grep is installed, run the
   anchor hygiene check (`scripts/spec_drift_gate.sh --check` when the repo
   has it, else resolve each anchor with `ast-grep scan`). Fix dangling or
   loose rules before committing — re-pointing a rule belongs in the same
   commit as the rename that broke it. Advisory: if the tooling is missing,
   report that and carry on; never let this step block the commit.
4. If all pass, finalise the change:
   - Create a Conventional Commits message commit
     (`git add -p && git commit -m "<type>: <message>"`) on the current
     branch — if still on the default branch, create `<type>/<name>` first
     with `git checkout -b`.
   - Push with `git push -u origin <branch>` — unless the branch is part of a
     stacked PR chain (see step 5).
5. If the branch belongs to a stack (`gh stack view` names it, or the repo has
   a `.git/stack` entry for it):
   - Push and open/update every PR with `gh stack submit`, not `git push`. It
     sets each PR's base to the branch below.
   - If the base moved or a lower PR merged while you worked, run
     `gh stack sync` first — it cascade rebases the whole chain. Never rebase
     the branches above by hand.
   - Adding the next change in the chain: `gh stack add <type>/<name>` from the
     top of the stack rather than branching off the default branch.
6. Report the commit id, the PR (or the stack and each PR's position in it),
   and any warnings

---
name: workflow-commit-and-push
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
   - Push with `git push -u origin <branch>`.
5. Report the commit id and any warnings

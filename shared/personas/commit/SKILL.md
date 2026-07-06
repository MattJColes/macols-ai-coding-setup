---
name: commit
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
3. If all pass, finalise the change:
   - Create a Conventional Commits message commit
     (`git add -p && git commit -m "<type>: <message>"`) on the current
     branch — if still on the default branch, create `<type>/<name>` first
     with `git checkout -b`.
   - Push with `git push -u origin <branch>`.
4. Report the commit id and any warnings

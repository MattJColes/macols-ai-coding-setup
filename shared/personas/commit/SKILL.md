---
name: commit
description: Run tests and linters, then describe the current jj change with a conventional message and push its bookmark (git commit/push in non-colocated repos).
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
   - **Colocated jj repo** (a `.jj` directory exists — the default here):
     the working copy already IS the change, so there is nothing to stage.
     Set a Conventional Commits message with `jj describe -m "<message>"`,
     then `jj bookmark create <feat/fix/chore>/<name> -r @` (or
     `jj bookmark move <name> --to @` if the bookmark exists) and
     `jj git push --allow-new`.
   - **Non-colocated repo** (no `.jj` — e.g. CI checkouts): use git as
     normal — create a conventional commit and push to the current branch.
     Never run `git commit`/`git push` in a colocated repo.
4. Report the change/commit id and any warnings

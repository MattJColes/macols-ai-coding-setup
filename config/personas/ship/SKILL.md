---
name: ship
description: Use to commit and push a finished change - runs tests and linters, writes a conventional commit, pushes the branch and opens the PR. Owns the git branch, worktree, commit, push, PR and stacked-PR (gh stack) workflow.
tier: light
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
user-invocable: true
---

# Ship Skill

Plain git with GitHub as the remote: one branch per change, a git worktree per
parallel task, Conventional Commits, and a pull request rather than a push to
the default branch.

## Steps

1. Run the project's tests (e.g. `pytest`, `dart test`, `go test -race ./...`).
2. Run its linters (e.g. `ruff check`, `dart analyze`, `golangci-lint run`).
3. If the repo has `specs/anchors/*.yml` and ast-grep is installed, run the
   anchor hygiene check (`scripts/spec_drift_gate.sh --check` when the repo
   has it, else resolve each anchor with `ast-grep scan`). Fix dangling or
   loose rules before committing - re-pointing a rule belongs in the same
   commit as the rename that broke it. Advisory: if the tooling is missing,
   report that and carry on; never let this step block the commit.
4. If all pass, commit:
   - Still on the default branch? Branch first:
     `git checkout -b <type>/<name>` (`feat/`, `fix/`, `chore/`).
   - Stage deliberately (`git add -p`) and write a Conventional Commits
     message (see below). Small, focused commits.
   - Push with `git push -u origin <branch>` and open a PR (`gh pr create`) -
     unless the branch is part of a stack (step 5).
5. If the branch belongs to a stack (`gh stack view` names it, or the repo has
   a `.git/stack` entry for it):
   - Push and open/update every PR with `gh stack submit`, not `git push`. It
     sets each PR's base to the branch below.
   - If the base moved or a lower PR merged while you worked, run
     `gh stack sync` first - it cascade rebases the whole chain. Never rebase
     the branches above by hand; that is what breaks stacks.
   - Adding the next change in the chain: `gh stack add <type>/<name>` from the
     top of the stack rather than branching off the default branch.
6. Report the commit id, the PR (or the stack and each PR's position in it),
   and any warnings.

## Conventional Commits

`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`, with `feat!:` or a
`BREAKING CHANGE:` footer for breaking changes. They map onto semantic
versioning: `fix` is a patch, `feat` a minor, a breaking change a major.

## Worktrees for parallel work

Don't juggle branches in one checkout - give each concurrent task its own
worktree:

- `git worktree add ../<repo>-<task> -b <type>/<task>` creates a sibling
  checkout on a fresh branch.
- `git worktree list` shows them all; `git log --oneline --graph --all` shows
  every in-flight branch, yours and other agents'.
- After merge: `git worktree remove <path>`, then `git branch -d <branch>`.

## Stacked pull requests (gh stack)

Stack PRs when a chain of changes genuinely depends on each other and each is
worth reviewing on its own; independent changes belong on separate branches
off the default branch. Needs the extension:
`gh extension install github/gh-stack` (gh 2.0+).

- `gh stack init` on the default branch starts a stack; `gh stack add` puts
  the next change on top.
- `gh stack view` shows the chain and each PR's state; `gh stack up` /
  `down` / `checkout` move between branches.
- `gh stack merge` lands PRs bottom-up: a PR cannot land before the ones it
  depends on.
- `gh stack link` joins branches already pushed; `gh stack unstack` returns
  them to plain PRs.

## Recovery

Made a mess? `git reflog` finds the commit you were on before things went
wrong - reach for it before attempting manual repair.

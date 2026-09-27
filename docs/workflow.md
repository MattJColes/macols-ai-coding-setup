# Git, OpenSpec and Spec Anchors

[Back to README](../README.md)

The generated steering points agents at three workflows. The installers
provision the CLIs. Projects opt in to OpenSpec and spec anchors themselves.

## Git Worktrees

The generated instructions use plain git: one branch per change and small
Conventional Commits. The `ship` skill holds the full commit, push and PR
flow. Parallel agents get separate worktrees:

```bash
git worktree add ../repo-task -b feat/task
git log --oneline --graph --all     # see every worktree's branch together
```

In herdr, `Ctrl+b` `Shift+g` creates a worktree, and the wildcard layout opens
Claude Code beside yazi (see the
[herdr and yazi guide](../machine/GETTING_STARTED_HERDR_YAZI_WITH_CLAUDE.md)).

For a chain of related changes the `ship` skill reaches for GitHub's stacked
pull requests instead of one long branch: `gh stack init` / `add` / `submit`
to build and publish the chain, `gh stack sync` to cascade rebase when the
base moves, and `gh stack merge` bottom-up. The machine setup installs the
`github/gh-stack` extension alongside the GitHub CLI.

## OpenSpec

The installers add the [OpenSpec](https://github.com/Fission-AI/openspec) CLI
(`npm install -g @fission-ai/openspec`, Node >= 20.19). Run `openspec init` in
a project to create its `openspec/` directory and generate the slash commands
(`/opsx:explore`, `/opsx:propose`, `/opsx:apply`, `/opsx:archive`). The
instructions follow that workflow when the directory exists. The installers
never initialise projects for you.

This repo has opted in: living specs are in `openspec/specs/<capability>/spec.md`.

## Spec Anchors (ast-grep)

The installers also add [ast-grep](https://ast-grep.github.io) and yq.
ast-grep powers structural code search for the `audit` persona and spec
anchors for the `anchors` persona.

An anchor binds a living-spec section (marked `<!-- anchor: <id> -->` in
`openspec/specs/*/spec.md`) to the code that implements it, through an
ast-grep rule in `specs/anchors/*.yml`. A repo opts in by adding those rules;
the steering checks for them.

`scripts/spec_drift_gate.sh` checks the anchors:

```bash
./scripts/spec_drift_gate.sh --check             # hygiene: every rule matches exactly one site
./scripts/spec_drift_gate.sh --base origin/main  # advisory drift report against a base
```

`--check` fails on a dangling rule (no match) or a loose one (more than one
match). Drift mode warns when a change touches anchored code without touching
its spec section or rule, and always exits 0. When anchored behaviour changes,
update the matching spec section. When code moves without changing behaviour,
re-point the anchor. Rules for languages the installed ast-grep cannot parse
belong in `specs/anchors/quarantine/`.

This repo has opted in too. Its anchors cover persona rendering, steering
assembly, MCP registration, hook wiring, CLI provisioning, omp model
provisioning, the Claude Desktop bundle and the anchoring itself.

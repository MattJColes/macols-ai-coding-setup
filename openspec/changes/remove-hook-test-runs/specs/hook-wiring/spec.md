## ADDED Requirements

### Requirement: Hook batteries do not automatically execute tests
Turn-end and commit batteries SHALL retain lint, type, layer, duplication, file-length and synthesis checks without automatically running Python, Node, Flutter or Go tests. Tests SHALL run only when explicitly requested by a repository command or another repository-owned workflow. Legacy test-scope settings SHALL NOT enable automatic test execution.

#### Scenario: Code changes without configured test commands
- **WHEN** either battery runs in a trusted project with changed Python, Node, Flutter or Go code
- **THEN** no built-in test runner executes and applicable static checks still run

## MODIFIED Requirements

### Requirement: A local checkpoint runs before commits
Every tool's PreToolUse(Bash) wiring SHALL pass the command to
`hooks/pre_commit_check.sh`, which on `git commit` (not `--no-verify`, not
`MACOLS_CHECKPOINT=off`, trusted projects only) runs lint/type/layer checks,
synthesis, review and the project's explicit `CHECKPOINT` command from
`.macols/checks.conf`. A failure SHALL deny the commit with the findings as
the reason; a pass is remembered by tree fingerprint so an unchanged tree
is not re-checked. The turn-end battery SHALL run the project's `IMMEDIATE`
command. No tests SHALL run automatically in either battery.
<!-- anchor: hook-wiring.checkpoint -->

#### Scenario: The agent commits a failing change
- **WHEN** the agent runs `git commit` in a trusted repo whose CHECKPOINT command fails
- **THEN** the commit is denied and the command's findings reach the model

#### Scenario: A commit runs only the tests it reaches
- **WHEN** the agent runs `git commit` without an explicit test command in CHECKPOINT
- **THEN** the checkpoint runs its applicable validation checks without invoking tests, including when CHECKPOINT_TESTS=full was previously configured

### Requirement: Every battery run is logged per check
`run_post_task_checks` SHALL append one JSON line per check, plus a `total`
line, to `macols-checks.jsonl` in the repo's common git dir (shared by
worktrees): time, repo, loop (`turn` or `checkpoint`), check, duration in ms
and `pass`/`fail`. The log SHALL stay bounded (newest 5000 lines once it passes
10000), `MACOLS_CHECK_LOG=off` SHALL turn it off, and `bin/macols-check-stats`
SHALL summarise time, failure rate, repeated failures and historical escapes per check.
<!-- anchor: hook-wiring.check-log -->

#### Scenario: The user asks whether the hooks are worth their time
- **WHEN** the user runs `macols-check-stats` in a repo after some agent turns
- **THEN** it prints, per loop and check, runs, total and p95 time, failure rate and historical escaped tests

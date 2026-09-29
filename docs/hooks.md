# Hooks and Quality Gates

[Back to README](../README.md)

The scripts in `hooks/` turn quality rules into feedback the agent acts on.
The installers reference them in place (they are not copied), so edits here
take effect on the agent's next turn. `MACOLS_HOOKS_DIR` overrides the
location if you move them. Wiring for each tool lives in `lib/hooks.sh`.

| File | Role |
|---|---|
| `hooks/post_code_hook.sh` | After each edit |
| `hooks/post_task_hook.sh` | At the end of a turn |
| `hooks/pre_deploy_hook.sh` | Before `cdk deploy` / `cdk destroy` (Claude Code, Codex, ZCode, pi-yaml-hooks) |
| `hooks/pre_deploy_check.sh` | Shared deploy matcher every tool's wiring calls |
| `hooks/pre_commit_hook.sh` | Before `git commit`: the local checkpoint (Claude Code, Codex, ZCode, pi-yaml-hooks) |
| `hooks/pre_commit_check.sh` | Shared checkpoint core every tool's wiring calls |
| `hooks/checks/` | The check batteries (`post_code.sh`, `post_task.sh`), shared helpers (`common.sh`) and `ensure_node.sh` |
| `hooks/adapters/` | Output formats (`hook_output.sh`), the OpenCode plugin and the `pi-checks` extension for pi and omp |

## Feedback Loops

Each check runs at the cheapest loop that still catches the problem:

| Loop | What runs | When |
|---|---|---|
| Immediate | Per edit: format, lint and type check on the file. Per turn: related unit tests, types, layer rules, duplication, and the project's `IMMEDIATE` command | Every agent iteration |
| Local checkpoint | The whole test suite of each affected package, the same lint/type/layer checks, and the project's `CHECKPOINT` command (integration tests, an eval smoke set) | When the agent runs `git commit`; a failure blocks the commit |
| PR | Full tests, semgrep, dependency audits, jscpd threshold (the `quality` skill's CI workflow) | Before human review |
| Merge/nightly | The project's `NIGHTLY` command: E2E, broad model matrix, load tests, full eval suite | Scheduled CI job |
| Production | Traces, user failures, latency and cost, sampled quality evals | Continuously; see the `sre` skill |

Projects declare their own commands in `.macols/checks.conf` (template in
`config/personas/quality/references/checks.conf`). The hooks read it as data and
run the commands from the repo root in trusted projects only. The checkpoint
skips when the tree matches the last passing checkpoint, when the command
passes `--no-verify`, or with `MACOLS_CHECKPOINT=off`.

## What Runs

Every tool gets the findings in its own model-visible format
(`--format claude|codex|zcode|text`), not just a log line:

- post-code: after each edit, the file's formatter, linter and type check
  (ruff + pyright/mypy, eslint, dart analyze, gofmt, shellcheck) plus a
  file-length limit. Findings come back with the edit and never block it.
- post-task: at the end of a turn, tests related to the changed files, lint
  and strict types, golangci-lint, jscpd duplication, and layer rules
  (import-linter, dependency-cruiser) when the project configures them. Test
  selection: pytest-testmon when the project's venv has it (coverage-based),
  otherwise `test_<module>.py` by name; `vitest related` / `jest
  --findRelatedTests` by import graph; `go test ./...` in each changed module,
  where Go's test cache replays everything the change can't affect. When
  something fails, the agent gets one more step with the findings and a fix
  instruction. It only re-runs when the tree changed since its last run, so it
  can't loop and Q&A turns stay fast (under a second on small projects).
- pre-commit: the local checkpoint above, before `git commit` lands.
- pre-deploy: asks for confirmation before `cdk deploy` or `cdk destroy`.
  For a deploy in a trusted project it runs `cdk diff` first and puts what
  needs a human in the prompt: resources removed or replaced, and stacks with
  IAM or security-group changes. Statement counts and template noise stay
  out. If the diff can't run (no credentials, timeout, untrusted repo) the
  prompt says so. `cdk diff` and `cdk synth` pass untouched. Codex has no
  "ask", so it denies the first attempt and allows an identical retry after
  you confirm; the retry doesn't re-run the diff.

Semgrep and dependency audits (pip-audit, npm audit, govulncheck) run in CI,
not per turn. `MACOLS_SEMGREP=1` turns local semgrep back on.

Codex only runs hooks you have trusted, so approve them in Codex after
installing (and again after they change).

## pi-yaml-hooks (pi and omp)

The Pi installer also adds [pi-yaml-hooks](https://github.com/KristjanPikhof/pi-yaml-hooks)
to both agents, for your own YAML hooks in `~/.pi/agent/hook/hooks.yaml`,
`~/.omp/agent/hook/hooks.yaml` or a trusted project's `.pi/hook/hooks.yaml` /
`.omp/hook/hooks.yaml`. `/hooks-status` inside either agent shows what loaded.

The macols checks stay in the `pi-checks` extension and are not written into
any `hooks.yaml`, because pi-yaml-hooks can't carry them all:

- it only feeds the model the reason for a blocked tool call. Output from
  `tool.after.*` and `session.idle` hooks goes to its log, so post-edit and
  turn-end findings would never reach the agent.
- omp gives synchronous hooks a 20-second budget. The commit checkpoint can
  run for minutes, and a timed-out hook doesn't block, so the checkpoint
  would fail open.
- it has no interactive confirm with dynamic text, so the deploy prompt
  couldn't show the `cdk diff` summary.

The pre-tool hooks do understand its contract (`--format pi-yaml`: the
lowercase `bash` tool name, `tool_args.command`, and a block as exit 2 with the
reason on stderr), so a hook of your own can call them. Wiring one of them
while `pi-checks` is loaded runs that check twice. The deploy guard uses the
same deny-then-retry as Codex:

```yaml
hooks:
  - id: macols-pre-deploy
    event: tool.before.bash
    actions:
      - bash:
          command: "~/path/to/macols-ai-coding-setup/hooks/pre_deploy_hook.sh --format pi-yaml"
          timeout: 300000
```

## Is It Worth the Time?

Every turn-end and checkpoint run appends one JSON line per check to
`.git/macols-checks.jsonl` (shared by worktrees, capped at 10k lines):
duration, pass or fail, and which loop ran it. At the checkpoint, failing
Python tests that the name-based turn-end selection wouldn't have run are
recorded as escapes.

```bash
macols-check-stats             # per loop and check: runs, total/p95 time, fail %, fail streak, escapes
macols-check-stats --days 7
macols-check-stats --escapes   # which tests escaped the fast path
```

Read it as: a slow check that never fails belongs in CI, a long fail streak
means the agent is going round in circles, and escapes mean the fast path
needs pytest-testmon or better-named tests. `MACOLS_CHECK_LOG=off` stops the
logging.

## Trusted Projects

Tests, cdk synth, and tools the repo ships or configures in code (`.venv/bin`,
`node_modules/.bin`, `eslint.config.js`, `.dependency-cruiser.cjs`, mypy and
analyser plugins) run code the repository controls. The hooks only run them in
projects you have trusted, so opening a cloned repo or reviewing a PR doesn't
execute its tests just because the agent edited a file. Untrusted projects
still get ruff and pyright from your PATH, shellcheck, gofmt, jscpd and the
file-length limit, and the agent is told which checks were skipped.

```bash
bin/macols-trust              # trust the repo you're in
bin/macols-trust --list       # show trusted entries
bin/macols-trust --remove     # stop trusting the current repo
```

Entries live in `~/.config/macols/trusted-projects`, one path per line; a glob
such as `~/code/*` trusts everything under it. `MACOLS_TRUST_ALL=1` trusts every
project.

## Thresholds

The thresholds come from each project's own config. The `quality` persona
installs starter configs (ruff, ESLint, tsconfig, analysis_options,
golangci-lint, jscpd, import-linter, dependency-cruiser) and a matching CI
workflow. Existing layer breaks are approved explicitly: a
`.dependency-cruiser-known-violations.json` baseline (the hook passes
`--ignore-known` when it exists) or import-linter's `ignore_imports`.

## Environment Switches

| Variable | Effect |
|---|---|
| `MACOLS_PYTEST_SCOPE=changed\|full\|off` | Python test scope at turn end (default `changed`) |
| `MACOLS_TESTMON=off` | Ignore pytest-testmon and select Python tests by name |
| `MACOLS_GO_TEST_SCOPE=module\|changed` | Go tests at turn end: the whole changed module via the test cache (default) or only changed packages |
| `MACOLS_DEPLOY_DIFF=off` | Don't run `cdk diff` before a deploy prompt |
| `MACOLS_DEPLOY_DIFF_TIMEOUT` | Seconds the pre-deploy `cdk diff` may take (default 240) |
| `MACOLS_CHECK_LOG=off` | Don't log check timings |
| `MACOLS_DUPLICATION=off` | Skip the jscpd duplication check |
| `MACOLS_DUP_MIN_LINES` | Minimum clone size jscpd reports (default 10) |
| `MACOLS_MAX_FILE_LINES` | File-length limit (default 500, `0` to turn off) |
| `MACOLS_GO_RACE=1` | Run Go tests with the race detector |
| `MACOLS_SEMGREP=1` | Run semgrep locally |
| `MACOLS_CHECKS_VERBOSE=1` | Also print notes such as "pytest not installed" |
| `MACOLS_HOOKS_DIR` | Where the hook scripts live |

## Installing Only Hooks

```bash
./install.sh claudecode --hooks-only --no-cli
./install.sh pi --hooks-only --no-pi       # the pi-checks extension, both agents
./install.sh pi --packages-only            # pi-yaml-hooks and the other agent packages
```

`tests/test_scoped_pytest.sh` covers the pytest scoping. See
[Testing](testing.md).

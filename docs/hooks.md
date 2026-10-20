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
| Immediate | Per edit: format, lint and type check on the file. Per turn: types, layer rules, duplication, and the project's `IMMEDIATE` command | Every agent iteration |
| Local checkpoint | Lint/type/layer checks, synthesis, review, and the project's explicit `CHECKPOINT` command | When the agent runs `git commit`; a failure blocks the commit |
| PR | Full tests, semgrep, dependency audits, jscpd threshold (the `quality` skill's CI workflow) | Before human review |
| Merge/nightly | The project's `NIGHTLY` command: E2E, broad model matrix, load tests, full eval suite | Scheduled CI job |
| Production | Traces, user failures, latency and cost, sampled quality evals | Continuously; see the `sre` skill |

Projects declare their own commands in `.macols/checks.conf` (template in
`config/personas/quality/references/checks.conf`). The hooks read it as data and
run the commands from the repo root in trusted projects only. The
hooks never automatically run tests. Repos own test execution through their
own pre-commit/CI workflow or an explicit `CHECKPOINT` command. Legacy
`CHECKPOINT_TESTS` and test-scope environment settings do not enable automatic
tests. Existing `IMMEDIATE` or `CHECKPOINT` commands still run as configured.
The checkpoint skips when the tree matches the last passing checkpoint, when the command
passes `--no-verify`, or with `MACOLS_CHECKPOINT=off`.

## What Runs

Every tool gets the findings in its own model-visible format
(`--format claude|codex|zcode|text`), not just a log line:

- post-code: after each edit, the file's formatter, linter and type check
  (ruff + pyright/mypy, eslint, dart analyze, gofmt + go vet, shellcheck) plus
  a file-length limit. Findings come back with the edit and never block it.
  For Go that means a compile or type error in the edited package shows up
  with the edit, not at turn end; go vet builds the package, so it runs in
  trusted projects only.
- post-task: at the end of a turn, lint and strict types, golangci-lint,
  jscpd duplication, CDK synthesis, and layer rules (import-linter,
  dependency-cruiser) when the project configures them. Built-in Python,
  Node, Flutter and Go tests do not run. When
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

## Tools the Checks Need

The checks prefer a project's own copy of a tool (`.venv/bin`,
`node_modules/.bin`), because that one matches the project's config and
dependencies, and fall back to your PATH. Every installer's CLI step
(`ensure_quality_tools` in `lib/quality-tools.sh`) puts the fallbacks there,
so a project with no local copy, and every Go and Dart project, still gets
checked:

| Language | Tools | How |
|---|---|---|
| Python | ruff, pyright, mypy, pytest, import-linter (`lint-imports`), pylsp | `uv tool install`, after installing uv if needed |
| JS/TS | typescript (`tsc`), eslint, dependency-cruiser (`depcruise`), vitest, jest, typescript-language-server, prettier | `npm install -g` |
| Go | go, gofmt, go vet, golangci-lint, gopls | Homebrew; without it the go.dev tarball in `~/.local/share/go` and `go install` into `~/.local/bin` |
| Dart/Flutter | flutter, dart | Homebrew cask on macOS; on Linux a shallow clone of the stable channel in `~/.local/share/flutter` |
| Every language | shellcheck, jscpd | Homebrew or apt; npm |

pylsp, typescript-language-server, prettier and gopls are for the
[Fresh](https://github.com/sinelaw/fresh) terminal IDE the installers also add
(`brew install fresh-editor`, or upstream's installer into `~/.local` without
Homebrew): they are the servers Fresh starts for Python, JS/TS and Go, and
Dart's comes with Flutter. gopls also lets the gopls MCP server register.

Each install is skipped when the tool is already on PATH, and a failure only
skips that gate. Flutter is the heavy one (the SDK plus a Dart download on
first run). Pass `--no-cli` to skip the whole step.

## Is It Worth the Time?

Every turn-end and checkpoint run appends one JSON line per check to
`.git/macols-checks.jsonl` (shared by worktrees, capped at 10k lines):
duration, pass or fail, and which loop ran it. Historical test escapes remain readable in older logs.

```bash
macols-check-stats             # per loop and check: runs, total/p95 time, fail %, fail streak, escapes
macols-check-stats --days 7
macols-check-stats --escapes   # which tests escaped the fast path
```

A slow check that never fails is a candidate for CI. A long fail streak
means the agent is going round in circles. `MACOLS_CHECK_LOG=off` stops logging.

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
| `MACOLS_DEPLOY_DIFF=off` | Don't run `cdk diff` before a deploy prompt |
| `MACOLS_DEPLOY_DIFF_TIMEOUT` | Seconds the pre-deploy `cdk diff` may take (default 240) |
| `MACOLS_CHECK_LOG=off` | Don't log check timings |
| `MACOLS_DUPLICATION=off` | Skip the jscpd duplication check |
| `MACOLS_DUP_MIN_LINES` | Minimum clone size jscpd reports (default 10) |
| `MACOLS_MAX_FILE_LINES` | File-length limit (default 500, `0` to turn off) |
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

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
| `hooks/pre_deploy_hook.sh` | Before `cdk deploy` / `cdk destroy` (Claude Code, Codex) |
| `hooks/pre_deploy_check.sh` | Shared deploy matcher every tool's wiring calls |
| `hooks/checks/` | The check batteries (`post_code.sh`, `post_task.sh`), shared helpers (`common.sh`) and `ensure_node.sh` |
| `hooks/adapters/` | Output formats (`hook_output.sh`), the OpenCode plugin and the `pi-checks` extension for pi and omp |

## What Runs

Every tool gets the findings in its own model-visible format
(`--format claude|codex|zcode|text`), not just a log line:

- post-code: after each edit, the file's formatter, linter and type check
  (ruff + pyright/mypy, eslint, dart analyze, gofmt, shellcheck) plus a
  file-length limit. Findings come back with the edit and never block it.
- post-task: at the end of a turn, tests related to the changed files, lint
  and strict types, golangci-lint, jscpd duplication, and layer rules
  (import-linter, dependency-cruiser) when the project configures them. When
  something fails, the agent gets one more step with the findings and a fix
  instruction. It only re-runs when the tree changed since its last run, so it
  can't loop and Q&A turns stay fast (under a second on small projects).
- pre-deploy: asks for confirmation before `cdk deploy` or `cdk destroy`.
  `cdk diff` and `cdk synth` pass untouched. Codex has no "ask", so it denies
  the first attempt and allows an identical retry after you confirm.

Semgrep and dependency audits (pip-audit, npm audit, govulncheck) run in CI,
not per turn. `MACOLS_SEMGREP=1` turns local semgrep back on.

Codex only runs hooks you have trusted, so approve them in Codex after
installing (and again after they change).

## Thresholds

The thresholds come from each project's own config. The `quality` persona
installs starter configs (ruff, ESLint, tsconfig, analysis_options,
golangci-lint, jscpd, import-linter, dependency-cruiser) and a matching CI
workflow.

## Environment Switches

| Variable | Effect |
|---|---|
| `MACOLS_PYTEST_SCOPE=changed\|full\|off` | Python test scope at turn end (default `changed`) |
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
```

`tests/test_scoped_pytest.sh` covers the pytest scoping. See
[Testing](testing.md).

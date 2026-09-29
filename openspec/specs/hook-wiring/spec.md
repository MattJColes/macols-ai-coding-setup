# Hook Wiring

## Purpose

Quality/safety hooks under `hooks/` (post-code, post-task,
pre-deploy) are referenced **in place** — never copied — so their
relative sourcing of the shared check libraries keeps working. Each tool
wires them through its native mechanism, and every wiring SHALL deliver
findings to the MODEL, not just a log: the hooks take
`--format claude|codex|zcode|text` and `hooks/adapters/hook_output.sh` renders
the report in the shape that tool injects into context. Post-code findings
never block an edit; the turn-end battery asks for at most one more step.

## Requirements

### Requirement: Claude hooks and deny permissions land in settings.json
`write_claude_hooks <settings>` SHALL merge into existing settings, each
command with `--format claude`: a PreToolUse(Bash) pre-deploy guard
(`permissionDecision: ask`), a PostToolUse(Edit|Write|NotebookEdit) post-code
check (JSON `additionalContext`), and a Stop hook running the post-task
battery (`decision: block` with the findings as the reason, skipped when
`stop_hook_active`). It SHALL also deny reads of
`~/.aws/**` and `./.aws/**` and keep bypass-permissions mode available.
<!-- anchor: hook-wiring.claude -->

#### Scenario: Existing settings survive

- **WHEN** settings.json already has user keys
- **THEN** only `hooks` and the deny additions change; other keys survive

### Requirement: Codex hooks mirror Claude's, in Codex's own file shape
`write_codex_hooks <hooks_json>` SHALL write the same Pre/Post/Stop events as
Claude with `--format codex` and timeouts (300/120/600 seconds; the pre-deploy guard runs `cdk diff`). Codex has no
hook "ask" and fails open on unsupported decisions, so the pre-deploy guard
SHALL `deny` the first attempt with a confirm-with-the-user reason and let an
identical retry within 15 minutes through. The post-code hook SHALL read the
edited paths from the `*** Add/Update File:` headers of the `apply_patch`
text in `tool_input.command`. The installer SHALL tell the user to trust the
hooks in Codex, which runs no untrusted or modified hook.

Codex parses hooks.json with `deny_unknown_fields` and accepts only
`description` and `hooks` at the top level, so the event map SHALL be nested
under `hooks` rather than written flat like Claude's settings. The PostToolUse
matcher SHALL use `Edit|Write`, which Codex accepts as compatibility aliases
for its `apply_patch` tool.
<!-- anchor: hook-wiring.codex -->

#### Scenario: Codex hooks file

- **WHEN** `write_codex_hooks` runs
- **THEN** hooks.json has only `description` and `hooks` at the top level, `hooks` holds PreToolUse/PostToolUse/Stop entries, each hook has a timeout and `--format codex`, and Stop runs the post-task battery

#### Scenario: Codex loads the file without warnings

- **WHEN** Codex starts with the generated hooks.json
- **THEN** it does not report `failed to parse hooks config … unknown field`

### Requirement: ZCode hooks mirror Claude's, gated by hooks.enabled
`write_zcode_hooks <config_json>` SHALL write the same Pre/Post/Stop events
as Claude into `~/.zcode/cli/config.json` under `hooks.events`, with
`hooks.enabled: true` (config-file hooks never fire without it). Entries SHALL
be `type: "process"` hooks (`command: "bash"`, `args: [script, "--format",
"zcode"]`) with `timeoutMs` (300000/120000/600000); ZCode ignores other types
and second-based timeouts, and records plain stdout as a hook failure.
Existing keys elsewhere in the config (mcp, plugins, …) SHALL survive.
<!-- anchor: hook-wiring.zcode -->

#### Scenario: Existing config.json with plugin state

- **WHEN** `write_zcode_hooks` runs on a config that already has `plugins`
- **THEN** only the `hooks` key is replaced; the other keys survive

### Requirement: The OpenCode plugin is installed with substituted hook paths
`install_opencode_plugin <plugins_dir>` SHALL render
`hooks/adapters/opencode_plugin.mjs` into the plugins dir as a `.js`
file (OpenCode's plugin loader scans only `*.ts`/`*.js`) with the
`__HOOK_SCRIPT_PATH__`/`__TASK_HOOK_SCRIPT_PATH__`/
`__PRE_DEPLOY_CHECK_PATH__` placeholders replaced by the absolute shared-hook
paths, removing any previously installed copy first. The plugin runs the
post-code check on write tools (including `apply_patch`, passing the edited
paths) and appends findings to the tool output; handles the `session.idle`
bus event in its `event` handler, sending post-task findings back with
`client.session.prompt`; and gates cdk deploy/destroy commands via
`tool.execute.before` (first attempt blocks with the confirmation reason; an
identical retry — the user having confirmed — passes).
<!-- anchor: hook-wiring.opencode-plugin -->

#### Scenario: Plugin references shared hooks in place

- **WHEN** the plugin is installed
- **THEN** it shells out to the hooks under this repo's `hooks/`, not to copies

### Requirement: The Pi extension bakes in the hooks directory, in both agents
`install_pi_extension <extensions_dir> <pi|omp>` SHALL render
`hooks/adapters/pi-checks.ts` with `__PI_HOOKS_DIR__` replaced by the absolute
shared hooks dir and `__PI_FLAVOUR__` by the agent, wiring `tool_call` (bash)
to the cdk pre-deploy guard (`ctx.ui.confirm`; blocks on decline, and with a
confirm-first reason when headless), `tool_result` to the post-code check
(findings appended to the result content, never a steer), and the turn end
to the post-task battery as one continuation: `agent_before_settle` in pi,
`session_stop` in omp. The two Pi agents share no config directories, so
`installers/pi.sh` SHALL install the extension into both
`~/.pi/agent/extensions` and `~/.omp/agent/extensions`.
<!-- anchor: hook-wiring.pi-extension -->

#### Scenario: Extension installed

- **WHEN** `installers/pi.sh` completes
- **THEN** `pi-checks.ts` exists in both agent dirs and contains no `__PI_HOOKS_DIR__` or `__PI_FLAVOUR__` placeholder

### Requirement: pi-yaml-hooks is installed beside pi-checks, not instead of it
`installers/pi.sh` SHALL install the `pi-yaml-hooks` package for both `pi`
and `omp` so users can add their own YAML hooks, and SHALL NOT write the
macols hooks into any `hooks.yaml`: pi-yaml-hooks shows the model only a
block reason (never `tool.after.*` or `session.idle` output), and omp gives
synchronous hooks a 20-second budget, after which a hook fails open. The
`pi-checks` extension SHALL stay the only carrier of the macols hooks in both
agents. `pre_commit_hook.sh` and `pre_deploy_hook.sh` SHALL accept
`--format pi-yaml` (tool name `bash`, command in `tool_args.command`, a block
as the reason on stderr with exit 2; the deploy guard as Codex's
deny-then-retry), and `post_code_hook.sh` SHALL read edited paths from
`tool_args` and `files`, so a user's own YAML hook can call them.

#### Scenario: A commit fails the checkpoint under pi-yaml-hooks

- **WHEN** `pre_commit_hook.sh --format pi-yaml` receives a `tool.before.bash` payload for `git commit` and the checkpoint fails
- **THEN** it prints the findings on stderr and exits 2, which pi-yaml-hooks turns into the block reason

### Requirement: The pre-deploy matcher is single-sourced
The cdk deploy/destroy pattern and confirmation reason SHALL live only in
`hooks/pre_deploy_check.sh` (prints the reason on match, nothing
otherwise, always exit 0); `pre_deploy_hook.sh`, the OpenCode plugin and the
Pi extension SHALL all delegate to it rather than duplicating the regex.

#### Scenario: cdk diff passes everywhere

- **WHEN** any tool runs `cdk diff` or `cdk synth`
- **THEN** `pre_deploy_check.sh` prints nothing and no wiring gates the command

### Requirement: A deploy prompt carries what the diff changes
For a `cdk deploy` in a trusted project with a `cdk.json` (in the working
directory, or the `<dir>` of a leading `cd <dir> &&`), `pre_deploy_check.sh`
SHALL run `cdk diff` (passing `--profile` through, bounded by
`MACOLS_DEPLOY_DIFF_TIMEOUT`) and append to the reason each resource removed
or replaced and each stack with IAM or security-group changes, or a line
saying there are none. When the diff cannot run (untrusted project, no CLI,
error, timeout) the reason SHALL say so rather than imply a clean diff.
`cdk destroy` and `MACOLS_DEPLOY_DIFF=off` skip the diff. A confirm-by-retry
(Codex, OpenCode) SHALL NOT re-run the check.
<!-- anchor: hook-wiring.deploy-diff -->

#### Scenario: A rename forces a replacement

- **WHEN** the agent runs `cdk deploy` and `cdk diff` reports a resource with `(requires replacement)`
- **THEN** the confirmation reason lists `replace: <stack> <resource>` before the user approves

### Requirement: The turn-end battery runs once per change
`post_task_hook.sh` SHALL run the battery only when code changed AND the
working tree differs from the fingerprint recorded by its last run
(`.git/macols-last-check`), so question-and-answer turns after an edit, and a
stop after findings the agent did not act on, do not re-run it or loop.
<!-- anchor: hook-wiring.turn-end-gate -->

#### Scenario: Nothing changed since the last run

- **WHEN** the Stop hook fires twice with no edits in between
- **THEN** the second run prints nothing and exits 0

### Requirement: Every battery run is logged per check
`run_post_task_checks` SHALL append one JSON line per check, plus a `total`
line, to `macols-checks.jsonl` in the repo's common git dir (shared by
worktrees): time, repo, loop (`turn` or `checkpoint`), check, duration in ms
and `pass`/`fail`. At the checkpoint, a failing Python test that the
name-based turn-end selection would not have run SHALL be recorded under
`escaped`. The log SHALL stay bounded (newest 5000 lines once it passes
10000), `MACOLS_CHECK_LOG=off` SHALL turn it off, and `bin/macols-check-stats`
SHALL summarise time, failure rate, repeated failures and escapes per check.
<!-- anchor: hook-wiring.check-log -->

#### Scenario: The user asks whether the hooks are worth their time

- **WHEN** the user runs `macols-check-stats` in a repo after some agent turns
- **THEN** it prints, per loop and check, the runs, total and p95 time, failure rate and escaped tests

### Requirement: Repo code only runs in trusted projects
The hook batteries SHALL run checks that execute repository-controlled code
(tests, cdk synth, go checks, eslint, tsc, dependency-cruiser, import-linter,
mypy, dart analyze, and any tool resolved from `.venv/bin` or
`node_modules/.bin`) only when `project_trusted` accepts the project root,
from `~/.config/macols/trusted-projects` (paths or globs, managed by
`bin/macols-trust`) or `MACOLS_TRUST_ALL=1`. Untrusted projects SHALL still get
the read-only checks (ruff and pyright from PATH, shellcheck, gofmt, jscpd,
file length), and the skipped checks SHALL be named to the agent with the
trust instruction.
<!-- anchor: hook-wiring.project-trust -->

#### Scenario: A cloned repo ships a malicious test

- **WHEN** the agent edits a file in a repo that is not trusted
- **THEN** the turn-end hook does not run pytest, go test or any repo binary

### Requirement: A local checkpoint runs before commits
Every tool's PreToolUse(Bash) wiring SHALL pass the command to
`hooks/pre_commit_check.sh`, which on `git commit` (not `--no-verify`, not
`MACOLS_CHECKPOINT=off`, trusted projects only) runs the checkpoint battery:
the whole test suite of each affected package, the lint/type/layer checks and
the project's `CHECKPOINT` command from `.macols/checks.conf`. A failure SHALL
deny the commit with the findings as the reason; a pass is remembered by tree
fingerprint so an unchanged tree is not re-checked. The turn-end battery SHALL
run the project's `IMMEDIATE` command.
<!-- anchor: hook-wiring.checkpoint -->

#### Scenario: The agent commits a failing change

- **WHEN** the agent runs `git commit` in a trusted repo whose tests fail
- **THEN** the commit is denied and the failing tests are the reason the model reads

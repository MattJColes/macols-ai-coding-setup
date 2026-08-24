# Hook Wiring

## Purpose

Advisory quality/safety hooks under `shared/hooks/` (post-code, post-task,
pre-deploy) are referenced **in place** — never copied — so their
relative sourcing of the shared check libraries keeps working. Each tool
wires them through its native mechanism. Hooks are advisory: they report,
they never block.

## Requirements

### Requirement: Claude hooks and deny permissions land in settings.json
`write_claude_hooks <settings>` SHALL merge into existing settings: a
PreToolUse(Bash) pre-deploy guard, a PostToolUse(Edit|Write|NotebookEdit)
post-code check, and a Stop hook running the deterministic post-task
battery. It SHALL also deny reads of
`~/.aws/**` and `./.aws/**` and keep bypass-permissions mode available.
<!-- anchor: hook-wiring.claude -->

#### Scenario: Existing settings survive

- **WHEN** settings.json already has user keys
- **THEN** only `hooks` and the deny additions change; other keys survive

### Requirement: Codex hooks mirror Claude's, in Codex's own file shape
`write_codex_hooks <hooks_json>` SHALL write the same Pre/Post/Stop events as
Claude with timeouts (30/120/300 seconds): the PreToolUse(Bash) pre-deploy
guard, the PostToolUse post-code check, and a Stop hook running the
deterministic post-task battery.

Codex parses hooks.json with `deny_unknown_fields` and accepts only
`description` and `hooks` at the top level, so the event map SHALL be nested
under `hooks` rather than written flat like Claude's settings. The PostToolUse
matcher SHALL use `Edit|Write`, which Codex accepts as compatibility aliases
for its `apply_patch` tool.
<!-- anchor: hook-wiring.codex -->

#### Scenario: Codex hooks file

- **WHEN** `write_codex_hooks` runs
- **THEN** hooks.json has only `description` and `hooks` at the top level, `hooks` holds PreToolUse/PostToolUse/Stop entries, each hook has a timeout, and Stop runs the post-task battery

#### Scenario: Codex loads the file without warnings

- **WHEN** Codex starts with the generated hooks.json
- **THEN** it does not report `failed to parse hooks config … unknown field`

### Requirement: ZCode hooks mirror Claude's, gated by hooks.enabled
`write_zcode_hooks <config_json>` SHALL write the same Pre/Post/Stop events
as Claude into `~/.zcode/cli/config.json` under `hooks.events`, with
`hooks.enabled: true` (config-file hooks never fire without it) and
`type: "command"` timeouts in seconds (30/120/300). Existing keys elsewhere
in the config (mcp, plugins, …) SHALL survive.
<!-- anchor: hook-wiring.zcode -->

#### Scenario: Existing config.json with plugin state

- **WHEN** `write_zcode_hooks` runs on a config that already has `plugins`
- **THEN** only the `hooks` key is replaced; the other keys survive

### Requirement: The OpenCode plugin is installed with substituted hook paths
`install_opencode_plugin <plugins_dir>` SHALL render
`shared/hooks/opencode_post_code_plugin.mjs` into the plugins dir as a `.js`
file (OpenCode's plugin loader scans only `*.ts`/`*.js`) with the
`__HOOK_SCRIPT_PATH__`/`__TASK_HOOK_SCRIPT_PATH__`/
`__PRE_DEPLOY_CHECK_PATH__` placeholders replaced by the absolute shared-hook
paths, removing any previously installed copy first. The plugin runs the
post-code check on write tools, the post-task battery on `session.idle`,
and gates cdk deploy/destroy commands via
`tool.execute.before` (first attempt blocks with the confirmation reason; an
identical retry — the user having confirmed — passes).
<!-- anchor: hook-wiring.opencode-plugin -->

#### Scenario: Plugin references shared hooks in place

- **WHEN** the plugin is installed
- **THEN** it shells out to the hooks under this repo's `shared/hooks/`, not to copies

### Requirement: The Pi extension bakes in the hooks directory, in both agents
`install_pi_extension <extensions_dir>` SHALL render
`shared/hooks/pi-checks.ts` with `__PI_HOOKS_DIR__` replaced by the absolute
shared hooks dir, wiring `tool_call` (bash) to the cdk pre-deploy guard
(`ctx.ui.confirm`, blocking only on explicit decline; advisory warning when
headless), `tool_result` to the post-code check, and `agent_end` to the
post-task battery, surfaced via
`pi.sendMessage`. The two Pi agents share no config directories, so
`install_pi.sh` SHALL install the extension into both
`~/.pi/agent/extensions` and `~/.omp/agent/extensions`.
<!-- anchor: hook-wiring.pi-extension -->

#### Scenario: Extension installed

- **WHEN** `install_pi.sh` completes
- **THEN** `pi-checks.ts` exists in both agent dirs and contains no `__PI_HOOKS_DIR__` placeholder

### Requirement: The pre-deploy matcher is single-sourced
The cdk deploy/destroy pattern and confirmation reason SHALL live only in
`shared/hooks/pre_deploy_check.sh` (prints the reason on match, nothing
otherwise, always exit 0); `pre_deploy_hook.sh`, the OpenCode plugin and the
Pi extension SHALL all delegate to it rather than duplicating the regex.

#### Scenario: cdk diff passes everywhere

- **WHEN** any tool runs `cdk diff` or `cdk synth`
- **THEN** `pre_deploy_check.sh` prints nothing and no wiring gates the command

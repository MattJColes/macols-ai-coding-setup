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

### Requirement: Codex hooks mirror Claude's, with timeouts
`write_codex_hooks <hooks_json>` SHALL write the same Pre/Post/Stop events as
Claude with timeouts (30/120/300 seconds): the PreToolUse(Bash) pre-deploy
guard, the PostToolUse post-code check, and a Stop hook running the
deterministic post-task battery.
<!-- anchor: hook-wiring.codex -->

#### Scenario: Codex hooks file

- **WHEN** `write_codex_hooks` runs
- **THEN** hooks.json has PreToolUse/PostToolUse/Stop entries, each hook with a timeout, and Stop runs the post-task battery

### Requirement: The OpenCode plugin is installed with substituted hook paths
`install_opencode_plugin <plugins_dir>` SHALL render
`shared/hooks/opencode_post_code_plugin.mjs` into the plugins dir with the
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

### Requirement: The Pi extension bakes in the hooks directory
`install_pi_extension <extensions_dir>` SHALL render
`shared/hooks/pi-checks.ts` with `__PI_HOOKS_DIR__` replaced by the absolute
shared hooks dir, wiring `tool_call` (bash) to the cdk pre-deploy guard
(`ctx.ui.confirm`, blocking only on explicit decline; advisory warning when
headless), `tool_result` to the post-code check, and `agent_end` to the
post-task battery, surfaced via
`pi.sendMessage`.
<!-- anchor: hook-wiring.pi-extension -->

#### Scenario: Extension installed

- **WHEN** `install_pi.sh` completes
- **THEN** `extensions/pi-checks.ts` exists and contains no `__PI_HOOKS_DIR__` placeholder

### Requirement: The pre-deploy matcher is single-sourced
The cdk deploy/destroy pattern and confirmation reason SHALL live only in
`shared/hooks/pre_deploy_check.sh` (prints the reason on match, nothing
otherwise, always exit 0); `pre_deploy_hook.sh`, the OpenCode plugin and the
Pi extension SHALL all delegate to it rather than duplicating the regex.

#### Scenario: cdk diff passes everywhere

- **WHEN** any tool runs `cdk diff` or `cdk synth`
- **THEN** `pre_deploy_check.sh` prints nothing and no wiring gates the command

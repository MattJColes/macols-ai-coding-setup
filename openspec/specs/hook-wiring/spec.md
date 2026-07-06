# Hook Wiring

## Purpose

Advisory quality/safety hooks under `shared/hooks/` (post-code, post-task,
pre-deploy, lgtmaybe) are referenced **in place** — never copied — so their
relative sourcing of the shared check libraries keeps working. Each tool
wires them through its native mechanism. Hooks are advisory: they report,
they never block, and lgtmaybe in particular must never gate anything.

## Requirements

### Requirement: Claude hooks and deny permissions land in settings.json
`write_claude_hooks <settings>` SHALL merge into existing settings: a
PreToolUse(Bash) pre-deploy guard, a PostToolUse(Edit|Write|NotebookEdit)
post-code check, and a Stop sequence of the deterministic post-task battery
followed by the advisory lgtmaybe review. It SHALL also deny reads of
`~/.aws/**` and `./.aws/**` and keep bypass-permissions mode available.
<!-- anchor: hook-wiring.claude -->

#### Scenario: Existing settings survive

- **WHEN** settings.json already has user keys
- **THEN** only `hooks` and the deny additions change; other keys survive

### Requirement: Codex hooks carry timeouts and skip lgtmaybe
`write_codex_hooks <hooks_json>` SHALL write the same Pre/Post/Stop events
with timeouts (30/120/300 seconds) and SHALL NOT wire the lgtmaybe hook —
that review is Claude-only.
<!-- anchor: hook-wiring.codex -->

#### Scenario: Codex hooks file

- **WHEN** `write_codex_hooks` runs
- **THEN** hooks.json has PreToolUse/PostToolUse/Stop entries, each with a timeout, none referencing lgtmaybe

### Requirement: The OpenCode plugin is installed with substituted hook paths
`install_opencode_plugin <plugins_dir>` SHALL render
`shared/hooks/opencode_post_code_plugin.mjs` into the plugins dir with the
`__HOOK_SCRIPT_PATH__`/`__TASK_HOOK_SCRIPT_PATH__` placeholders replaced by
the absolute shared-hook paths, removing any previously installed copy first.
<!-- anchor: hook-wiring.opencode-plugin -->

#### Scenario: Plugin references shared hooks in place

- **WHEN** the plugin is installed
- **THEN** it shells out to the hooks under this repo's `shared/hooks/`, not to copies

### Requirement: The Pi extension bakes in the hooks directory
`install_pi_extension <extensions_dir>` SHALL render
`shared/hooks/pi-checks.ts` with `__PI_HOOKS_DIR__` replaced by the absolute
shared hooks dir, wiring `tool_result` to the post-code check and `agent_end`
to the post-task battery, advisory via `pi.sendMessage`.
<!-- anchor: hook-wiring.pi-extension -->

#### Scenario: Extension installed

- **WHEN** `install_pi.sh` completes
- **THEN** `extensions/pi-checks.ts` exists and contains no `__PI_HOOKS_DIR__` placeholder

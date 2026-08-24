# MCP Registration

## Purpose

`shared/mcp-config.json` is the single source of MCP servers (filesystem,
puppeteer, playwright, context7, dart, aws-mcp, aws-iac). Each tool registers
them through its native mechanism with `$HOME` expanded.

`shared/mcp-config-brave.json` is a second, opt-in source holding the
`brave-search` server. Only the OpenCode and Oh My Pi writers merge it, and only
when a Brave Search API key is on disk — Claude Code, Codex and ZCode keep the
shared list alone.

## Requirements

### Requirement: Claude servers are registered via the CLI, remove-then-add
`register_mcps_claude` SHALL register every server from the shared config at
user scope with `claude mcp add-json -s user`, removing any existing
registration of the same name first so re-runs update rather than duplicate.
String values SHALL have `$HOME` expanded before registration. A single
failed server SHALL NOT abort the remaining registrations.
<!-- anchor: mcp-registration.claude -->

#### Scenario: Re-running the installer

- **WHEN** `register_mcps_claude` runs on a machine that already has the servers
- **THEN** each server is removed and re-added once, and `claude mcp list` shows one entry per server

### Requirement: Codex servers flatten env and args to CLI flags
`register_mcps_codex` SHALL register each server with `codex mcp add`,
passing every `env` entry as an `--env KEY=VALUE` flag and the command/args
after `--`, with `$HOME` expanded in both.
<!-- anchor: mcp-registration.codex -->

#### Scenario: Server with environment variables

- **WHEN** a server entry carries an `env` map
- **THEN** each entry becomes an `--env` flag on the `codex mcp add` call

### Requirement: OpenCode servers are merged into opencode.json
`register_mcps_opencode` SHALL write the servers under the `mcp` key of
`~/.config/opencode/opencode.json` (type `local`, command array, `environment`
map, `enabled: true`), preserving all other keys in an existing config — a
standalone `mcp.json` is ignored by OpenCode and SHALL NOT be used. It SHALL
also merge the `brave-search` server from `shared/mcp-config-brave.json` on top
of the shared list when, and only when, a Brave Search API key is configured.
<!-- anchor: mcp-registration.opencode -->

#### Scenario: Existing opencode.json with user settings

- **WHEN** the file already contains user keys (theme, keybinds, …)
- **THEN** only the `mcp` key (and a default `$schema`) is written; other keys survive

#### Scenario: No Brave Search API key

- **WHEN** the key file is missing or empty
- **THEN** `brave-search` is absent from the written `mcp` key and the rest of the servers are registered as usual

### Requirement: Oh My Pi servers are merged into mcp.json
`register_mcps_pi` SHALL write the servers under the `mcpServers` key of
`~/.omp/agent/mcp.json` (Claude-style `command`/`args`/`env` entries with
`$HOME` expanded), preserving all other keys in an existing file — omp reads
MCP config from `mcp.json`, not from `config.yml`. It SHALL also merge the
`brave-search` server from `shared/mcp-config-brave.json` when, and only when, a
Brave Search API key is configured. Plain `pi` has no MCP support and therefore
gets no web search.
<!-- anchor: mcp-registration.pi -->

#### Scenario: Existing mcp.json with disabled servers

- **WHEN** the file already contains other keys (e.g. `disabledServers`)
- **THEN** only the `mcpServers` key is replaced; other keys survive

#### Scenario: No Brave Search API key

- **WHEN** the key file is missing or empty
- **THEN** `brave-search` is absent from the written `mcpServers` key and the rest of the servers are registered as usual

### Requirement: ZCode servers are merged into config.json under mcp.servers
`register_mcps_zcode` SHALL write the servers under the `mcp.servers` key of
`~/.zcode/cli/config.json` with `$HOME` expanded, using ZCode's strict
per-server schema (`type: "stdio"`, `command`, `args`, `env`, `enabled` — an
unknown key silently drops the whole server), preserving all other keys in an
existing config such as `hooks` and `plugins`.
<!-- anchor: mcp-registration.zcode -->

#### Scenario: Existing config.json with hooks and plugins

- **WHEN** the file already contains `hooks` and `plugins` keys
- **THEN** only `mcp.servers` gains entries; the other keys survive

### Requirement: The Brave Search API key is prompted for and stored outside config
`ensure_brave_api_key` SHALL obtain a Brave Search API key for the OpenCode and
Oh My Pi installers, in this order: an existing non-empty key file
(`~/.config/macols/brave-api-key`), then `$BRAVE_API_KEY` from the environment,
then an interactive prompt when stdin is a tty. A blank answer or a
non-interactive install SHALL be non-fatal and leave `brave-search` unregistered.
The key SHALL be written only to the key file with mode 600, never echoed and
never written into a tool's MCP config — the config references it through
`BRAVE_API_KEY_FILE`.
<!-- anchor: mcp-registration.brave-key -->

#### Scenario: Re-running the installer after the key is set

- **WHEN** `ensure_brave_api_key` runs with a non-empty key file present
- **THEN** it reports the key as already configured and does not prompt again

#### Scenario: Non-interactive install with no key

- **WHEN** the installer runs with stdin not a tty and `$BRAVE_API_KEY` unset
- **THEN** it warns, returns non-zero, and the install continues without `brave-search`

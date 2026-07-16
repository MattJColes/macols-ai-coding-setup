# MCP Registration

## Purpose

`shared/mcp-config.json` is the single source of MCP servers (filesystem,
puppeteer, playwright, context7, dart, aws-mcp, aws-iac). Each tool registers
them through its native mechanism with `$HOME` expanded; Oh My Pi gets no MCP
by design.

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
standalone `mcp.json` is ignored by OpenCode and SHALL NOT be used.
<!-- anchor: mcp-registration.opencode -->

#### Scenario: Existing opencode.json with user settings

- **WHEN** the file already contains user keys (theme, keybinds, …)
- **THEN** only the `mcp` key (and a default `$schema`) is written; other keys survive

### Requirement: Oh My Pi gets no MCP servers

The Pi installer SHALL NOT register MCP servers — omp has no MCP support by
design and its checks run through the pi-checks extension instead.

#### Scenario: Pi install

- **WHEN** `install_pi.sh` completes
- **THEN** no MCP registration has been attempted for omp

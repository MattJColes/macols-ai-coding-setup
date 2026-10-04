# MCP Registration

## Purpose

`config/mcp/servers.json` is the default source of MCP servers (playwright,
context7, dart, gopls), with pinned package versions. A server with a
`requires` key (dart, gopls) is registered only when that binary is on PATH.

Three opt-in sources sit beside it. `config/mcp/aws.json` holds
`aws-mcp` and `aws-iac`, registered for every tool only when the user opts in.
`config/mcp/youtrack.json` holds `youtrack`, registered for every tool once a
YouTrack URL and permanent token are stored.
`config/mcp/brave.json` holds `brave-search`, merged only by the
OpenCode and Pi-agent writers and only when a Brave Search API key is on disk.

Every writer takes its list from `mcp_resolve`, so all five tools see the
same servers, and each writer removes the stale entries this repo owns while
leaving the user's own servers alone.

## Requirements

### Requirement: One resolver decides the server list and the stale names
`mcp_resolve <tool>` SHALL return the servers to register (defaults, plus AWS
when opted in, plus `youtrack` when a URL and token are stored, plus
`brave-search` for opencode/pi when a key is configured),
with `$HOME` expanded and the `requires` key dropped, leaving out any server
whose `requires` binary is not on PATH. It SHALL also return the stale names:
owned servers left out above, which are removed outright, and the retired
`filesystem` and `puppeteer` servers, which are removed only while the entry
still runs the `@modelcontextprotocol/server-*` package this repo installed.
A source entry with a `marker` key SHALL be removed only while it still
contains that string (`youtrack`: its key file), and the key SHALL NOT reach a
tool's config.
<!-- anchor: mcp-registration.resolve -->

#### Scenario: gopls is not installed

- **WHEN** `gopls` is not on PATH
- **THEN** `gopls` is not registered, and an earlier registration of it is removed

#### Scenario: A user's own server shares a retired name

- **WHEN** a `puppeteer` entry runs a package other than `@modelcontextprotocol/server-puppeteer`
- **THEN** it survives the re-run

#### Scenario: A user's own youtrack server with no stored token

- **WHEN** no YouTrack URL and token are stored and a `youtrack` entry does not reference `~/.config/macols/youtrack-api-key`
- **THEN** it survives the re-run

### Requirement: The AWS servers are opt-in and the choice is remembered
`ensure_aws_mcp_choice` SHALL take the choice from `MACOLS_AWS_MCP` (set by
the `--aws-mcp` / `--no-aws-mcp` installer flags), then from
`~/.config/macols/aws-mcp`, then from a y/N prompt when stdin is a tty, and
SHALL record an explicit or prompted answer there so later installers do not
ask again. A non-interactive install with nothing set SHALL default to off.
Opting in SHALL make sure `uvx` is available.
<!-- anchor: mcp-registration.aws-choice -->

#### Scenario: Unattended install

- **WHEN** an installer runs with stdin not a tty, no flag and no remembered choice
- **THEN** `aws-mcp` and `aws-iac` are not registered and nothing is recorded

### Requirement: Claude servers are registered via the CLI, remove-then-add
`register_mcps_claude` SHALL register every resolved server at user scope with
`claude mcp add-json -s user`, removing any existing registration of the same
name first so re-runs update rather than duplicate, and SHALL then remove the
stale names. A single failed server SHALL NOT abort the remaining
registrations.
<!-- anchor: mcp-registration.claude -->

#### Scenario: Re-running the installer

- **WHEN** `register_mcps_claude` runs on a machine that already has the servers
- **THEN** each server is removed and re-added once, and `claude mcp list` shows one entry per server

### Requirement: Codex servers flatten env and args to CLI flags
`register_mcps_codex` SHALL register each resolved server with
`codex mcp add`, passing every `env` entry as an `--env KEY=VALUE` flag and the
command/args after `--`, and SHALL then remove the stale names.
<!-- anchor: mcp-registration.codex -->

#### Scenario: Server with environment variables

- **WHEN** a server entry carries an `env` map
- **THEN** each entry becomes an `--env` flag on the `codex mcp add` call

### Requirement: JSON configs are merged, never clobbered
`mcp_merge_json` SHALL merge the resolved servers into a user-owned JSON
config in the tool's shape: write the resolved entries, delete the stale
ones, and keep every other server and key. A file that does not parse SHALL be
left untouched and the call SHALL fail.
<!-- anchor: mcp-registration.merge -->

#### Scenario: Running twice

- **WHEN** a JSON writer runs twice against the same config
- **THEN** each server appears once and the user's own servers and keys survive

### Requirement: OpenCode servers are merged into opencode.json
`register_mcps_opencode` SHALL merge the servers under the `mcp` key of
`~/.config/opencode/opencode.json` (type `local`, command array, `environment`
map, `enabled: true`) and set a default `$schema`. A standalone `mcp.json` is
ignored by OpenCode and SHALL NOT be used.
<!-- anchor: mcp-registration.opencode -->

#### Scenario: No Brave Search API key

- **WHEN** the key file is missing or empty
- **THEN** `brave-search` is absent from the `mcp` key and the rest of the servers are registered as usual

### Requirement: Pi-agent servers are merged into mcp.json and mcp-adapter.json
`register_mcps_pi <config_json>` SHALL merge the servers under the
`mcpServers` key of the given file (Claude-style `command`/`args`/`env`),
keeping other keys. `installers/pi.sh` SHALL call it for
`~/.omp/agent/mcp.json` (omp reads MCP config natively from `mcp.json`, not
from `config.yml`) and for `~/.pi/agent/mcp-adapter.json`, which plain `pi`
reads through the `pi-mcp-adapter` package the installer adds. The adapter
never reads `~/.pi/agent/mcp.json`, so that file SHALL NOT be the plain-pi
target. Both files SHALL receive the same server list.
<!-- anchor: mcp-registration.pi -->

#### Scenario: Existing mcp.json with disabled servers

- **WHEN** the file already contains other keys (e.g. `disabledServers`)
- **THEN** those keys survive and only owned entries under `mcpServers` change

#### Scenario: Existing adapter settings

- **WHEN** `~/.pi/agent/mcp-adapter.json` already holds adapter `settings` and a server of the user's own
- **THEN** both survive a re-run, and the owned servers match those in `~/.omp/agent/mcp.json`

### Requirement: ZCode servers are merged into config.json under mcp.servers
`register_mcps_zcode` SHALL merge the servers under the `mcp.servers` key of
`~/.zcode/cli/config.json` using ZCode's strict per-server schema
(`type: "stdio"`, `command`, `args`, `env`, `enabled` - an unknown key silently
drops the whole server), keeping `hooks`, `plugins` and other keys.
<!-- anchor: mcp-registration.zcode -->

#### Scenario: Existing config.json with hooks and plugins

- **WHEN** the file already contains `hooks` and `plugins` keys
- **THEN** only owned entries under `mcp.servers` change; the other keys survive

### Requirement: The Brave Search API key is prompted for and stored outside config
`ensure_brave_api_key` SHALL obtain a Brave Search API key for the OpenCode and
Pi installers, in this order: an existing non-empty key file
(`~/.config/macols/brave-api-key`), then `$BRAVE_API_KEY` from the environment,
then an interactive prompt when stdin is a tty. A blank answer or a
non-interactive install SHALL be non-fatal and leave `brave-search` unregistered.
The key SHALL be written only to the key file with mode 600, never echoed and
never written into a tool's MCP config - the config references it through
`BRAVE_API_KEY_FILE`.
<!-- anchor: mcp-registration.brave-key -->

#### Scenario: Re-running the installer after the key is set

- **WHEN** `ensure_brave_api_key` runs with a non-empty key file present
- **THEN** it reports the key as already configured and does not prompt again

#### Scenario: Non-interactive install with no key

- **WHEN** the installer runs with stdin not a tty and `$BRAVE_API_KEY` unset
- **THEN** it warns, returns non-zero, and the install continues without `brave-search`

### Requirement: The YouTrack URL and token are prompted for and stored outside config
`ensure_youtrack_mcp` SHALL obtain the YouTrack site URL and a permanent token
for every installer's MCP step, in this order: `$YOUTRACK_URL` /
`$YOUTRACK_TOKEN` from the environment (either one replaces the stored value),
then the stored files, then an interactive prompt when stdin is a tty. The URL
SHALL be stored in `~/.config/macols/youtrack-url` without a trailing `/` or
`/mcp`, defaulting to `https://`. The token SHALL be written only to
`~/.config/macols/youtrack-api-key` with mode 600, as the
`Authorization: Bearer <token>` header file `mcp-remote` reads through
`--header-file`, never echoed and never written into a tool's MCP config or
argv. A blank answer SHALL record `off` in `~/.config/macols/youtrack-mcp` so
later installers do not prompt again; setting the environment variables SHALL
clear it. A skip or a non-interactive install with nothing set SHALL be
non-fatal and leave `youtrack` unregistered.
<!-- anchor: mcp-registration.youtrack -->

#### Scenario: Skipping the prompt

- **WHEN** the user leaves the URL or token blank
- **THEN** `youtrack` is not registered, `off` is recorded, and the next installer in the same run does not prompt

#### Scenario: Re-running the installer after the URL and token are set

- **WHEN** `ensure_youtrack_mcp` runs with both files present and neither variable set
- **THEN** it reports YouTrack as already configured and does not prompt again

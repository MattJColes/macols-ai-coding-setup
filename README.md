# macols-ai-coding-setup

One source of personas, steering, MCP servers and quality hooks, rendered into
the formats used by Claude Code, Codex, OpenCode, the Pi agents (plain `pi` and
Oh My Pi) and ZCode. You edit `config/` or `hooks/` once and `./install.sh`
writes each tool's agents, skills, system instructions, MCP registrations and
hook wiring. The generated instructions use plain git branches and worktrees,
add [ponytail](https://github.com/DietrichGebert/ponytail) for minimal-code
rules and provision the [OpenSpec](https://github.com/Fission-AI/openspec) and
ast-grep CLIs for repos that use specs. An optional workstation setup for macOS
and Ubuntu 24/26 installs the runtimes, containers and terminal tools around
them.

## Quick Start

```bash
git clone https://github.com/MattJColes/macols-ai-coding-setup.git
cd macols-ai-coding-setup

./install.sh                          # all five tools
./install.sh codex                    # one tool
./install.sh claudecode pi            # several tools
./install.sh codex --skills-only --no-cli   # one component, keep the existing CLI
./install.sh codex --help             # a tool's full option list
./install.sh --machine                # workstation setup first, then the tools
```

Tool names are `claudecode`, `codex`, `opencode`, `pi` (installs both `pi` and
`omp`) and `zcode` (configs only; the app is a desktop install). Every other
option passes through to each selected tool's installer. See
[Installing](docs/installing.md) for component flags, project-local installs
and where each file lands.

> [!CAUTION]
> The installers delete and rebuild generated agents and skills directories.
> Move or commit any hand-written files there first. User-owned settings files
> are merged.

## Layout

| Path | Holds | Edit it when |
|---|---|---|
| `install.sh` | The only entry point | Adding a tool or a global option |
| `config/personas/<name>/` | `SKILL.md` plus `references/` and `scripts/` for each persona | Adding or changing an agent or skill |
| `config/steering/` | `base.md`, `response-format.md`, `ponytail.AGENTS.md`, `tools/<tool>.json` | Changing the system instructions every agent reads |
| `config/mcp/` | `servers.json`, `brave.json`, `aws.json`, `youtrack.json` | Adding, removing or bumping an MCP server |
| `hooks/` | Post-code, post-task and pre-deploy hooks, `checks/` and `adapters/` | Changing what runs inside the agents |
| `installers/` | One installer per tool | Changing how one tool is installed or wired |
| `lib/` | `common.sh` loader plus `os.sh`, `personas.sh`, `steering.sh`, `mcp.sh`, `omp-models.sh`, `hooks.sh` | Changing rendering or install logic shared by every tool |
| `machine/` | macOS and Ubuntu workstation setup | Changing the runtimes, terminal or editor setup |
| `dist/` | Committed Claude Desktop persona bundle | Never by hand; regenerate it |
| `bin/` | `claude-launch.sh` for `--dangerously-skip-permissions` | Rarely |
| `openspec/`, `specs/anchors/` | Living specs and the ast-grep rules anchored to them | Anchored behaviour changes |
| `scripts/`, `tests/` | Bundle packager, spec drift gate, install verifier and self-tests | Adding a check |

Never edit the generated files under `~/.claude`, `~/.codex`,
`~/.config/opencode`, `~/.pi`, `~/.omp` or `~/.zcode`. Change the source here
and rerun the installer.

## Making a Change

1. Edit the source: a persona in `config/personas/`, steering in
   `config/steering/`, a server in `config/mcp/` or a check in `hooks/`.
2. Rerun the installer for the tools you use:

   ```bash
   ./install.sh claudecode --no-cli
   ```

3. After changing a persona or `response-format.md`, rebuild the Claude Desktop
   bundle and commit it with the change:

   ```bash
   ./scripts/package_claude_desktop_personas.sh
   ```

4. Run the checks that match what you touched:

   ```bash
   bash -n install.sh installers/*.sh lib/*.sh
   ./scripts/package_claude_desktop_personas.sh --check
   ./scripts/spec_drift_gate.sh --check
   ./tests/verify_install.sh claudecode
   ```

[AGENTS.md](AGENTS.md) maps each kind of change to the file that owns it and
the check that proves it.

## Documentation

- [Installing](docs/installing.md): per-tool options, project-local config,
  what gets installed where, running with `--dangerously-skip-permissions`,
  post-install steps and troubleshooting.
- [Personas and steering](docs/personas.md): persona frontmatter, tiers,
  `references/`, the persona set, the Claude Desktop bundle, ponytail and the
  response format.
- [MCP servers](docs/mcp.md): the default servers, Brave Search and the opt-in
  AWS servers.
- [Models](docs/models.md): model providers and roles for pi and Oh My Pi.
- [Hooks](docs/hooks.md): the post-code, post-task and pre-deploy hooks,
  quality gates and environment switches.
- [Workflow](docs/workflow.md): git worktrees, stacked PRs, OpenSpec and
  ast-grep spec anchors.
- [Testing](docs/testing.md): the install verifier, self-tests and CI.
- [Machine setup](machine/README.md): everything the workstation setup installs.

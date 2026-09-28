# Installing

[Back to README](../README.md)

`./install.sh` is the only entry point. It takes tool names (`claudecode`,
`codex`, `opencode`, `pi`, `zcode`) and passes every other option through to
`installers/<tool>.sh`. With no tool names it installs all five.

By default each installer installs the missing CLI and updates configuration
in your home directory. If you already have the CLI, add `--no-cli`. The Pi
installer uses `--no-pi` instead (it covers both the `pi` and `omp` binaries).
ZCode is a desktop app, so its installer writes configs and warns when the app
itself is missing.

The tool installers run on macOS and Linux. The optional workstation setup
targets macOS and Ubuntu 24.04/26.04.

## Choose What to Install

| Goal | Command |
|---|---|
| Install and configure everything | `./install.sh` |
| Install one tool and all its configuration | `./install.sh codex` |
| Install several tools | `./install.sh claudecode opencode` |
| Keep an existing CLI and install all its configuration | `./install.sh codex --no-cli` |
| Install only selected configuration | `./install.sh codex --skills-only --no-cli` |
| Preview the personas available to a tool | `./install.sh codex --list` |
| Show a tool's options | `./install.sh codex --help` |
| Install configuration into one project | `<setup repo>/install.sh <tool> --project`, run from that project |
| Build the full workstation as well | `./install.sh --machine` (alias `--env`) |

With no component flags, an installer installs everything for that tool. The
first `--*-only` flag clears the default set. Add more `--*-only` flags to
install those components together.

```bash
# Codex skills only. Keep the existing Codex CLI.
./install.sh codex --skills-only --no-cli

# Claude Code MCPs and hooks only. Keep the existing Claude CLI.
./install.sh claudecode --mcps-only --hooks-only --no-cli

# Codex skills plus the system AGENTS.md
./install.sh codex --skills-only --instructions-only --no-cli
```

A component is the smallest selection unit, so `--skills-only` installs every
applicable skill shown by `--list`. When you name several tools, the same
options go to each of them.

## Per-Tool Options

| Tool | Selectable components | Skip CLI install | Other choices |
|---|---|---|---|
| `claudecode` | `--agents-only`, `--skills-only`, `--mcps-only`, `--hooks-only` | `--no-cli` | `--project`, `--list` |
| `codex` | `--skills-only`, `--agents-only`, `--instructions-only`, `--mcps-only`, `--hooks-only` | `--no-cli` | `--project`, `--list` |
| `opencode` | `--agents-only`, `--skills-only`, `--mcps-only`, `--hooks-only` | `--no-cli` | `--project`, `--list` |
| `pi` | `--skills-only`, `--context-only`, `--hooks-only`, `--packages-only`, `--mcps-only`, `--models-only` | `--no-pi` | `--no-packages`, `--no-models`, `--project`, `--list` |
| `zcode` | `--skills-only`, `--commands-only`, `--instructions-only`, `--mcps-only`, `--hooks-only` | `--no-cli` (skips the app check) | `--project`, `--list` |

`--no-cli` and `--no-pi` skip the binary install or upgrade. They don't remove
anything. MCP registration still needs the tool's CLI on your `PATH`. Every
installer, and `install.sh` itself, also takes `--aws-mcp` / `--no-aws-mcp` to
opt in to or out of the AWS MCP servers (see [MCP servers](mcp.md)).

## Project-Local Configuration

Run the installer from the project that should receive the files. This example
assumes the setup repo is at `~/code/macols-ai-coding-setup`:

```bash
cd ~/code/my-project
~/code/macols-ai-coding-setup/install.sh codex --project
```

`--project` implies `--no-cli`. It leaves global MCPs, hooks, models and Oh My
Pi packages alone, then writes the project files supported by that tool:

| Tool | Project-local output |
|---|---|
| Claude Code | `.claude/agents/`, `.claude/skills/` |
| Codex | `.codex/skills/`, `.codex/agents/`, `AGENTS.md` |
| OpenCode | `.opencode/agents/`, `.opencode/skills/` |
| Pi (`pi` + `omp`) | `.pi/skills/`, `.omp/skills/`, `AGENTS.md` |
| ZCode | `.zcode/skills/`, `.zcode/commands/`, `AGENTS.md` |

You can combine `--project` with component selection, such as
`install.sh codex --project --skills-only`.

> [!CAUTION]
> The installers delete and rebuild generated agents and skills directories.
> Move or commit any hand-written files in those directories first. JSON,
> TOML and YAML settings owned by the user are merged.

## What Gets Installed, and Where

| Tool | Personas as | Steering | MCP | Hooks |
|------|-------------|----------|-----|-------|
| Claude Code | agents `~/.claude/agents/`, skills `~/.claude/skills/` | `~/.claude/CLAUDE.md` | `claude mcp add-json` into `~/.claude.json` | `~/.claude/settings.json` |
| Codex | skills `~/.codex/skills/`, agents `~/.codex/agents/*.toml` | `~/.codex/AGENTS.md` | `codex mcp add` into `~/.codex/config.toml` | `~/.codex/hooks.json` |
| OpenCode | agents `~/.config/opencode/agents/`, skills `.../skills/` | `~/.config/opencode/AGENTS.md` | `mcp` key in `~/.config/opencode/opencode.json` | plugin in `.../plugins/` |
| Pi (`pi` + `omp`) | Agent Skills in `~/.pi/agent/skills/` and `~/.omp/agent/skills/` (`/skill:<name>`) | both `.../agent/AGENTS.md` | `mcpServers` key in `~/.omp/agent/mcp.json` (omp only) | `pi-checks` extension in both agent dirs |
| ZCode | skills `~/.zcode/skills/`, commands `~/.zcode/commands/` | `~/.zcode/AGENTS.md` | `mcp.servers` in `~/.zcode/cli/config.json` | `hooks.events` in `~/.zcode/cli/config.json` |

The two Pi agents share no config directories: plain `pi` reads `~/.pi/agent`
and Oh My Pi (`omp`) reads `~/.omp/agent`. The installer writes skills,
steering and the pi-checks extension into both, and installs the Bun runtime
omp needs. It also writes model providers for both agents and omp's model
roles (see [Models](models.md)).

Codex removed custom prompts (`~/.codex/prompts/`) upstream in favour of Agent
Skills. The installer cleans up prompts left by earlier versions of this repo.
Codex still loads user skills from `~/.codex/skills/` (upstream now marks it
deprecated in favour of `~/.agents/skills/`). The installer stays there
because pi and OpenCode also scan `~/.agents/skills/` and would warn about a
duplicate of every persona.

Hooks are referenced in place from this repo's `hooks/` directory, so keep the
clone where it is after installing. See [Hooks](hooks.md).

### revdiff

[revdiff](https://revdiff.com) is a terminal UI for annotating diffs, files and
plans. Each agent's plugin opens it in an overlay (tmux, herdr, kitty,
wezterm, Zellij and others) and hands your annotations back to the agent. The
installers add the binary with `brew install umputun/apps/revdiff` (it is also
in `machine/Brewfile`) and then the upstream plugin for each tool that has one:

| Tool | How |
|------|-----|
| Claude Code | `claude plugin marketplace add umputun/revdiff` + `claude plugin install revdiff@revdiff` |
| Codex | `codex plugin marketplace add umputun/revdiff` + `codex plugin add revdiff@revdiff` |
| OpenCode | upstream `plugins/opencode/setup.sh`, run from a clone cached in `~/.cache/macols/revdiff` |
| Pi (`pi` + `omp`) | `pi install git:github.com/umputun/revdiff`, `omp install github:umputun/revdiff` |

ZCode has no revdiff integration. The auto-firing `revdiff-planning` plugin is
left out for Claude Code and Codex; add it by hand if you want every plan
opened for review. OpenCode's setup script includes its plan-review plugin.
Without Homebrew the binary step is skipped with a warning, and the plugins
report an error until `revdiff` is on PATH.

## Machine Setup

```bash
./install.sh --machine            # picks the right setup for your OS, then installs all tools
# or directly:
./machine/install_macos.sh        # macOS
./machine/install_ubuntu26.sh     # Ubuntu 24/26 / WSL2
```

[machine/README.md](../machine/README.md) lists everything the setup installs.
The Ubuntu script includes herdr and its project/review/browser plugins. On
macOS, install those separately with
`machine/install_brew_herdr_yazi_lazygit_nvim.sh`.

The herdr setup maps `prefix+p` to the project picker, `cmd+r` to reviewr, and
`prefix+shift+b` / `prefix+shift+o` to a herdr-browser split / overlay. New
worktrees open Claude Code beside yazi. The
[herdr and yazi guide](../machine/GETTING_STARTED_HERDR_YAZI_WITH_CLAUDE.md)
covers the workflow.

## Running With `--dangerously-skip-permissions`

Claude Code ignores bypass-permissions mode under root or sudo. The installer
adds `~/.claude/bin/claude-launch` (from `bin/claude-launch.sh`) to handle
that case:

```bash
~/.claude/bin/claude-launch            # or: alias cc=~/.claude/bin/claude-launch
```

- As a normal user, it runs `claude --dangerously-skip-permissions` directly.
- As root, it switches to `$CLAUDE_USER`, `$SUDO_USER` or the owner of `$HOME`.
  Claude needs to be installed for that user or system-wide.

For a root-owned sandbox, use `IS_SANDBOX=1 claude --dangerously-skip-permissions`.
Otherwise use the launcher.

## Post-Installation

```bash
aws configure                                   # AWS credentials (only with --aws-mcp)
podman machine init && podman machine start     # containers (macOS)
claude --version && codex --version             # sanity check
pi --version && omp --version                   # pi agents
ls -d /Applications/ZCode.app                   # ZCode (desktop app)
openspec --version                              # spec-driven dev CLI (auto-installed)
openspec init                                   # opt a project into OpenSpec (per repo)
ast-grep --version                              # structural search CLI (auto-installed)
```

Codex only runs hooks you have trusted, so approve them in Codex after
installing (and again after they change).

## Troubleshooting

```bash
# MCPs not loading
claude mcp list                                 # Claude
codex mcp list                                  # Codex
jq .mcp ~/.config/opencode/opencode.json        # OpenCode (mcp key, not mcp.json)
jq .mcpServers ~/.omp/agent/mcp.json            # Oh My Pi

# PATH not updated
source ~/.zshrc   # or ~/.bashrc
```

Run `./tests/verify_install.sh <tool>` to check the generated files for one
tool (see [Testing](testing.md)).

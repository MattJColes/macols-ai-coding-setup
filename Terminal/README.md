# Optional development environment

The scripts in this directory build the workstation layer used alongside
`macols-ai-coding-setup`. They install language runtimes, cloud and container
tools, editors and the four AI coding CLIs configured by the repository root.

Use the per-tool installers in the [top-level README](../README.md) if you only
want the AI coding setup. The scripts here make broader system changes, install
many packages and prompt for Git and AWS configuration.

## Supported systems

- macOS with Xcode Command Line Tools
- Ubuntu 24.04 or 26.04 with `sudo` access

The Ubuntu entry point keeps its historical filename,
`install_ubuntu26.sh`, but supports both Ubuntu releases.

## Quick start

From the repository root:

```bash
./install.sh --env
```

Or run the platform setup directly:

```bash
cd Terminal
./install_macos.sh       # macOS
./install_ubuntu26.sh    # Ubuntu 24.04 or 26.04
```

Review the relevant script before running it. Both platform installers require
an internet connection, install packages, update shell configuration, prompt
for Git identity and run `aws configure`. Existing Neovim data is moved to
timestamped backup directories before LazyVim is installed.

## What gets installed

Both platform installers provide:

- Python 3.14, uv, pytest, ruff, mypy, pip-audit, semgrep and Commitizen
- Node.js through NVM, TypeScript and AWS CDK
- AWS CLI, GitHub CLI, Podman and common command-line tools
- Neovim/LazyVim, ripgrep, fd and lazygit
- Claude Code, Codex, OpenCode and Oh My Pi, including this repository's
  generated personas, instructions, MCP registration and hooks

Platform-specific additions:

| Platform | Additional setup |
|---|---|
| macOS | Homebrew, Flutter, Xcode tooling and a Podman machine-ready install |
| Ubuntu | Docker, QEMU/binfmt, Ollama, zsh/Powerlevel10k, tmux, Homebrew, yazi, herdr and its project/review plugins |

To install the herdr/yazi workflow separately on either platform, run:

```bash
./install_brew_herdr_yazi_lazygit_nvim.sh
```

That helper merges herdr keybindings into the existing user config and adds an
idempotent SSH auto-launch block. See
[GETTING_STARTED_HERDR_YAZI_WITH_CLAUDE.md](GETTING_STARTED_HERDR_YAZI_WITH_CLAUDE.md)
for the project picker, review mode and worktree layout.

## Other optional scripts

| Script | Purpose |
|---|---|
| `install_ohmyzsh_p10k.sh` | Install zsh, Oh My Zsh and Powerlevel10k |
| `install_ghostty_config.sh` | Install the repository's Ghostty configuration |
| `install_iterm_colors.sh` | Install the Ayu Dark iTerm2 colour scheme |
| `install_lazyvim_config.sh` | Install the repository's LazyVim configuration |
| `configure_lmstudio.sh` | Configure OpenCode for a local LM Studio model |
| `host_ollama_model.sh` | Expose an Ollama model from a host machine |
| `expand_disk.sh` | Assist with expanding an Ubuntu disk |

The focused remote-development guides cover
[VS Code over Tailscale](vscode-over-tailscale.md) and
[Mosh from iPad to Ubuntu](ubuntu-mosh-ipad.md).

## After installation

Start a new terminal session, then verify the pieces you intend to use:

```bash
python --version
uv --version
node --version
aws --version
podman --version
nvim --version

claude --version
codex --version
opencode --version
omp --version
```

On macOS, initialise Podman once:

```bash
podman machine init
podman machine start
```

On Ubuntu, log out and back in (or run `newgrp docker`) before using Docker
without `sudo`. Start Ollama with `ollama serve` if its service is not already
running.

## Configuration locations

The installers use the standard user locations:

```text
~/.zshrc and ~/.bashrc          shell setup
~/.config/nvim/                Neovim/LazyVim
~/.config/herdr/               herdr configuration and layouts
~/.aws/                        AWS CLI configuration
~/.claude/                     Claude Code
~/.codex/                      Codex
~/.config/opencode/            OpenCode
~/.omp/                        Oh My Pi
~/.local/bin/                  user-level executables
```

The AI coding configuration is generated from `../shared/`. Do not treat the
installed files in these home-directory locations as the source of truth.

## Troubleshooting

Reload shell configuration after installation:

```bash
source ~/.zshrc    # zsh
source ~/.bashrc   # bash
```

If Podman is not running on macOS:

```bash
podman machine start
```

If LazyVim needs to be rebuilt, move its directories aside rather than
deleting them, then rerun the platform installer. Each installer already uses
timestamped backups when it finds existing Neovim state.

For AI tool configuration and per-tool troubleshooting, return to the
[top-level README](../README.md#troubleshooting).

# Optional development environment

These are the scripts I use to set up my macOS and Ubuntu development machines.
They install the language runtimes, container tools, editor and four coding
agents used by this repo.

If you only want the agent config, use the per-tool installers in the
[top-level README](../README.md). The scripts here install system packages and
prompt for your Git and AWS settings.

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
cd machine-setup
./install_macos.sh       # macOS
./install_ubuntu26.sh    # Ubuntu 24.04 or 26.04
```

Read the platform script before running it. It needs an internet connection and
updates your shell config. It also asks for your Git identity and runs
`aws configure`. Existing Neovim data is moved into timestamped backups before
LazyVim is installed.

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

The helper merges herdr keybindings into your existing config and adds the SSH
auto-launch block once. See
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

There are also guides for
[VS Code over Tailscale](vscode-over-tailscale.md) and
[Mosh from iPad to Ubuntu](ubuntu-mosh-ipad.md).

## After installation

Start a new terminal and check the tools you plan to use:

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

The installers write to these user locations:

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

The AI coding config comes from `../shared/`. Make changes there and rerun the
installer instead of editing the generated copies.

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

If LazyVim needs rebuilding, move its directories aside and rerun the platform
installer. The installer makes timestamped backups when it finds existing
Neovim state.

For AI tool configuration and per-tool troubleshooting, return to the
[top-level README](../README.md#troubleshooting).

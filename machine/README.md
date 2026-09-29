# Optional development environment

These are the scripts I use to set up my macOS and Ubuntu development machines.
They install the language runtimes, container tools, editor and coding agents
used by this repo.

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
./install.sh --machine
```

Or run the platform setup directly:

```bash
cd machine
./install_macos.sh       # macOS
./install_ubuntu26.sh    # Ubuntu 24.04 or 26.04
```

Read the platform script before running it. It needs an internet connection and
updates your shell config through marker-delimited blocks, so re-running it
upgrades packages without duplicating anything. It asks for your Git identity
only when none is set, and runs `aws configure` only when `~/.aws` is empty.
Prompts are skipped without a terminal or with `MACOLS_NONINTERACTIVE=1`. An
existing `~/.config/nvim` is never touched.

Both platform scripts share `common.sh` and install their packages from one
[`Brewfile`](Brewfile) with `brew bundle`. To add a tool, add it there.

## What gets installed

Both platform installers provide:

- Everything in the [`Brewfile`](Brewfile): git, GitHub CLI, AWS CLI, Neovim,
  lazygit, delta, hunk, yazi, tmux, ripgrep, fd, jq, yq, ast-grep,
  starship, uv, Go, gopls, bun, shellcheck and golangci-lint (plus Podman,
  Flutter, coreutils and the Inconsolata font on macOS)
- Python 3.14 from `uv python install`, with pytest, ruff, mypy, pyright,
  pip-audit, semgrep and Commitizen as uv tools
- Node.js through NVM, TypeScript and AWS CDK
- zsh with Oh My Zsh and the starship prompt (in zsh and bash); an earlier
  Powerlevel10k setup is removed from `~/.zshrc`
- The repository's LazyVim config (`Lazyvim/`) when you have no Neovim config
- herdr, its plugins and layouts, and the yazi config
- Claude Code, Codex, OpenCode, both Pi agents (plain `pi` and Oh My Pi) and
  ZCode's configuration (the ZCode app itself is a separate desktop install),
  including this repository's generated personas, instructions, MCP
  registration and hooks

Platform-specific additions:

| Platform | Additional setup |
|---|---|
| macOS | Xcode Command Line Tools check, Flutter and a Podman machine-ready install |
| Ubuntu | Docker, Podman and QEMU/binfmt from apt, and Ollama with its systemd service |

To install the herdr/yazi workflow separately on either platform, run:

```bash
./install_brew_herdr_yazi_lazygit_nvim.sh
```

The helper merges herdr keybindings into your existing config and adds the SSH
auto-launch block once. It also installs herdr-browser and its prerequisites
(bun, Chrome/Chromium) and turns on `[experimental] kitty_graphics`, which
herdr-browser needs to draw into a pane. See
[GETTING_STARTED_HERDR_YAZI_WITH_CLAUDE.md](GETTING_STARTED_HERDR_YAZI_WITH_CLAUDE.md)
for the project picker, review mode, browser panes and worktree layout.

## Other optional scripts

| Script | Purpose |
|---|---|
| `install_zsh.sh` | Install zsh and Oh My Zsh and make zsh the login shell |
| `install_ghostty_config.sh` | Install the repository's Ghostty configuration to `~/.config/ghostty/config.ghostty` |
| `install_iterm_colors.sh` | Install the Ayu Dark iTerm2 colour scheme |
| `install_lazyvim_config.sh` | Replace your Neovim config with the repository's LazyVim configuration (backs up the old one) |
| `configure_lmstudio.sh` | Merge a local LM Studio provider into OpenCode's `opencode.json` |
| `host_ollama_model.sh` | Serve an Ollama model on this machine's Tailscale address only, preloaded, with a q8_0 KV cache |
| `expand_disk.sh` | Assist with expanding an Ubuntu disk |

There are also guides for
[VS Code over Tailscale](vscode-over-tailscale.md) and
[Mosh from iPad to Ubuntu](ubuntu-mosh-ipad.md).

## After installation

Start a new terminal and check the tools you plan to use:

```bash
python3 --version
uv --version
starship --version
node --version
aws --version
podman --version
nvim --version

claude --version
codex --version
opencode --version
pi --version
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
~/.pi/                         Pi agent (plain pi)
~/.omp/                        Oh My Pi (omp)
~/.zcode/                      ZCode
~/.local/bin/                  user-level executables
```

The AI coding config comes from `../config/` and `../hooks/`. Make changes there and rerun the
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

If LazyVim needs rebuilding, run `./install_lazyvim_config.sh`, which backs up
your current config first.

For AI tool configuration and per-tool troubleshooting, return to the
[installing guide](../docs/installing.md).

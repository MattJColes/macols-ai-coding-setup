# macols-ai-coding-setup

One setup for four AI coding CLIs — **Claude Code**, **Codex**, **OpenCode** and
**Oh My Pi** (`omp`, selected as `pi`) — plus an optional macOS or Ubuntu
development environment.

This repository is a generator, not a dump of files from `~/.config`.
Personas, agent instructions, MCP servers and quality hooks are authored once
under `shared/`; the installers render those sources into each tool's native
format. Change the shared source once, then reinstall whichever tools you use.

The steering teaches a plain-git workflow — one branch per change, git
worktrees for parallel work — and each installer installs the
[ponytail](https://github.com/DietrichGebert/ponytail) minimal-mode ruleset for
every agent via that agent's native mechanism, plus the
[OpenSpec](https://github.com/Fission-AI/openspec) CLI for spec-driven
development in repositories that opt in.

## Quick start

Clone the repository, then install one tool or all four:

```bash
git clone https://github.com/MattJColes/macols-ai-coding-setup.git
cd macols-ai-coding-setup

./install.sh codex             # one tool
./install.sh claudecode pi     # several tools
./install.sh                   # all four tools
```

The installers add or update configuration in your home directory and install
missing CLI dependencies. Review the scripts first if you do not want them to
manage Homebrew, npm packages or user-level configuration. To render config
without installing the CLI itself, run the relevant per-tool installer with
`--no-cli` (or `--no-pi` for Oh My Pi).

Supported platforms are macOS and Linux for the tool installers. The optional
full development-environment setup targets macOS and Ubuntu 24.04/26.04.

## Choose what to install

Start with the row that matches what you want:

| Goal | Command |
|---|---|
| Install and configure everything | `./install.sh` |
| Install one tool and all its configuration | `./install.sh codex` |
| Install several tools | `./install.sh claudecode opencode` |
| Keep an existing CLI and install all its configuration | `./install_codex.sh --no-cli` |
| Install only selected configuration | `./install_codex.sh --skills-only --no-cli` |
| Preview the personas available to a tool | `./install_codex.sh --list` |
| Install configuration into one project | Run `install_<tool>.sh --project` from that project's directory |
| Build the full workstation as well | `./install.sh --env` |

With no component options, a per-tool installer installs the CLI and all of
that tool's configuration. Component options can be combined: the first
`--*-only` option turns off the default set, and each option you provide turns
that component back on.

For example:

```bash
# Codex skills only; do not install or upgrade the Codex CLI
./install_codex.sh --skills-only --no-cli

# Claude Code MCPs and hooks only; use the existing Claude CLI
./install_claudecode.sh --mcps-only --hooks-only --no-cli

# Codex prompts plus shared AGENTS.md instructions
./install_codex.sh --prompts-only --instructions-only --no-cli
```

Component flags belong to the per-tool installers, not `install.sh`. Run the
relevant installer with `--help` to see its exact options. A component is the
smallest supported selection unit: for example, `--skills-only` installs every
applicable skill shown by `--list`.

### Project-local configuration

Run a per-tool installer from the project that should receive the files. For
example, if this setup repository is at `~/code/macols-ai-coding-setup`:

```bash
cd ~/code/my-project
~/code/macols-ai-coding-setup/install_codex.sh --project
```

`--project` implies `--no-cli` and does not change global MCPs, hooks or Oh My
Pi packages. It writes only the project formats that the selected tool
supports:

| Tool | Project-local output |
|---|---|
| Claude Code | `.claude/agents/`, `.claude/skills/` |
| Codex | `.codex/prompts/`, `.codex/skills/`, `.codex/agents/`, `AGENTS.md` |
| OpenCode | `.opencode/agents/`, `.opencode/skills/` |
| Oh My Pi | `.omp/skills/`, `AGENTS.md` |

You can combine `--project` with component selection, such as
`install_codex.sh --project --skills-only`.

> [!CAUTION]
> When an installer writes a generated agents, skills or prompts directory, it
> replaces that target directory. Move or commit hand-written files there
> before running the installer. User-owned JSON/TOML settings are merged rather
> than replaced.

## Structure

```
macols-ai-coding-setup/
├── install.sh              # orchestrator: env (optional) + all four tools
├── install_claudecode.sh   # self-contained per-tool installers
├── install_codex.sh        #   (ensure brew + CLI, then install configs)
├── install_opencode.sh
├── install_pi.sh           # installs Oh My Pi (omp)
├── lib/
│   └── common.sh           # shared install functions used by all installers
├── bin/
│   └── claude-launch.sh    # root-safe launcher for --dangerously-skip-permissions
├── shared/                 # ── single sources of truth ──
│   ├── personas/<name>/SKILL.md   # specialist personas (agents/skills/prompts)
│   ├── steering/base.md + tools/  # system steering, tokenised per tool
│   ├── mcp-config.json            # MCP server definitions
│   ├── hooks/                     # post-code / post-task / pre-deploy + plugins
│   ├── checks_common.sh          # shared check helpers (discovery, gate, timeout)
│   ├── post_code_checks.sh        # per-edit lint/type-check battery
│   ├── post_task_checks.sh        # turn-end battery (runs checks in parallel)
│   └── ensure_node.sh
├── Terminal/               # macOS / Ubuntu dev-environment setup
├── tests/verify_install.sh # post-install location + introspection checks
└── .github/workflows/      # installer tests, security scanning, dependabot
```

There are no per-tool directories: every difference between the tools lives in a
small per-tool file under `shared/` (e.g. `shared/steering/tools/codex.json`) and
in the matching `install_<tool>.sh`.

## Per-tool option reference

Each `install_<tool>.sh` is self-contained — it ensures Homebrew (macOS), the
CLI binary and the OpenSpec CLI, then installs that tool's
agents/skills/prompts, steering, MCPs and hooks. Run one, several, or all:

```bash
./install.sh                  # all four tools (binaries + configs)
./install.sh claudecode pi    # just Claude Code and Oh My Pi
./install.sh --env            # run the Terminal dev-environment setup first
./install_codex.sh            # one tool directly
```

| Installer | Selectable components | Skip CLI install | Other choices |
|---|---|---|---|
| `install_claudecode.sh` | `--agents-only`, `--skills-only`, `--mcps-only`, `--hooks-only` | `--no-cli` | `--project`, `--list` |
| `install_codex.sh` | `--prompts-only`, `--skills-only`, `--agents-only`, `--instructions-only`, `--mcps-only`, `--hooks-only` | `--no-cli` | `--project`, `--list` |
| `install_opencode.sh` | `--agents-only`, `--skills-only`, `--mcps-only`, `--hooks-only` | `--no-cli` | `--project`, `--list` |
| `install_pi.sh` | `--skills-only`, `--context-only`, `--hooks-only`, `--packages-only` | `--no-pi` | `--no-packages`, `--project`, `--list`; no MCP support |

`--no-cli` and `--no-pi` skip installing or upgrading the binary; they do not
remove an existing installation. Operations such as MCP registration still
expect the relevant CLI to already be available.

### Dev environment

```bash
./install.sh --env            # picks the right Terminal script for your OS
# or directly:
cd Terminal && ./install_macos.sh        # macOS
cd Terminal && ./install_ubuntu26.sh     # Ubuntu 24/26 / WSL2
```

See **[Terminal/README.md](Terminal/README.md)** for the full toolchain
(Python 3.14 + uv, Node.js + TypeScript/CDK, Podman, AWS CLI, LazyVim, etc.).
The Ubuntu setup also installs **herdr** with the **herdr-plus** and
**herdr-reviewr** plugins; on macOS, run
`Terminal/install_brew_herdr_yazi_lazygit_nvim.sh` separately. `prefix+p`
opens the project picker, `cmd+r` toggles reviewr, and a wildcard worktree
layout opens Claude Code + yazi in every new worktree (see
[Terminal/GETTING_STARTED_HERDR_YAZI_WITH_CLAUDE.md](Terminal/GETTING_STARTED_HERDR_YAZI_WITH_CLAUDE.md)).

### Running with `--dangerously-skip-permissions`

Claude Code refuses bypass-permissions mode under root/sudo (the flag silently
drops back to the default mode), which bites in containers and install scripts
that run as root. The Claude Code installer drops a launcher at
`~/.claude/bin/claude-launch` that handles this the documented way:

```bash
~/.claude/bin/claude-launch            # or: alias cc=~/.claude/bin/claude-launch
```

- **Non-root** → runs `claude --dangerously-skip-permissions` directly.
- **Root** → drops to a non-root user (`$CLAUDE_USER`, else `$SUDO_USER`, else the
  owner of `$HOME`) and runs Claude as them. For this to work Claude must be
  installed for that user (or system-wide), not just for root.

If you genuinely intend to run as root inside a sandbox, the documented escape
hatch is `IS_SANDBOX=1 claude --dangerously-skip-permissions` — but a non-root
user is preferred.

## What gets installed, and where

| Tool | Personas as | Steering | MCP | Hooks |
|------|-------------|----------|-----|-------|
| Claude Code | agents `~/.claude/agents/`, skills `~/.claude/skills/` | `~/.claude/CLAUDE.md` | `claude mcp add-json` → `~/.claude.json` | `~/.claude/settings.json` |
| Codex | prompts `~/.codex/prompts/`, skills `~/.codex/skills/`, agents `~/.codex/agents/*.toml` | `~/.codex/AGENTS.md` | `codex mcp add` → `~/.codex/config.toml` | `~/.codex/hooks.json` |
| OpenCode | agents `~/.config/opencode/agents/`, skills `…/skills/` | `~/.config/opencode/AGENTS.md` | `mcp` key in `~/.config/opencode/opencode.json` | plugin in `…/plugins/` |
| Oh My Pi | Agent Skills `~/.omp/agent/skills/` (`/skill:<name>`) | `~/.omp/agent/AGENTS.md` | none by design | `pi-checks` extension |

**Oh My Pi is deliberately different:** it has no MCP — external capabilities
come from CLI tools, Agent Skills and pluggable packages (`omp install <pkg>`,
e.g. `pi-agent-web-access`, `pi-subagents`, `pi-ask-user`). It replaces the
plain `pi` agent (the old install is retired) and its npm bundle runs on Bun,
which the installer provisions automatically.

### Git worktree workflow

The steering teaches agents a plain-git loop: start each change on its own
branch (`git checkout -b feat/x`), commit in small conventional commits, and
publish with `git push -u origin <branch>` + a PR. Parallel agents each get
their own git worktree (`git worktree add ../repo-task -b feat/task`) so they
never collide in one checkout; review everything in one view with
`git log --oneline --graph --all`. In herdr, `Ctrl+b` `Shift+g` creates a new
worktree, and the herdr-plus wildcard worktree layout (installed by the
Terminal setup) automatically opens Claude Code + yazi in each one.

### Ponytail

[Ponytail](https://github.com/DietrichGebert/ponytail) (lazy/YAGNI mode) is
installed for every agent via its native mechanism:

- **Claude Code** — plugin: `claude plugin marketplace add DietrichGebert/ponytail`
  + `claude plugin install ponytail@ponytail` (falls back to declaring both in
  `~/.claude/settings.json` when offline; fetched on next launch).
- **Oh My Pi** — package: `omp install git:github.com/DietrichGebert/ponytail`.
- **Codex / OpenCode / Oh My Pi AGENTS.md** — ponytail's AGENTS.md ruleset
  (vendored at `shared/steering/ponytail.AGENTS.md`) is appended inside
  `<!-- ponytail:ruleset:start/end -->` marker comments; re-runs replace the
  block instead of duplicating it. Re-vendor the file to pick up upstream changes.

Ponytail's hooks need `node` on the non-interactive PATH; the installers link
`node`/`npm`/`npx` into `~/.local/bin` to guarantee that.

### OpenSpec

Every installer provisions the [OpenSpec](https://github.com/Fission-AI/openspec)
CLI (`npm install -g @fission-ai/openspec`, Node ≥ 20.19) for spec-driven
development. Adoption is per-repo and opt-in: run `openspec init` in a project
to create its `openspec/` directory and generate the agent slash commands
(`/opsx:explore`, `/opsx:propose`, `/opsx:apply`, `/opsx:archive`). The
steering teaches agents to follow the propose → approve → implement → archive
loop wherever an `openspec/` directory exists, and never to `openspec init`
uninvited.

### ast-grep

Every installer provisions the [ast-grep](https://ast-grep.github.io) CLI
(`npm install -g @ast-grep/cli`, ships both `ast-grep` and `sg` binaries) for
structural code search. It backs the code-reviewer persona and the Spec
Anchors steering section: repos that pin spec sections to code with anchor
rules under `specs/anchors/*.yml` get the resolve-before-change /
propose-spec-diff-after workflow. Adoption is per-repo and opt-in — no anchor
files, no workflow.

## Personas

Each persona is one file: `shared/personas/<name>/SKILL.md`. Its frontmatter
(`agent: true`, `model:`, `allowed-tools:`) drives how each installer renders it.
Add or edit a persona once and every tool picks it up on the next install.

**Development:** python-backend, frontend-engineer-ts, dart-app-developer,
cdk-expert-ts, cdk-expert-python, data-scientist ·
**Testing and diagnosis:** diagnosing-bugs, test-coordinator,
python-test-engineer, typescript-test-engineer ·
**DevOps and reliability:** devops-engineer, sre-reliability, linux-specialist,
code-reviewer ·
**Architecture and design:** architecture-expert, ui-ux-designer,
security-specialist ·
**Management:** documentation-engineer, product-manager, project-coordinator,
engineering-manager ·
**Research and advisory:** deep-research-scientist, ideation, legal-advisor ·
**Writing:** interrogate-me, writing-chat-messages, writing-documents,
writing-short-articles ·
**Workflow:** commit, mental-model, ponytail-senior-engineer, spec-anchors

## MCP servers

Defined once in `shared/mcp-config.json` and registered into each tool's native
config: **filesystem**, **puppeteer**, **playwright**, **context7**, **dart**,
**aws-mcp**, **aws-iac**. (Oh My Pi excluded by design.)

- **aws-mcp** — the managed [AWS MCP Server](https://aws.amazon.com/blogs/aws/the-aws-mcp-server-is-now-generally-available/)
  (Agent Toolkit for AWS), reached through the `mcp-proxy-for-aws` package,
  which SigV4-signs requests with your ambient AWS credentials. The endpoint
  pins the server region (`us-east-1` here); the operations it performs default
  to your credential chain's region.
- **aws-iac** — the [AWS IaC MCP Server](https://awslabs.github.io/mcp/servers/aws-iac-mcp-server)
  (`awslabs.aws-iac-mcp-server` via uvx): CloudFormation/CDK validation,
  documentation search and best-practice checks. Uses ambient AWS credentials.

## Hooks

Thin wrappers in `shared/hooks/` source the shared check libraries and run
advisory (never blocking) checks:

- **post-code** (per edit, all tools) — fast, file-scoped lint/type-check
- **post-task** (turn end, all tools) — full test/security battery (linters, audits, semgrep), only when code changed
- **pre-deploy** (all tools) — confirms `cdk diff` before `cdk deploy`/`destroy`. The matcher is single-sourced in `pre_deploy_check.sh`: Claude/Codex gate through the PreToolUse "ask" protocol, OpenCode blocks the first attempt via `tool.execute.before` (an identical retry after user confirmation passes), and omp asks via the extension's `ctx.ui.confirm`.

## Testing

`tests/verify_install.sh <tool>` asserts each tool's files landed in the expected
locations and that the CLI reports a configured state (non-auth introspection).
The **Test installers** GitHub Actions workflow runs `shellcheck` and, on Ubuntu,
installs each tool and runs the verifier across a `claudecode/codex/opencode/pi`
matrix.

```bash
./tests/verify_install.sh claudecode
```

For repository changes, run the checks that match what you touched:

```bash
bash -n install.sh install_*.sh Terminal/*.sh
./scripts/spec_drift_gate.sh --check
./tests/test_spec_drift_gate.sh
```

The root [AGENTS.md](AGENTS.md) is the maintainer and AI-agent guide. It maps
each kind of change to its source-of-truth file and records the idempotency,
portability, OpenSpec and spec-anchor rules used in this repository.

## Post-installation

```bash
aws configure                                   # AWS credentials for aws-* MCPs
podman machine init && podman machine start     # containers (macOS)
claude --version && codex --version             # sanity check
omp --version                                   # oh-my-pi
openspec --version                              # spec-driven dev CLI (auto-installed)
openspec init                                   # opt a project into OpenSpec (per repo)
ast-grep --version                              # structural search CLI (auto-installed)
```

## Troubleshooting

```bash
# MCPs not loading
claude mcp list                                 # Claude
codex mcp list                                  # Codex
jq .mcp ~/.config/opencode/opencode.json        # OpenCode (mcp key, not mcp.json)

# PATH not updated
source ~/.zshrc   # or ~/.bashrc
```

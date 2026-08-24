# macols-ai-coding-setup

I keep my **Claude Code**, **Codex**, **OpenCode** and **Oh My Pi** setup in this
repo. The files under `shared/` define the personas, instructions, MCP servers
and checks. Each installer turns them into the format its tool expects.

There is also an optional setup for my macOS and Ubuntu development machines.
It installs the language runtimes, containers and terminal tools I use.

The generated instructions use plain git branches and worktrees. The installers
also add [ponytail](https://github.com/DietrichGebert/ponytail) for the minimal
mode rules and the [OpenSpec](https://github.com/Fission-AI/openspec) CLI for
repos that use specs.

## Quick start

Clone the repo and run the installer for the tools you use:

```bash
git clone https://github.com/MattJColes/macols-ai-coding-setup.git
cd macols-ai-coding-setup

./install.sh codex             # one tool
./install.sh claudecode pi     # several tools
./install.sh                   # all four tools
```

By default, the scripts install missing CLIs and update configuration in your
home directory. If you already have the CLI, call its installer with
`--no-cli`. Oh My Pi uses `--no-pi` for the same job.

The tool installers run on macOS and Linux. The optional development-machine
setup targets macOS and Ubuntu 24.04/26.04.

## Choose what to install

Pick the closest command and change the tool name if needed:

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

With no component flags, a per-tool installer installs everything for that
tool. The first `--*-only` flag clears the default set. Add more `--*-only`
flags to install those components together.

```bash
# Codex skills only. Keep the existing Codex CLI.
./install_codex.sh --skills-only --no-cli

# Claude Code MCPs and hooks only. Keep the existing Claude CLI.
./install_claudecode.sh --mcps-only --hooks-only --no-cli

# Codex prompts plus shared AGENTS.md instructions
./install_codex.sh --prompts-only --instructions-only --no-cli
```

Component flags only work on the per-tool installers. Run one with `--help` to
see its options. A component is the smallest selection unit, so
`--skills-only` installs every applicable skill shown by `--list`.

### Project-local configuration

Run the installer from the project that should receive the files. This example
assumes the setup repo is at `~/code/macols-ai-coding-setup`:

```bash
cd ~/code/my-project
~/code/macols-ai-coding-setup/install_codex.sh --project
```

`--project` implies `--no-cli`. It leaves global MCPs, hooks and Oh My Pi
packages alone, then writes the project files supported by that tool:

| Tool | Project-local output |
|---|---|
| Claude Code | `.claude/agents/`, `.claude/skills/` |
| Codex | `.codex/prompts/`, `.codex/skills/`, `.codex/agents/`, `AGENTS.md` |
| OpenCode | `.opencode/agents/`, `.opencode/skills/` |
| Oh My Pi | `.omp/skills/`, `AGENTS.md` |

You can combine `--project` with component selection, such as
`install_codex.sh --project --skills-only`.

> [!CAUTION]
> The installers delete and rebuild generated agents, skills and prompts
> directories. Move or commit any hand-written files in those directories
> first. JSON and TOML settings owned by the user are merged.

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
├── machine-setup/          # macOS / Ubuntu development-machine setup
├── tests/verify_install.sh # post-install location + introspection checks
└── .github/workflows/      # installer tests, security scanning, dependabot
```

Tool-specific differences live in `shared/steering/tools/` and the matching
`install_<tool>.sh`. Shared behaviour stays under `shared/`.

## Per-tool option reference

Each tool has its own installer. With no flags it installs the CLI and all of
the config this repo provides.

| Installer | Selectable components | Skip CLI install | Other choices |
|---|---|---|---|
| `install_claudecode.sh` | `--agents-only`, `--skills-only`, `--mcps-only`, `--hooks-only` | `--no-cli` | `--project`, `--list` |
| `install_codex.sh` | `--prompts-only`, `--skills-only`, `--agents-only`, `--instructions-only`, `--mcps-only`, `--hooks-only` | `--no-cli` | `--project`, `--list` |
| `install_opencode.sh` | `--agents-only`, `--skills-only`, `--mcps-only`, `--hooks-only` | `--no-cli` | `--project`, `--list` |
| `install_pi.sh` | `--skills-only`, `--context-only`, `--hooks-only`, `--packages-only` | `--no-pi` | `--no-packages`, `--project`, `--list` (no MCP support) |

`--no-cli` and `--no-pi` skip the binary install or upgrade. They don't remove
anything. MCP registration still needs the tool's CLI on your `PATH`.

### Machine setup

```bash
./install.sh --env            # picks the right machine setup for your OS
# or directly:
cd machine-setup && ./install_macos.sh        # macOS
cd machine-setup && ./install_ubuntu26.sh     # Ubuntu 24/26 / WSL2
```

[machine-setup/README.md](machine-setup/README.md) lists everything the setup
installs. The Ubuntu script includes herdr and its project/review plugins. On
macOS, install those separately with
`machine-setup/install_brew_herdr_yazi_lazygit_nvim.sh`.

The herdr setup maps `prefix+p` to the project picker, `cmd+r` to reviewr, and
`prefix+shift+b` / `prefix+shift+o` to a herdr-browser split / overlay.
New worktrees open Claude Code beside yazi. The
[herdr and yazi guide](machine-setup/GETTING_STARTED_HERDR_YAZI_WITH_CLAUDE.md)
covers the workflow.

### Running with `--dangerously-skip-permissions`

Claude Code ignores bypass-permissions mode under root or sudo. The installer
adds `~/.claude/bin/claude-launch` to handle that case:

```bash
~/.claude/bin/claude-launch            # or: alias cc=~/.claude/bin/claude-launch
```

- As a normal user, it runs `claude --dangerously-skip-permissions` directly.
- As root, it switches to `$CLAUDE_USER`, `$SUDO_USER` or the owner of `$HOME`.
  Claude needs to be installed for that user or system-wide.

For a root-owned sandbox, use
`IS_SANDBOX=1 claude --dangerously-skip-permissions`. Otherwise use the
launcher.

## What gets installed, and where

| Tool | Personas as | Steering | MCP | Hooks |
|------|-------------|----------|-----|-------|
| Claude Code | agents `~/.claude/agents/`, skills `~/.claude/skills/` | `~/.claude/CLAUDE.md` | `claude mcp add-json` → `~/.claude.json` | `~/.claude/settings.json` |
| Codex | prompts `~/.codex/prompts/`, skills `~/.codex/skills/`, agents `~/.codex/agents/*.toml` | `~/.codex/AGENTS.md` | `codex mcp add` → `~/.codex/config.toml` | `~/.codex/hooks.json` |
| OpenCode | agents `~/.config/opencode/agents/`, skills `…/skills/` | `~/.config/opencode/AGENTS.md` | `mcp` key in `~/.config/opencode/opencode.json` | plugin in `…/plugins/` |
| Oh My Pi | Agent Skills `~/.omp/agent/skills/` (`/skill:<name>`) | `~/.omp/agent/AGENTS.md` | none by design | `pi-checks` extension |

Oh My Pi doesn't support MCP. External capabilities come from CLI tools, Agent
Skills and packages installed with `omp install <pkg>`. It replaces the old
plain `pi` agent, and the installer sets up the Bun runtime it needs.

### Git worktree workflow

The generated instructions use one branch per change and small conventional
commits. Parallel agents get separate worktrees, created with
`git worktree add ../repo-task -b feat/task`. Use
`git log --oneline --graph --all` to see them together.

In herdr, `Ctrl+b` `Shift+g` creates a worktree. The wildcard layout opens
Claude Code beside yazi.

For a chain of related changes the instructions reach for GitHub's stacked
pull requests instead of one long branch: `gh stack init` / `add` / `submit`
to build and publish the chain, `gh stack sync` to cascade rebase when the base
moves, and `gh stack merge` bottom-up. The machine setup installs the
`github/gh-stack` extension alongside the GitHub CLI.

### Ponytail

[Ponytail](https://github.com/DietrichGebert/ponytail) provides the lazy/YAGNI
rules. Each tool loads it differently:

- **Claude Code:** plugin: `claude plugin marketplace add DietrichGebert/ponytail`
  + `claude plugin install ponytail@ponytail` (falls back to declaring both in
  `~/.claude/settings.json` when offline, ready for the next launch).
- **Oh My Pi:** package: `omp install git:github.com/DietrichGebert/ponytail`.
- **Codex / OpenCode / Oh My Pi AGENTS.md:** ponytail's AGENTS.md ruleset
  (vendored at `shared/steering/ponytail.AGENTS.md`) is appended inside
  `<!-- ponytail:ruleset:start/end -->` marker comments. Re-runs replace the
  block. Re-vendor the file to pick up upstream changes.

Ponytail's hooks need `node` on the non-interactive PATH. The installers link
`node`/`npm`/`npx` into `~/.local/bin`.

### Response format

`shared/steering/response-format.md` holds one block of output rules — lead
with the action, number multi-step work, restate progress, suppress tangents,
real time estimates, cap lists, no preamble or closers, end on one concrete
next step. Adapted from [i-have-adhd](https://github.com/ayghri/i-have-adhd)
(MIT), which ships the same idea as an opt-in skill.

Here it is always on, and it reaches every surface from that one file:

- **Steering:** substituted into `base.md` via `{{RESPONSE_FORMAT}}`, so all
  four tools' steering documents carry it.
- **Personas:** appended to every rendered agent, skill and Codex prompt by
  `generate_personas` — a subagent has its own system prompt and would
  otherwise miss the rules.
- **Claude Desktop:** appended to every `SKILL.md` in the packaged bundle.

The block scopes itself to chat replies. Content the agent authors — documents,
blog posts, specs, PR and commit bodies, code and comments — keeps its own
conventions, so the writing personas and the review checklists are unaffected.
Say "stop adhd mode" or "long form" to suspend it for a session. Edit the one
file and rerun the installers to change the rules.

### OpenSpec

The installers add the [OpenSpec](https://github.com/Fission-AI/openspec) CLI
(`npm install -g @fission-ai/openspec`, Node >= 20.19). Run `openspec init` in
a project to create its `openspec/` directory and generate the slash commands
(`/opsx:explore`, `/opsx:propose`, `/opsx:apply`, `/opsx:archive`). The
instructions follow that workflow when the directory exists. The installers
don't initialise projects for you.

### ast-grep

The installers also add [ast-grep](https://ast-grep.github.io) for structural
code search. The quality-review-code persona uses it, as does the
workflow-maintain-spec-anchors persona. A repo opts in by adding rules under
`specs/anchors/*.yml`.

## Personas

Each persona is one file: `shared/personas/<name>/SKILL.md`. Its frontmatter
(`agent: true`, `allowed-tools:`, `user-invocable:`) drives how each installer renders it.
Add or edit a persona once and every tool picks it up on the next install.

- **Development:** development-build-python-backends,
  development-build-react-frontends, development-build-flutter-apps,
  development-build-data-and-ml
- **Infrastructure:** infrastructure-provision-cdk-python,
  infrastructure-provision-cdk-typescript, infrastructure-build-ci-cd,
  infrastructure-administer-linux, infrastructure-run-reliable-services
- **Design:** design-software-architecture, design-ui-ux,
  design-secure-applications
- **Quality:** quality-review-code, quality-diagnose-bugs,
  quality-plan-testing, quality-test-python, quality-test-typescript
- **Delivery:** delivery-plan-products, delivery-manage-engineering,
  delivery-coordinate-projects
- **Research:** research-deep-dive, research-brainstorm-ideas,
  research-review-software-legal
- **Writing:** writing-interview-author, writing-draft-chat-messages,
  writing-draft-technical-docs, writing-draft-long-documents,
  writing-draft-blog-posts
- **Workflow:** workflow-commit-and-push, workflow-explain-code,
  workflow-simplify-code, workflow-maintain-spec-anchors

### Claude Desktop bulk upload

All personas are also packaged as one Claude plugin at
`bundles/macols-personas-claude-plugin.zip`. In Claude Desktop, open
**Customize → Plugins → Browse plugins**, then upload that custom plugin file.
One upload installs every persona as a separate skill under the
`macols-personas` plugin.

Whenever a persona changes, rebuild and commit the bundle with it:

```bash
./scripts/package_claude_desktop_personas.sh
```

CI runs the same generator in check mode and fails if the committed ZIP is
missing or stale:

```bash
./scripts/package_claude_desktop_personas.sh --check
```

## MCP servers

The MCP list lives in `shared/mcp-config.json`: **filesystem**, **puppeteer**,
**playwright**, **context7**, **dart**, **aws-mcp** and **aws-iac**. The Claude
Code, Codex and OpenCode installers register them in their own config formats.

- **aws-mcp:** the managed [AWS MCP Server](https://aws.amazon.com/blogs/aws/the-aws-mcp-server-is-now-generally-available/)
  (Agent Toolkit for AWS), reached through the `mcp-proxy-for-aws` package,
  which SigV4-signs requests with your ambient AWS credentials. The endpoint
  is in `us-east-1`. Operations default to your credential chain's region.
- **aws-iac:** the [AWS IaC MCP Server](https://awslabs.github.io/mcp/servers/aws-iac-mcp-server)
  (`awslabs.aws-iac-mcp-server` via uvx): CloudFormation/CDK validation,
  documentation search and best-practice checks. Uses ambient AWS credentials.

## Hooks

The wrappers in `shared/hooks/` run checks without blocking the agent:

- **post-code:** fast lint and type checks after an edit
- **post-task:** the full test and security checks at the end of a turn
- **pre-deploy:** asks for confirmation before `cdk deploy` or `cdk destroy`

`pre_deploy_check.sh` holds the shared matcher. Each tool wires it into its own
hook API.

## Testing

`tests/verify_install.sh <tool>` checks the generated files and asks the CLI to
report its config without logging in. CI runs ShellCheck, installs each tool on
Ubuntu and runs the verifier.

```bash
./tests/verify_install.sh claudecode
```

For repository changes, run the checks that match what you touched:

```bash
bash -n install.sh install_*.sh machine-setup/*.sh
./scripts/package_claude_desktop_personas.sh --check
./scripts/spec_drift_gate.sh --check
./tests/test_spec_drift_gate.sh
```

The root [AGENTS.md](AGENTS.md) tells maintainers and coding agents which source
file owns each part of the setup.

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

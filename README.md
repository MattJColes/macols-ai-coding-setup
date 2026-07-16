# macols-configs

One source of truth for four agentic coding CLIs — **Claude Code**, **Codex**,
**OpenCode** and **Oh My Pi** (`omp`, tool keyword `pi`) — plus the
terminal/dev-environment setup. Personas, steering, MCP servers and check hooks
are authored once under `shared/` and each tool's installer renders them into
that tool's native format, so nothing drifts.

The steering teaches a plain-git workflow — one branch per change, git
worktrees for parallel work — and each installer installs the
[ponytail](https://github.com/DietrichGebert/ponytail) minimal-mode ruleset for
every agent via that agent's native mechanism, plus the
[OpenSpec](https://github.com/Fission-AI/openspec) CLI for spec-driven
development in repos that opt in.

## Structure

```
macols-configs/
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
│   ├── hooks/                     # post-code / post-task / pre-deploy / lgtmaybe + plugins
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

## Install

Each `install_<tool>.sh` is self-contained — it ensures Homebrew (macOS), the
CLI binary and the OpenSpec CLI, then installs that tool's
agents/skills/prompts, steering, MCPs and hooks (every installer also installs
and configures lgtmaybe for its advisory review hook). Run one, several, or all:

```bash
./install.sh                  # all four tools (binaries + configs)
./install.sh claudecode pi    # just Claude Code and Oh My Pi
./install.sh --env            # run the Terminal dev-environment setup first
./install_codex.sh            # one tool directly
```

Useful flags (per installer; run `--help` for the full list):

- `--agents-only` / `--skills-only` / `--prompts-only` / `--mcps-only` / `--hooks-only`
- `--no-cli` — skip the Homebrew/CLI bootstrap, install configs only
- `-p`, `--project` — install into the current project instead of user scope
- `--list` — preview the available personas

### Dev environment

```bash
./install.sh --env            # picks the right Terminal script for your OS
# or directly:
cd Terminal && ./install_macos.sh        # macOS
cd Terminal && ./install_ubuntu26.sh     # Ubuntu 24/26 / WSL2
```

See **[Terminal/README.md](Terminal/README.md)** for the full toolchain
(Python 3.x + uv, Node 22 + TypeScript/CDK, Podman, AWS CLI, LazyVim, etc.).
The Terminal setup also installs **herdr** with the **herdr-plus** and
**herdr-reviewr** plugins: `prefix+p` opens the project picker, `cmd+r` toggles
reviewr, and a wildcard worktree layout opens Claude Code + yazi in every new
worktree (see
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
**Testing:** test-coordinator, python-test-engineer, typescript-test-engineer ·
**DevOps/Reliability:** devops-engineer, sre-reliability, linux-specialist, code-reviewer ·
**Architecture/Design:** architecture-expert, ui-ux-designer ·
**Security:** security-specialist ·
**Management:** documentation-engineer, product-manager, project-coordinator, engineering-manager ·
**Writing:** writing-blog-posts, writing-documents, writing-style ·
**Workflow:** commit (run checks, create a conventional commit and push the branch), ponytail (minimal/YAGNI mode)

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
- **lgtmaybe** (turn end, all tools) — advisory LLM review of uncommitted changes via [lgtmaybe](https://github.com/MattJColes/lgtmaybe); runs after post-task when code changed (Claude/Codex Stop hook, OpenCode `session.idle`, omp `agent_end`). The CLI is installed automatically by every installer, which also prompts for provider/model and persists them as a `LGTMAYBE_CONFIG` block (`LGTMAYBE_PROVIDER` / `LGTMAYBE_MODEL`) in your shell rc — `anthropic` needs `ANTHROPIC_API_KEY`, `bedrock` needs ambient AWS creds with `bedrock:InvokeModel*`. The code-reviewer persona reads the same variables for its automated review pass. Disable the hook with `LGTMAYBE_HOOK_ENABLED=false`.

## Testing

`tests/verify_install.sh <tool>` asserts each tool's files landed in the expected
locations and that the CLI reports a configured state (non-auth introspection).
The **Test installers** GitHub Actions workflow runs `shellcheck` and, on Ubuntu,
installs each tool and runs the verifier across a `claudecode/codex/opencode/pi`
matrix.

```bash
./tests/verify_install.sh claudecode
```

## Post-installation

```bash
aws configure                                   # AWS credentials for aws-* MCPs
podman machine init && podman machine start     # containers (macOS)
claude --version && codex --version             # sanity check
omp --version && lgtmaybe --version             # oh-my-pi + lgtmaybe (auto-installed)
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

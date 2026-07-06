# macols-configs — agent notes

## What this repo is

A *generator*, not a config dump: personas, steering, MCP servers and hooks are
authored once under `shared/` and rendered into each tool's native format by
the four installers (`install_claudecode.sh`, `install_codex.sh`,
`install_opencode.sh`, `install_pi.sh`), all backed by `lib/common.sh`. The
only checked-in `.claude/` content is OpenSpec's opsx commands/skills —
`~/.claude/agents/*` and `~/.claude/skills/*` are generated from
`shared/personas/*/SKILL.md` at install time.

Edit the single source, never the rendered output:

- **Personas** — `shared/personas/<name>/SKILL.md`. Frontmatter drives
  rendering: `agent: true` also emits a Claude/OpenCode agent;
  `user-invocable: true` a Claude skill. One persona file can therefore be
  both the "agent" and the "skill" (e.g. code-reviewer).
- **Steering** — `shared/steering/base.md`, tokenised per tool via
  `shared/steering/tools/<tool>.json`. The `{{EXTRA_SECTION}}` token sits
  glued to the last line of the final section — keep it there when editing.
- **MCP servers** — `shared/mcp-config.json` (filesystem, puppeteer,
  playwright, context7, dart, aws-mcp, aws-iac). Registered for Claude Code,
  Codex and OpenCode; Oh My Pi has no MCP by design.
- **Hooks** — `shared/hooks/*` (post-code, post-task, pre-deploy, lgtmaybe),
  referenced in place, wired by `write_*_hooks` in `lib/common.sh`.
- **Dev environment** — `Terminal/` (macOS + Ubuntu 24/26). The herdr script
  also installs the herdr-plus/herdr-reviewr plugins and their
  Claude+yazi project/worktree layouts.
- **Specs** — this repo dogfoods OpenSpec + spec anchors: living specs in
  `openspec/specs/<capability>/spec.md`, ast-grep anchor rules in
  `specs/anchors/*.yml`, checked by `scripts/spec_drift_gate.sh`. When you
  change anchored code (mostly `lib/common.sh` functions), update the spec
  section in the same change — or say explicitly that behaviour didn't
  change — and re-point the rule if you renamed the function.

## Conventions (follow these in every installer change)

- **Idempotent, always**: `command -v` guards before installs; grep-guarded
  appends for rc/config lines; marker-delimited blocks that are stripped then
  re-added for anything that may change (`PONYTAIL_MARKER_*`,
  `HERDR_AUTOLAUNCH`, `LGTMAYBE_CONFIG`). Re-running any installer must never
  duplicate config.
- **Merge, don't overwrite, user-owned config** (e.g. `~/.config/herdr/config.toml`);
  files this repo fully owns (rendered personas, plugin layouts, yazi configs)
  are written with `cat >`.
- **Optional steps are non-fatal**: `ensure_foo || printf "${YELLOW}⚠ … skipped${NC}\n"`.
- **Portability**: macOS + Ubuntu 24/26. Homebrew on both (linuxbrew is
  bootstrapped by the Terminal setup); `detect_os` branches on `$OSTYPE`.
  Avoid `sed -i` (GNU vs BSD) — filter to a temp file and `mv` back.
- **Version control workflow is plain git + git worktrees.** Jujutsu (jj) was
  removed deliberately — do not reintroduce it in installers, steering or docs.
- **lgtmaybe is advisory-only** — it must never block a hook, review or
  install. Provider/model come from `LGTMAYBE_PROVIDER` / `LGTMAYBE_MODEL`
  (written to shell rc by `configure_lgtmaybe`).
- **OpenSpec is per-repo opt-in** — the installers provision the CLI only;
  never run `openspec init` for the user. (This repo itself *has* opted in.)
- **Spec anchors are per-repo opt-in** — the installers provision the
  ast-grep and yq CLIs only (`ensure_ast_grep`, `ensure_yq`); the steering
  workflow gates on `specs/anchors/*.yml` existing in the target repo. (This
  repo itself has opted in — see the Specs bullet above.)

## Rule: resolve script paths from `${BASH_SOURCE[0]}`, never `$0` after a `cd`

Shell installers here run from various working directories and `cd` around
(e.g. `cd /tmp` before downloading a tarball). Path resolution must not depend
on the current working directory. Set an absolute script dir once at the top
of every installer and derive all sibling/parent paths from it:

```sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # absolute, cwd-independent
CONFIGS_ROOT="$(dirname "$SCRIPT_DIR")"
"$CONFIGS_ROOT/install.sh"
```

Do **not** re-resolve later with `"$(cd "$(dirname "$0")/.." && pwd)"`. `$0` is
relative to the *current* cwd, so after an earlier `cd /tmp` it resolves against
`/tmp`: `dirname` → `/tmp`, `/tmp/..` → `/`, and the path becomes `//install.sh`
(No such file). This exact regression bit `Terminal/install_ubuntu26.sh` — keep
it fixed.

## Verifying changes

```bash
bash -n <script>                 # syntax, every touched script
./tests/verify_install.sh <claudecode|codex|opencode|pi>
./scripts/spec_drift_gate.sh --check   # anchor hygiene (needs ast-grep + yq)
```

CI (`.github/workflows/test-installers`) runs shellcheck, an Ubuntu
install-and-verify matrix across all four tools, and the spec-anchors job
(anchor hygiene + the gate self-test, plus an advisory drift pass on PRs).
For config-merge logic, prove idempotency by running the step twice against
a scratch `$HOME` and asserting the config appears exactly once.

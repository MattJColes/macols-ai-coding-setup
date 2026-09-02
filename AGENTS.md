# macols-ai-coding-setup agent notes

## What this repo is

The source config lives under `shared/`. The five installers render it into the
formats used by Claude Code, Codex, OpenCode, the Pi agents (plain `pi` and
Oh My Pi) and ZCode. Shared rendering and installer functions live in
`lib/common.sh`.

The checked-in `.claude/` directory only contains OpenSpec's opsx commands and
skills. Claude agents and skills are generated from
`shared/personas/*/SKILL.md` during installation.

This repo used to be called `macols-configs`. Keep the old name only where an
installed marker needs it for compatibility.

## Change routing

Start at the source that owns the requested behaviour:

| Change | Source of truth | Primary verification |
|---|---|---|
| Persona, skill or specialist agent | `shared/personas/<name>/SKILL.md` | Persona bundle check + `./tests/verify_install.sh <tool>` |
| Shared agent instructions | `shared/steering/base.md` | render/verify the affected tool |
| Tool-specific steering wording | `shared/steering/tools/<tool>.json` | render/verify that tool |
| MCP registration | `shared/mcp-config.json`, then `lib/common.sh` when wiring changes | installer verifier + relevant spec anchor |
| omp model/provider setup | `configure_omp_models` and friends in `lib/common.sh` | scratch-`$HOME` run of `install_pi.sh --models-only` + installer verifier |
| Lifecycle or quality hook | `shared/hooks/`, `shared/post_*_checks.sh` | targeted hook check + installer verifier |
| Tool installation behaviour | `install_<tool>.sh` and shared helpers in `lib/common.sh` | `bash -n` + installer verifier |
| Full machine setup | `machine-setup/` | syntax check + platform-specific smoke test |

Do not edit generated files under `~/.claude`, `~/.codex`,
`~/.config/opencode`, `~/.pi`, `~/.omp` or `~/.zcode`. Change the source here
and rerun the installer.

Edit the single source, never the rendered output:

- **Personas:** `shared/personas/<name>/SKILL.md`. Frontmatter drives
  rendering: `agent: true` also emits a Claude/OpenCode agent and a Codex
  agent TOML. `user-invocable: true` also emits a Claude skill, so one file can
  provide both forms (e.g. review). Every persona also renders as
  a ZCode Agent Skill and slash command. Persona bodies may inline shared
  partials with `{{include: _shared/<file>.md}}` (renderer inlines them into
  every output; `_`-prefixed dirs hold partials, not personas). After adding, editing,
  renaming or removing a persona, run
  `./scripts/package_claude_desktop_personas.sh` and include the regenerated
  `bundles/macols-personas-claude-plugin.zip` in the same change.
- **Steering:** `shared/steering/base.md`, tokenised per tool via
  `shared/steering/tools/<tool>.json`. The `{{EXTRA_SECTION}}` token sits
  glued to the last line of the final section. Keep it there when editing.
- **Response format:** `shared/steering/response-format.md` is a second
  injected source, not a per-tool var. It fills `{{RESPONSE_FORMAT}}` in
  `base.md`, is appended to every rendered persona by `generate_personas`, and
  is appended to every packaged `SKILL.md` by the Claude Desktop bundle script.
  Edit it once; changing it means regenerating the bundle. It governs chat
  replies only — never widen it to authored content, or it breaks the
  `editor`/`docs`/`messages` personas and the review checklists.
- **MCP servers:** `shared/mcp-config.json` (filesystem, puppeteer,
  playwright, context7, dart, aws-mcp, aws-iac). Registered for Claude Code,
  Codex, OpenCode, Oh My Pi (written to `~/.omp/agent/mcp.json`) and ZCode
  (written to `~/.zcode/cli/config.json`). Plain pi has no MCP support.
  `shared/mcp-config-brave.json` is a second, opt-in source holding
  `brave-search`; only `register_mcps_opencode` and `register_mcps_pi` merge it,
  and only when `~/.config/macols/brave-api-key` holds a key
  (`ensure_brave_api_key` prompts for it, honours `$BRAVE_API_KEY`, writes mode
  600). The key path in that JSON and `BRAVE_KEY_FILE` in `lib/common.sh` must
  stay in sync.
- **omp models:** no file under `shared/` — the config is per-machine, so
  `configure_omp_models` in `lib/common.sh` asks at install time and merges the
  answers into `~/.omp/agent/models.yml` (providers) and
  `~/.omp/agent/config.yml` (`modelRoles.default` / `modelRoles.plan`). Both
  files are user-owned: merge, never overwrite. Keys go to
  `~/.config/macols/omp-<provider>-api-key` mode 600 and are referenced as
  `!cat '<path>'` — never inlined. The YAML readers/writers run on Bun, which
  omp already requires as its runtime. Unattended callers use
  `OMP_MODELS_CONFIG` / `OMP_DEFAULT_MODEL` / `OMP_PLAN_MODEL`.
- **Hooks:** `shared/hooks/*` (post-code, post-task, pre-deploy),
  referenced in place, wired by `write_*_hooks` in `lib/common.sh`.
- **Machine setup:** `machine-setup/` (macOS + Ubuntu 24/26). The herdr script
  also installs the herdr-plus/herdr-reviewr/herdr-browser plugins, their
  Claude+yazi project/worktree layouts, and herdr-browser's prerequisites
  (bun, Chrome/Chromium, `[experimental] kitty_graphics`).
- **Specs:** this repo dogfoods OpenSpec and spec anchors. Living specs are in
  `openspec/specs/<capability>/spec.md`, ast-grep anchor rules in
  `specs/anchors/*.yml` and checked by `scripts/spec_drift_gate.sh`. When
  anchored behaviour changes, update the matching spec section. If code moved
  without changing behaviour, re-point the anchor and say so.

## Conventions (follow these in every installer change)

- **Idempotency:** guard installs with `command -v` and appends with `grep`.
  Strip and re-add marker-delimited blocks that may change
  (`PONYTAIL_MARKER_*`, `HERDR_AUTOLAUNCH`). Re-running an installer must not
  duplicate config.
- **User-owned config:** merge files such as `~/.config/herdr/config.toml`.
  Files fully owned by this repo (rendered personas, plugin layouts, yazi
  configs) can be written with `cat >`.
- **Optional steps are non-fatal**: `ensure_foo || printf "${YELLOW}⚠ … skipped${NC}\n"`.
- **Portability**: macOS + Ubuntu 24/26. Homebrew on both (linuxbrew is
  bootstrapped by the machine setup). `detect_os` branches on `$OSTYPE`.
  Avoid `sed -i` because GNU and BSD differ. Filter to a temp file and `mv` it
  back.
- **Version control workflow is plain git + git worktrees.** Jujutsu (jj) was
  removed. Do not reintroduce it in installers, steering or docs.
- **OpenSpec is per-repo opt-in.** The installers provision the CLI only.
  Never run `openspec init` for the user. This repo has opted in.
- **Spec anchors are per-repo opt-in.** The installers provision the
  ast-grep and yq CLIs only (`ensure_ast_grep`, `ensure_yq`). The steering
  workflow checks for `specs/anchors/*.yml` in the target repo. This repo has
  opted in.

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
(No such file). This broke `machine-setup/install_ubuntu26.sh` before, so keep the
path based on `BASH_SOURCE`.

## Verifying changes

```bash
bash -n <script>                 # syntax, every touched script
./scripts/package_claude_desktop_personas.sh --check
./tests/verify_install.sh <claudecode|codex|opencode|pi|zcode>
./scripts/spec_drift_gate.sh --check   # anchor hygiene (needs ast-grep + yq)
```

CI (`.github/workflows/test-installers`) runs shellcheck, an Ubuntu
install-and-verify matrix across all five tools (ZCode config-only via
`--no-cli`; it is a macOS desktop app), and the spec-anchors job
(anchor hygiene + the gate self-test, plus an advisory drift pass on PRs).
For config-merge logic, prove idempotency by running the step twice against
a scratch `$HOME` and asserting the config appears exactly once.

# CLI Provisioning

## Purpose

Installers idempotently provision the agent CLI plus companion tooling
(Node 24, OpenSpec, ast-grep, yq, hunk, node symlinks). Every install is
`command -v`-guarded so re-runs are no-ops, and optional steps are non-fatal
(`ensure_foo || printf "⚠ … skipped"`).

## Requirements

### Requirement: Node 24 runs every global npm install, into a writable prefix
Every installer's CLI step SHALL call `ensure_node_runtime` before anything
runs `npm install -g`. When the node on PATH is older than Node 24
(`NODE_VERSION`), it SHALL install Node 24 through nvm per-user (installing
nvm first when missing, without sudo), make it nvm's default, and source nvm
from the shell rcs under the `macols: nvm` marker the machine setup also
writes, grep-guarded so neither duplicates it. An nvm Node 24 from an earlier
run SHALL be reused without reinstalling. On success it SHALL re-point the
`~/.local/bin` node/npm/npx links at the active node at once, because later
steps put that directory first on PATH and a link an earlier run left to the
old node would otherwise bring it back. A failure SHALL be non-fatal.
Every global npm install in `lib/` SHALL go through `npm_global_install`,
which installs into npm's own global prefix when the user can write it and
otherwise into `~/.local` (bins in `~/.local/bin`), so a root-owned prefix
such as apt's `/usr/local` never fails with EACCES. It SHALL NOT use sudo or
write `~/.npmrc`.
<!-- anchor: cli-provisioning.node-runtime -->
<!-- anchor: cli-provisioning.npm-global -->

#### Scenario: Ubuntu with apt's Node 18

- **WHEN** an installer runs as a non-root user whose node is apt's v18 with its global prefix in `/usr/local`
- **THEN** Node 24 is installed with nvm, the npm CLIs install under nvm's prefix, and no EACCES error occurs

#### Scenario: Re-run after Node 24 is in place

- **WHEN** an installer runs again in a fresh shell where the old system node is first on PATH
- **THEN** `ensure_node_runtime` switches to nvm's Node 24 without downloading it again, and the rc block appears once

#### Scenario: Links from an earlier run point at the old node

- **WHEN** `~/.local/bin/node` and `npm` link to apt's Node 18 and `~/.local/bin` is first on PATH
- **THEN** after `ensure_node_runtime`, those links point at Node 24, and npm keeps running on Node 24 after a later step prepends `~/.local/bin` again

### Requirement: Each tool's CLI installs through its native channel
`ensure_cli <tool>` SHALL return immediately when the native CLI install is
already present, otherwise install: claude via the official curl installer;
codex via the official standalone installer with brew (macOS) or npm as
fallbacks; opencode via brew, npm, or the curl installer; pi installs both
Pi agents — plain `pi` (`@earendil-works/pi-coding-agent`) and omp (via npm
`--ignore-scripts` after ensuring the bun runtime, upgrading bun and retrying
once if omp fails to run); zcode verifies the ZCode desktop app is present
and warns non-fatally when it isn't (nothing is downloaded — it is a desktop
install, not a package-managed CLI).
<!-- anchor: cli-provisioning.cli -->

#### Scenario: Re-run with CLI present

- **WHEN** `ensure_cli claudecode` runs and `claude` is on PATH
- **THEN** nothing is installed and the function reports success

### Requirement: OpenSpec CLI is provisioned; project setup stays per-repo
`ensure_openspec` SHALL install `@fission-ai/openspec` globally via npm
(Node >= 20.19, which `ensure_node_runtime` guarantees) and verify with `openspec --version`. Installers SHALL NOT
run `openspec init` for the user — adopting the workflow is a per-repo,
human decision (this repo has opted in; see the spec-anchoring capability).
<!-- anchor: cli-provisioning.openspec -->

#### Scenario: OpenSpec already installed

- **WHEN** `openspec` is on PATH
- **THEN** `ensure_openspec` returns success without touching npm

### Requirement: The macols OpenSpec schema is available user-level
`install_openspec_schema` SHALL copy `openspec/schemas/macols` into OpenSpec's
user schema directory (`${XDG_DATA_HOME:-~/.local/share}/openspec/schemas/macols`),
replacing any earlier copy, so any repo can opt in with `schema: macols`. It
SHALL NOT write into a repository or change a repo's `openspec/config.yaml`.
Installers SHALL also link `bin/macols-trust` and `bin/macols-openspec-adopt`
into `~/.local/bin` and keep that directory on PATH. A repo switches only when
the user runs `macols-openspec-adopt`, which pins in-flight changes without a
schema line to `spec-driven` and never runs `openspec init`.
<!-- anchor: cli-provisioning.openspec-schema -->

#### Scenario: A repo opts in without copying files

- **WHEN** a repo's `openspec/config.yaml` says `schema: macols` and it has no `openspec/schemas/`
- **THEN** `openspec schema which macols` resolves from the user directory and a new change has five artifacts

### Requirement: ast-grep is provisioned and guarded on `ast-grep`, never `sg`
`ensure_ast_grep` SHALL install `@ast-grep/cli` globally via npm and verify
with `ast-grep --version`. The presence guard SHALL check `ast-grep`, never
`sg`: Linux ships an unrelated `/usr/sbin/sg` (setgroups) that would
false-positive and skip the install.
<!-- anchor: cli-provisioning.ast-grep -->

#### Scenario: Linux box without ast-grep

- **WHEN** `/usr/sbin/sg` exists but `ast-grep` is not installed
- **THEN** `ensure_ast_grep` still installs the CLI

### Requirement: yq is provisioned for YAML parsing
`ensure_yq` SHALL install yq when missing (brew on macOS, apt on Linux,
matching the jq pattern) so the spec-anchor drift gate can convert sidecar
YAML to JSON. Consumers SHALL tolerate both yq flavors (mikefarah Go yq and
kislyuk jq-wrapper yq).
<!-- anchor: cli-provisioning.yq -->

#### Scenario: yq already present

- **WHEN** any yq flavor is on PATH
- **THEN** `ensure_yq` returns success without installing

### Requirement: The hook batteries' tools are provisioned per language
`ensure_quality_tools` SHALL put on PATH the tools the post-code and post-task
checks fall back to when a project has no local copy: shellcheck and jscpd;
for Python ruff, pyright, mypy, pytest and import-linter as `uv tool`s
(installing uv first when missing); for JS/TS typescript, eslint,
dependency-cruiser, vitest and jest as global npm packages; for Go the Go
toolchain and golangci-lint (Homebrew, else the go.dev tarball under
`~/.local/share/go` and `GOBIN=~/.local/bin go install`); and Flutter, which
provides `dart` (Homebrew cask on macOS, else a shallow stable-channel clone
under `~/.local/share/flutter` linked into `~/.local/bin`). Each install SHALL
be skipped when the binary is already on PATH, and a failed install SHALL be
non-fatal. Every installer SHALL call it in its CLI step. The same functions
SHALL also install the language servers Fresh starts for those languages:
pylsp (`python-lsp-server`, a uv tool), typescript-language-server and
prettier (npm), and gopls (Homebrew, else `go install` into `~/.local/bin`);
Dart's server ships with the Flutter SDK.
<!-- anchor: cli-provisioning.quality-tools -->

#### Scenario: Re-running on a provisioned machine

- **WHEN** every tool is already on PATH
- **THEN** `ensure_quality_tools` installs nothing and returns success

### Requirement: Fresh is provisioned as the terminal IDE
`ensure_fresh` SHALL install Fresh when `fresh` is not on PATH:
`brew install fresh-editor` when Homebrew is available, otherwise upstream's
`scripts/install.sh`, which installs a static binary under `~/.local` and
links `~/.local/bin/fresh` without root. A failed install SHALL be non-fatal.
Every installer SHALL call it in its CLI step, and `machine/Brewfile` SHALL
carry the formula.
<!-- anchor: cli-provisioning.fresh -->

#### Scenario: Fresh already installed

- **WHEN** `fresh` is on PATH
- **THEN** `ensure_fresh` returns success without installing

### Requirement: hunk is provisioned for diff review
`ensure_hunk` SHALL install the hunk binary when it is not on PATH:
`brew install hunk` when Homebrew is available, otherwise the `hunkdiff` npm
package, and warn non-fatally when neither is. `machine/Brewfile` SHALL carry
the formula so the machine setup installs it regardless of tool.
<!-- anchor: cli-provisioning.hunk -->

#### Scenario: hunk already installed

- **WHEN** `hunk` is on PATH
- **THEN** `ensure_hunk` returns success without calling brew or npm

### Requirement: Every agent gets the hunk-review skill, and revdiff is retired
`install_hunk_skill <skills_dir>` SHALL copy the skill printed by
`hunk skill path hunk-review` to `<skills_dir>/hunk-review/SKILL.md` (a copy,
not a symlink, since agents skip symlinked entries when scanning for skills),
and warn non-fatally when hunk is missing. Each installer SHALL call it for its
user-level skills dir after rendering the personas there: Claude Code, Codex,
OpenCode, ZCode, and both `~/.pi/agent/skills` and `~/.omp/agent/skills`.
Project installs SHALL NOT get it (the path is machine-local). Re-runs SHALL
remove the revdiff integrations earlier versions installed (the Claude and
Codex `revdiff@revdiff` plugin and marketplace, OpenCode's copied tool,
command and auto-loaded plan-review plugin with its `opencode.json` entry, the
pi and omp packages) and SHALL NOT touch anything else.
<!-- anchor: cli-provisioning.hunk-skill -->

#### Scenario: Upgrading a machine that had revdiff

- **WHEN** an installer re-runs on a machine where an earlier version installed the revdiff plugin
- **THEN** the revdiff plugin is gone, and the skills dir holds the rendered personas plus `hunk-review/SKILL.md`

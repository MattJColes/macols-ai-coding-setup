# CLI Provisioning

## Purpose

Installers idempotently provision the agent CLI plus companion tooling
(OpenSpec, ast-grep, yq, revdiff, node symlinks). Every install is
`command -v`-guarded so re-runs are no-ops, and optional steps are non-fatal
(`ensure_foo || printf "⚠ … skipped"`).

## Requirements

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
(Node >= 20.19) and verify with `openspec --version`. Installers SHALL NOT
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
non-fatal. Every installer SHALL call it in its CLI step.
<!-- anchor: cli-provisioning.quality-tools -->

#### Scenario: Re-running on a provisioned machine

- **WHEN** every tool is already on PATH
- **THEN** `ensure_quality_tools` installs nothing and returns success

### Requirement: revdiff is provisioned with each tool's upstream plugin
`ensure_revdiff` SHALL install the revdiff binary with
`brew install umputun/apps/revdiff` when it is not on PATH, and warn
non-fatally when Homebrew is missing. The Claude Code, Codex, OpenCode and Pi
installers SHALL then add upstream's diff-review integration for their tool
(Claude and Codex marketplace plugin `revdiff@revdiff`, OpenCode's
`plugins/opencode/setup.sh`, the pi package for both `pi` and `omp`). The
auto-firing `revdiff-planning` plugin SHALL NOT be installed for Claude Code or
Codex. Re-runs SHALL NOT duplicate any of it. `machine/Brewfile` SHALL carry
the formula so the machine setup installs it regardless of tool.
<!-- anchor: cli-provisioning.revdiff -->

#### Scenario: revdiff already installed

- **WHEN** `revdiff` is on PATH
- **THEN** `ensure_revdiff` returns success without calling brew

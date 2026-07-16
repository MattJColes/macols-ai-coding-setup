# CLI Provisioning

## Purpose

Installers idempotently provision the agent CLI plus companion tooling
(OpenSpec, ast-grep, yq, node symlinks). Every install is
`command -v`-guarded so re-runs are no-ops, and optional steps are non-fatal
(`ensure_foo || printf "⚠ … skipped"`).

## Requirements

### Requirement: Each tool's CLI installs through its native channel
`ensure_cli <tool>` SHALL return immediately when the native CLI install is
already present, otherwise install: claude via the official curl installer;
codex via the official standalone installer with brew (macOS) or npm as
fallbacks; opencode via brew, npm, or the curl installer; pi (omp) via npm
`--ignore-scripts` after ensuring the bun runtime, upgrading bun and retrying
once if omp fails to run.
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

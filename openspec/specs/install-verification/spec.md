# Install Verification

## Purpose

`tests/verify_install.sh <tool>` proves an install worked. Hard checks
(rendered files, persisted config) fail the run; soft checks
(network/auth-dependent introspection like CLI versions or `mcp list`) only
warn. CI runs shellcheck plus an Ubuntu install-and-verify matrix across all
four tools.

## Requirements

### Requirement: Hard checks fail the run, soft checks only warn

The verifier SHALL exit non-zero when any hard check fails (rendered
agents/skills present, steering title rendered, hooks wired, exactly one
ponytail block for AGENTS.md tools) and SHALL exit zero when only soft checks
fail (CLI versions, openspec/ast-grep/yq/lgtmaybe presence, MCP listing).

#### Scenario: Offline verification

- **WHEN** the network is unavailable but all rendered files are in place
- **THEN** the verifier reports soft warnings and exits zero

### Requirement: CI installs and verifies every tool on Ubuntu

The `test-installers` workflow SHALL shellcheck every shell script and run
each installer followed by its verifier in a matrix across
claudecode/codex/opencode/pi on Ubuntu.

#### Scenario: Installer regression

- **WHEN** a change breaks an installer's rendered output
- **THEN** the matrix job for that tool fails on the hard check

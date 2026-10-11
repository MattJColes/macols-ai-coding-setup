# Spec Delta

## ADDED Requirements

### Requirement: Codex and OpenCode install the upstream ponytail plugin
The Codex installer SHALL install the upstream `ponytail@ponytail` plugin. The OpenCode installer SHALL merge `@dietrichgebert/ponytail` into the `plugin` array of `~/.config/opencode/opencode.json`, keeping every other key and entry. A failed plugin install SHALL warn and let the install carry on.

#### Scenario: Plugin installed
- **WHEN** `./install.sh codex` runs with `codex` on PATH, or `./install.sh opencode` runs
- **THEN** the plugin is recorded in that tool's config

#### Scenario: Re-running with the plugin
- **WHEN** either installer runs twice
- **THEN** the plugin is recorded once and the user's other `opencode.json` plugin entries survive

### Requirement: The ruleset block is the fallback when the plugin is absent
When the Codex or OpenCode plugin is present, the freshly assembled user-level AGENTS.md SHALL carry no ponytail marker block. When it is absent, the installer SHALL append the block with `append_ponytail_ruleset`. ZCode and project-mode AGENTS.md files SHALL keep the block.

#### Scenario: Plugin present
- **WHEN** the Codex or OpenCode installer finishes with its plugin recorded
- **THEN** that tool's user-level AGENTS.md contains no ponytail marker block

#### Scenario: Plugin unavailable
- **WHEN** `./install.sh codex --no-cli` runs with no `codex` binary
- **THEN** the installer warns and `~/.codex/AGENTS.md` contains exactly one ponytail marker block

#### Scenario: Upgrading a block-based install
- **WHEN** an install that carries the block re-runs with the plugin now available
- **THEN** the block is gone from the user-level AGENTS.md and the plugin is recorded

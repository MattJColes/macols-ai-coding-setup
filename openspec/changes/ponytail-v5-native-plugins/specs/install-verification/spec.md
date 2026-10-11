# Spec Delta

## MODIFIED Requirements

### Requirement: Hard checks fail the run, soft checks only warn

The verifier SHALL exit non-zero when any hard check fails (rendered
agents/skills present, steering title rendered, hooks wired, ponytail
delivered exactly once — one AGENTS.md block for ZCode, and for Codex and
OpenCode either their plugin with no block or, without the plugin, one block —
and the persona contract: skills carry
their `references/`, no rendered file carries `tier:`, tiers render as Claude
`effort` / Codex `model_reasoning_effort` on `audit`, and no retired persona
such as `review` or `debug` remains) and SHALL exit zero when only soft checks
fail (CLI versions, openspec/ast-grep/yq presence, MCP listing, whether the
Codex and OpenCode ponytail plugins are installed).

#### Scenario: Offline verification

- **WHEN** the network is unavailable but all rendered files are in place
- **THEN** the verifier reports soft warnings and exits zero

#### Scenario: Ponytail delivered twice

- **WHEN** the Codex or OpenCode plugin is present and the user-level AGENTS.md also carries a ponytail block
- **THEN** the verifier fails the hard check

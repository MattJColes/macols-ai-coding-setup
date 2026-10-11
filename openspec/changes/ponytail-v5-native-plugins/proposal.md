# Proposal

## Why

Ponytail 5 rebuilt its ruleset and ships native integrations for Codex (a plugin with lifecycle hooks and the review/audit skills) and OpenCode (an npm plugin). Codex and OpenCode still get our pre-v5 vendored copy pasted into AGENTS.md, so they follow older rules than Claude Code and pi (they write `ponytail:` comments instead of `shortcut:`, and skip the v5 scope check) and never get `/ponytail-review`, `/ponytail-audit` or `/ponytail-debt`.

## What Changes

- Codex installs the upstream `ponytail@ponytail` plugin (`codex plugin marketplace add` + `codex plugin add`).
- OpenCode lists `@dietrichgebert/ponytail` in the `plugin` array of `~/.config/opencode/opencode.json` (merged; OpenCode 1 installs it on launch).
- Their user-level AGENTS.md drops the ruleset block when the plugin is present, and keeps it as the fallback when the plugin is absent, so the rules still load exactly once.
- `config/steering/ponytail.AGENTS.md` is re-vendored from upstream v5.1.0 for ZCode (which upstream no longer supports), the fallback and project-mode AGENTS.md files.
- The verifier accepts either delivery path for Codex and OpenCode but still requires exactly one.
- Claude Code, pi and omp are unchanged: they already load v5 from upstream.

## Capabilities

### New Capabilities

### Modified Capabilities
- `steering-assembly`: Codex and OpenCode take ponytail from their plugin and fall back to the ruleset block.
- `install-verification`: the "exactly one ponytail" hard check counts the plugin as a delivery path for Codex and OpenCode.

## Impact

Codex and OpenCode installs gain a plugin and lose the AGENTS.md block on re-run. Codex runs the plugin's hooks only after the user trusts them in `/hooks`, the same manual step the macols hooks already need; until then Codex gets the skills but not the always-on ruleset.

## Scope

### May change
- `lib/steering.sh`: `install_codex_ponytail`, `install_opencode_ponytail`, `ponytail_plugin_present`, `ponytail_ruleset_unless_plugin`; comments.
- `lib/common.sh`: `PONYTAIL_NPM` and the ponytail comment.
- `installers/codex.sh`, `installers/opencode.sh`: wire the plugin step before AGENTS.md is written; next-step lines.
- `config/steering/ponytail.AGENTS.md`: re-vendor from upstream v5.1.0.
- `tests/verify_install.sh`: Codex and OpenCode ponytail checks.
- `docs/personas.md`: the Ponytail section.
- This change directory.

### Must not change
- `append_ponytail_ruleset` and the marker strings: ZCode, project mode and the fallback still use them, and the anchor `steering-assembly.ponytail-append` points at the function.
- `installers/claudecode.sh`, `installers/pi.sh`, `installers/zcode.sh`: their ponytail delivery already matches upstream v5.
- Other keys and `plugin` entries in a user's `opencode.json`.
- The macols Codex hooks in `~/.codex/hooks.json` and their trust state.
- Living spec prose: proposed deltas only.

## Constraints

- `C-INSTALL-IDEMPOTENT`: plugin installs and the `opencode.json` merge must be no-ops on re-run; the block stays marker-delimited.
- `C-MERGE-USER-CONFIG`: `opencode.json` is user-owned, so the plugin entry is merged into it.
- `C-OPTIONAL-NON-FATAL`: a failed plugin install warns and falls back to the block.
- `C-PORTABLE-SHELL`: helpers use `grep -F` and node, no `sed -i`.
- `C-SHELLCHECK-CLEAN`: every touched script.
- `C-SPEC-ANCHORS-HEALTHY`: `steering-assembly.ponytail-append` must still resolve.
- Ponytail reaches each tool exactly once, whichever delivery path wins.

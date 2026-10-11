# Design

## Context

Each tool gets ponytail once through its native mechanism. Before Ponytail 5, Codex and OpenCode had no usable native path, so they got a vendored copy of upstream's AGENTS.md in a marker block. v5 ships a Codex plugin (`.codex-plugin/`, two lifecycle hooks plus six skills) and an npm package that OpenCode loads as a plugin.

## Goals / Non-Goals

Goal: Codex and OpenCode run the same v5 rules as Claude Code and pi, with the review, audit and debt commands, and still load the rules exactly once.

Non-goals: changing Claude Code, pi or omp delivery; changing the macols Codex hooks or their trust flow; resolving the overlap between `/ponytail-review` and the `audit` persona (both stay); reconciling ponytail's "end with what you skipped" line with rule 10 of `response-format.md` (Claude Code already runs both).

## Decisions

- **Plugin first, block as fallback.** `ponytail_ruleset_unless_plugin` checks the tool's config for the plugin after the plugin step has run and appends the block only when it is missing. A missing `codex` binary, an offline clone or `--no-cli` therefore still leaves the rules in place. `assemble_steering` rewrites AGENTS.md from scratch, so an upgrade drops the old block with no extra migration.
- **OpenCode via `opencode.json`, not `opencode plugin add`.** The npm release is OpenCode 1.19, which has no `plugin add` and reads the `plugin` key. Merging the entry with node keeps the file user-owned and needs no OpenCode binary; OpenCode installs the package on launch (checked with `opencode debug config`, which lists the six `/ponytail*` commands).
- **Presence, not enabled state.** `ponytail_plugin_present` matches the plugin's table or entry, not `enabled = true`. A user who disables the Codex plugin has opted out, and the installer should not force the rules back in through AGENTS.md.
- **omp unchanged.** `omp install` is an alias of `omp plugin install`, which is what upstream documents, and omp runs the pi extension as is.

## Risks / Trade-offs

- Codex runs plugin hooks only after the user trusts them in `/hooks`. Until then Codex has the skills but no always-on ruleset. The macols hooks already need the same step, and the installer prints the reminder only when the plugin is present.
- The OpenCode plugin installs on first launch, so a machine that is offline at launch runs without ponytail until it can reach npm. This is the trade-off for not shelling out to npm during install.
- The block no longer gets exercised for Codex/OpenCode in CI when the plugin installs; the Codex `--no-cli` fallback run in evidence covers it, and ZCode keeps it covered in the CI matrix.

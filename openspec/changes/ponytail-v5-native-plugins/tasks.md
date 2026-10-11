# Tasks

## 1. Delivery

- [x] 1.1 Re-vendor `config/steering/ponytail.AGENTS.md` from upstream v5.1.0.
- [x] 1.2 Add `install_codex_ponytail` and `install_opencode_ponytail`, and wire them before AGENTS.md is written.
- [x] 1.3 Add `ponytail_plugin_present` / `ponytail_ruleset_unless_plugin` so the block is only the fallback.

## 2. Verification

- [x] 2.1 Accept either delivery path for Codex and OpenCode in `tests/verify_install.sh`, still exactly once.
- [x] 2.2 Run E1-E6 against scratch homes and record results.

## 3. Docs and specs

- [x] 3.1 Update the Ponytail section of `docs/personas.md`.
- [ ] 3.2 On archive: apply the deltas to `openspec/specs/steering-assembly` (including its Purpose paragraph) and `install-verification`, and anchor the fallback requirement to `ponytail_ruleset_unless_plugin`.

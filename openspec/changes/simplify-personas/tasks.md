# Tasks

## 1. Renderer + shared partial

- [x] Add `{{include: _shared/<file>.md}}` inlining to `PERSONA_GEN_JS` in
      `lib/common.sh` (missing include fails the render)
- [x] Skip `_`-prefixed persona dirs and inline includes in
      `scripts/package_claude_desktop_personas.sh`
- [x] Create `shared/personas/_shared/voice.md` (voice rules, words-to-kill,
      AI tells, read-back test)
- [x] Rewrite `blog`, `docs`, `messages`, `explain` on top of the partial

## 2. Merges, removals, slimming

- [x] Merge the CDK pair into `cdk` (shared patterns, paired Python/TS blocks)
- [x] Merge the test trio into `test` (shared philosophy + per-language
      sections; drop plan-testing boilerplate)
- [x] Fold `design-secure-applications` into `review` as Security Audit mode
- [x] Fold `writing-draft-technical-docs` templates into `docs`
- [x] Move the decision-log template into `product`; remove
      `delivery-manage-engineering` and `research-review-software-legal`
- [x] Slim `linux` to house conventions
- [x] Rewrite `coordinate`'s delegation table for the 25-persona roster

## 3. Renames + sweep

- [x] `git mv` all persona dirs to short prefixless names; update frontmatter
      (incl. `agent: true` removal for the interactive family, normalized
      `allowed-tools`/`user-invocable`)
- [x] Update cross-persona handoffs and descriptions
- [x] Update `shared/steering/tools/*.json` examples
- [x] Update `README.md`, `AGENTS.md`, installer next-steps echoes,
      `tests/verify_install.sh` (`review.toml`), `lib/common.sh` comment
- [x] Refresh `openspec/specs/persona-rendering/spec.md` (stale examples,
      include requirement)

## 4. Verification

- [x] Rebuild `bundles/macols-personas-claude-plugin.zip`; `--check` passes
- [x] `bash -n` on touched scripts; shellcheck clean
- [x] All four installers run clean against the real `$HOME` (`--no-cli`);
      idempotent on a second run; `tests/verify_install.sh` passes for all
      four tools
- [x] Grep for every old persona name: zero hits outside `openspec/changes/`

## Why

The 32 personas accumulated near-duplicates (the CDK pair were explicit mirrors,
the writing family copied the same voice/AI-tell lists, the test trio split one
job three ways) and the domain-verb-noun names from
`rename-personas-for-discovery` read as bureaucratic — `infrastructure-provision-cdk-typescript`
is 38 characters before you've said anything. Aggregating to 25 short,
prefixless names removes the duplication and makes every invocation a word you
would actually type.

## What Changes

- **Rename all 25 remaining personas to short, prefixless names**
  (`cdk`, `review`, `debug`, `test`, `ponytail`, `ship`, `blog`, `docs`, ...).
  No aliases are kept — same policy as the previous rename.
- **Merge:** the two CDK personas into one `cdk` (shared patterns, paired
  Python/TS code); the three testing personas into one `test` (shared
  philosophy + per-language sections); `writing-draft-technical-docs` into
  `docs`; the security audit persona into `review` as a Security Audit mode.
- **Remove:** `research-review-software-legal` (legal review rarely invoked);
  `delivery-manage-engineering` (agile-ceremony content; its decision-log
  template moves into `product`).
- **Slim** `linux` to house conventions (script template, git/worktree
  workflow, Podman/jq preferences), dropping generic bash/systemd/SSH teaching.
- **Skills-only** for the interactive/writing family (`blog`, `docs`,
  `messages`, `interview`, `explain`, `brainstorm`) — they drop `agent: true`
  and stop rendering as subagents; 16 of 25 personas remain agents.
- **Shared voice partial:** the near-verbatim voice rules, words-to-kill table
  and AI-tell lists duplicated across `blog`/`docs`/`messages`/`explain` move
  to `shared/personas/_shared/voice.md`, inlined at render time by a new
  `{{include: _shared/<file>.md}}` marker in the generator (and the Claude
  Desktop packaging script).
- Update all cross-persona handoffs, steering examples, README/AGENTS docs,
  installer next-steps echoes, `verify_install.sh`, and the living
  `persona-rendering` spec.
- **BREAKING**: remove the old slash-command and agent names. Re-running an
  installer replaces the generated persona directories, so only the new names
  remain.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `persona-rendering`: add the shared-partial include mechanism; refresh
  stale scenario examples.

## Impact

- All `shared/personas/*` source directories and their `name` frontmatter.
- `shared/personas/_shared/` (new, partials not personas).
- `lib/common.sh` (generator include preprocessing) and
  `scripts/package_claude_desktop_personas.sh` (include inlining, `_` skip).
- Cross-persona references, `shared/steering/tools/*.json` examples,
  `README.md`, `AGENTS.md`, `tests/verify_install.sh`,
  `openspec/specs/persona-rendering/spec.md`.
- `bundles/macols-personas-claude-plugin.zip` regenerated.
- Installed skills/agents for Claude Code, Codex, OpenCode, and Pi after the
  installers are re-run.

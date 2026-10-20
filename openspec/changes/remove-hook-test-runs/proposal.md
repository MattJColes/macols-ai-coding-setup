## Why
Automatic tests can take minutes in large repos and delay every agent reply. Test execution belongs to each repo's chosen pre-commit workflow.

## What Changes
- Remove built-in Python, Node, Flutter and Go test execution from turn-end and commit batteries.
- Keep lint, types, structure checks, CDK synthesis, AI review and explicitly configured project commands.

## Capabilities
### New Capabilities
None.
### Modified Capabilities
- `hook-wiring`: batteries validate code without automatically running tests.

## Impact
Shared batteries affect every installed agent in place. Repos can explicitly configure CHECKPOINT commands for tests.

## Scope
### May change
- `hooks/checks/post_task.sh`, `hooks/checks/lang_checks.sh`, `hooks/post_task_hook.sh`, `hooks/pre_commit_check.sh`
- `tests/test_hook_loops.sh`, `docs/hooks.md`, `config/personas/quality/references/checks.conf`
- `openspec/changes/remove-hook-test-runs/**`
- `dist/macols-personas-claude-plugin.zip`: regenerate the bundled quality template.
### Must not change
- Installer wiring, trust gates, per-edit checks, user-owned configuration and unrelated plugins.

## Constraints
- C-EDIT-SOURCE-NOT-OUTPUT: hooks run from this source checkout.
- C-TRUSTED-REPO-CODE: explicit project commands retain trust checks.
- C-HOOKS-MODEL-VISIBLE: preserve finding delivery.
- C-SHELLCHECK-CLEAN: verify touched shell scripts.
- C-SPEC-ANCHORS-HEALTHY: keep anchors resolving and propose specification deltas.
- No new opt-in setting: automatic tests are removed for all repos.

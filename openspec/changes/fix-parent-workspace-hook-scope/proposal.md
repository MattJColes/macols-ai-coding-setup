# Proposal

## Why

A Codex session opened at a parent workspace runs turn-end checks across unrelated sibling repositories. Those pre-existing findings are presented as changes from this task.

## What Changes

- Require Git membership or a project manifest in the current directory before the autonomous battery runs.
- Preserve explicitly declared standalone projects and normal repository checks.
- Fix macOS physical-path selection, bounded review execution, checkpoint retries and existing-key permissions found during installer testing.

## Capabilities

### Modified Capabilities
- `hook-wiring`: bound autonomous discovery to an identified project.

## Impact

Shared check helpers, review/key setup and installer verification; provision coreutils for a hard review timeout on macOS.

## Scope

### May change
- `hooks/checks/common.sh`: project boundaries and physical working directory.
- `hooks/pre_commit_check.sh`, `hooks/checks/lgtmaybe_review.sh`: checkpoint cache and bounded review.
- `lib/lgtmaybe.sh`, `lib/quality-tools.sh`: key setup and timeout provisioning.
- `tests/test_lgtmaybe_review.sh`, `tests/verify_install.sh`: installer and review regressions and managed-skill exclusions.
- `tests/test_hook_loops.sh`: boundary regression checks.
- `.github/workflows/test-installers.yml`: run the offline review regressions in CI.
- This change directory: proposal, delta, design, tasks and evidence.

### Must not change
- Sibling projects and their lint configuration.
- Hook output schemas and trust decisions.
- Living spec prose: provide a proposed delta only.

## Constraints

- `C-EDIT-SOURCE-NOT-OUTPUT`: the installed hook references source in place.
- `C-PORTABLE-SHELL`: the guard must work with macOS Bash and Linux Bash.
- `C-SHELLCHECK-CLEAN`: verify both touched shell files.
- `C-SPEC-ANCHORS-HEALTHY`: shared helpers carry existing anchors.
- `C-HOOKS-MODEL-VISIBLE`: eligible project findings must still reach the agent.
- `C-TRUSTED-REPO-CODE`: retain the existing trust gate.

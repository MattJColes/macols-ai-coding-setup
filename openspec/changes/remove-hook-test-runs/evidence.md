# Evidence

## E1. No automatic tests; static checks and configured commands survive
- **Claim**: Both batteries skip built-in tests, including legacy full-scope settings; Go lint and explicit checkpoint failures remain effective. Trust gates and model-visible findings survive.
- **Command**: `bash tests/test_hook_loops.sh`
- **Expected**: All assertions pass using scratch repos and boundary stubs.
- **Fails before**: The new battery regression detects automatic test dispatch; Go assertions detect go test.
- **Recorded**: pass, 41/41 assertions; base HEAD 95a50bdf609186b7b0014593bdff3c24bfcdeca3, working-tree changes tested (2026-10-20).

## E2. Shell and anchor constraints
- **Claim**: C-SHELLCHECK-CLEAN, C-SPEC-ANCHORS-HEALTHY and source-only changes hold.
- **Command**: `bash -n hooks/checks/post_task.sh hooks/checks/lang_checks.sh hooks/post_task_hook.sh hooks/pre_commit_check.sh tests/test_hook_loops.sh && shellcheck -S warning hooks/checks/post_task.sh hooks/checks/lang_checks.sh hooks/post_task_hook.sh hooks/pre_commit_check.sh tests/test_hook_loops.sh && ./scripts/spec_drift_gate.sh --check`
- **Expected**: All commands pass; installer and per-edit code unchanged.
- **Recorded**: pass; base HEAD 95a50bdf609186b7b0014593bdff3c24bfcdeca3, working-tree changes tested (2026-10-20).

## E3. Installer, bundle and change validation
- **Claim**: Codex wiring remains valid, the quality template is bundled, and spec deltas validate.
- **Command**: `./tests/verify_install.sh codex && ./scripts/package_claude_desktop_personas.sh --check && openspec validate remove-hook-test-runs --strict && git diff --check`
- **Expected**: All hard checks pass.
- **Recorded**: pass; base HEAD 95a50bdf609186b7b0014593bdff3c24bfcdeca3, working-tree changes tested (2026-10-20). Other agents' installer verifiers were not run; shared hook wiring is unchanged.

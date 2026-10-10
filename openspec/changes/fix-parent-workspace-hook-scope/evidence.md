# Evidence

## E1. Scope and eligible projects
- **Claim**: the actual Stop hook skips an unmarked workspace, while standalone manifests and Git repositories remain eligible.
- **Command**: `MACOLS_LGREVIEW=off TMPDIR=/private/tmp bash tests/test_hook_loops.sh`
- **Expected**: workspace integration regression plus existing hook-loop checks pass.
- **Fails before**: the workspace integration regression reports sibling lint findings.
- **Recorded**: pass: 38/38 hook-loop assertions; all three boundary regressions pass. Base HEAD fbb38741914d1fd740ba0584df4c2b0debedd46e; uncommitted source diff SHA-256 fe3b52bfdfc39cee19d507915d0917ed2b358444493e1077db8bb99d00f5ab40.

## E2. Portable syntax and anchors
- **Claim**: the source change preserves portable syntax and all existing anchor sites.
- **Command**: `bash -n hooks/checks/common.sh tests/test_hook_loops.sh`; `shellcheck -P SCRIPTDIR -x hooks/checks/common.sh tests/test_hook_loops.sh`; `./scripts/spec_drift_gate.sh --check`
- **Expected**: zero syntax/lint errors; every existing anchor resolves exactly once.
- **Recorded**: pass: syntax and Shellcheck (source-aware -P SCRIPTDIR -x) clean; 45/45 anchors resolve; git diff --check clean. Base HEAD fbb38741914d1fd740ba0584df4c2b0debedd46e; uncommitted source diff SHA-256 fe3b52bfdfc39cee19d507915d0917ed2b358444493e1077db8bb99d00f5ab40.

## E3. Original entry point
- **Claim**: the installed Codex Stop hook returns no sibling findings from Development.
- **Command**: `printf '{"cwd":"/Users/mattcoles/Development","stop_hook_active":false}' | hooks/post_task_hook.sh --format codex`
- **Expected**: empty output, exit zero; eligible-project model feedback remains exercised by E1.
- **Recorded**: pass: installed Stop replay at Development exits 0 with empty stdout/stderr. Base HEAD fbb38741914d1fd740ba0584df4c2b0debedd46e; uncommitted source diff SHA-256 fe3b52bfdfc39cee19d507915d0917ed2b358444493e1077db8bb99d00f5ab40.

## E4. macOS installation and review retries
- **Claim**: the installer reuses existing keys securely, temporary-directory paths select the correct tests, and skipped reviews do not poison checkpoint retries.
- **Commands**: `./install.sh codex --no-cli`; `bash tests/verify_install.sh codex`; `bash tests/test_lgtmaybe_review.sh`; `bash tests/test_scoped_pytest.sh`; `MACOLS_LGREVIEW=off bash tests/test_hook_loops.sh`.
- **Recorded**: all pass on the existing Apple Silicon Mac with default macOS TMPDIR. Review tests cover hard timeout, missing timeout, unavailable/restored reviewer on an unchanged tree, reenabled review, mode-600 key reuse/rotation and interactive blank opt-out. The fixture sources every split check module without missing-source errors. All 45 anchors and warning-level ShellCheck pass. These are local results; hosted CI must run on the pushed revision separately.
- **Prior live integration**: native Codex repaired a failing Node test after Stop feedback, denied an unsafe commit after a live GLM critical finding, and allowed a repaired checkpoint. Installer/key regressions use dummy keys and stub only external tools; no secret is committed.

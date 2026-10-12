# Evidence

Commands run from the repository root. Results will be recorded with the implementation commit SHA.

## E1. Migration and preservation

- **Claim**: Both retired IDs migrate, reasoning suffixes and unrelated configuration survive, reruns converge, fresh setup succeeds, and invalid configuration remains untouched.
- **Command**: `./tests/test_pi_lan_models.sh`
- **Expected**: Pass using the real installer entry point in scratch homes.
- **Fails before**: The previous installer retains the Swift 1.0 selection and lacks Swift 1.5.
- **Recorded**: _not yet run_

## E2. Shell and anchors

- **Claim**: Edited scripts parse and lint cleanly and existing anchors still resolve.
- **Command**: `bash -n lib/omp-models.sh tests/test_pi_lan_models.sh tests/verify_install.sh && shellcheck -S warning -x lib/omp-models.sh tests/test_pi_lan_models.sh tests/verify_install.sh && ./scripts/spec_drift_gate.sh --check && ./scripts/package_claude_desktop_personas.sh --check`
- **Expected**: Success; 45/45 anchors healthy and unchanged persona bundle matches source.
- **Recorded**: _not yet run_

## E3. Endpoint discovery and inference

- **Claim**: Exodus serves the exact configured model and accepts a completion.
- **Command**: `curl --connect-timeout 5 --max-time 15 -fsS http://exodus:8000/v1/models && curl --connect-timeout 5 --max-time 60 -fsS http://exodus:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"ukisai/Swift-1.5-Qwen3.8-27b-NVFP4","messages":[{"role":"user","content":"Reply with SWIFT_OK only."}],"max_tokens":64,"chat_template_kwargs":{"enable_thinking":false}}'`
- **Expected**: Discovery includes the exact ID and context length; completion returns `SWIFT_OK`.
- **Recorded**: _not yet run_

## E4. Installer verification

- **Claim**: Generated pi/omp configuration satisfies the installer verifier on Ubuntu.
- **Command**: `./install.sh pi && ./tests/verify_install.sh pi`
- **Expected**: All hard assertions pass in the hosted pi installer job.
- **Recorded**: _not yet run_

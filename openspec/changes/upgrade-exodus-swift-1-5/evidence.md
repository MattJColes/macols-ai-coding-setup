# Evidence

Commands run from the repository root. Results will be recorded with the implementation commit SHA.

## E1. Migration and preservation

- **Claim**: Both retired IDs migrate, reasoning suffixes and unrelated configuration survive, reruns converge, fresh setup succeeds, and invalid configuration remains untouched.
- **Command**: `./tests/test_pi_lan_models.sh`
- **Expected**: Pass using the real installer entry point in scratch homes.
- **Fails before**: The previous installer retains the Swift 1.0 selection and lacks Swift 1.5.
- **Recorded**: pass at `52a58811d1486072ae8a41a82c0bfb946b841b8e`: 2/2 predecessor selections migrated through `./install.sh pi --models-only`, suffixes and unrelated settings preserved, repeated installs identical, malformed files unchanged and skip flags respected.

## E2. Shell and anchors

- **Claim**: Edited scripts parse and lint cleanly and existing anchors still resolve.
- **Command**: `bash -n lib/omp-models.sh tests/test_pi_lan_models.sh tests/verify_install.sh installers/pi.sh scripts/install_swift_pi.sh && shellcheck -S warning -x install.sh installers/*.sh lib/*.sh tests/*.sh hooks/*.sh hooks/checks/*.sh hooks/adapters/*.sh bin/*.sh scripts/*.sh && ./scripts/spec_drift_gate.sh --check && ./scripts/package_claude_desktop_personas.sh --check`
- **Expected**: Success; 45/45 anchors healthy and unchanged persona bundle matches source.
- **Recorded**: pass at `52a58811d1486072ae8a41a82c0bfb946b841b8e`: syntax, full CI shellcheck command, 45/45 anchors and bundle check passed. `openspec validate upgrade-exodus-swift-1-5 --strict` also passed. Focused audit found no actionable findings.

## E3. Endpoint discovery and inference

- **Claim**: Exodus serves the exact configured model and accepts a completion.
- **Command**: `curl --connect-timeout 5 --max-time 15 -fsS http://exodus:8000/v1/models && curl --connect-timeout 5 --max-time 60 -fsS http://exodus:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"ukisai/Swift-1.5-Qwen3.8-27b-NVFP4","messages":[{"role":"user","content":"Reply with SWIFT_OK only."}],"max_tokens":64,"chat_template_kwargs":{"enable_thinking":false}}'`
- **Expected**: Discovery includes the exact ID and context length; completion returns `SWIFT_OK`.
- **Recorded**: pass at `52a58811d1486072ae8a41a82c0bfb946b841b8e`: discovery returned the exact ID and 262144 context; live completion returned `SWIFT_OK`.

## E4. Installer verification

- **Claim**: Generated pi/omp configuration satisfies the installer verifier on Ubuntu.
- **Command**: `./install.sh pi && ./tests/verify_install.sh pi`
- **Expected**: All hard assertions pass in the hosted pi installer job.
- **Recorded**: _not yet run_

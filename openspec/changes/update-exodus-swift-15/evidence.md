## E1. Installer migration and boundaries

- **Claim**: Both agents migrate retired selections, preserve unrelated configuration, fail visibly on malformed input and converge on reruns.
- **Command**: `bash tests/test_pi_lan_models.sh` (runs the real model-only installer in scratch homes).
- **Expected**: Both retired IDs pass all migration, suffix, idempotency and preservation assertions.
- **Recorded**: pass: both retired IDs migrated in both agents; suffixed role, unrelated settings, repeated install and malformed-input assertions passed. Regression failed on the old implementation because the new ID was absent.

## E2. Shell and anchors

- **Claim**: Touched scripts remain valid and anchored code still resolves.
- **Command**: `bash -n lib/omp-models.sh installers/pi.sh scripts/install_swift_pi.sh tests/test_pi_lan_models.sh tests/verify_install.sh`; `shellcheck -S warning -x lib/omp-models.sh installers/pi.sh scripts/install_swift_pi.sh tests/test_pi_lan_models.sh tests/verify_install.sh`; `./scripts/spec_drift_gate.sh --check`.
- **Expected**: All scripts pass and every anchor resolves once.
- **Recorded**: pass: 5/5 Bash syntax checks and warning-severity ShellCheck checks; 45/45 anchors resolve once. Full ShellCheck also passes for the shared writer and migration test.

## E3. Live inference

- **Claim**: Exodus accepts the exact new model ID.
- **Command**: `curl --fail --silent --show-error --connect-timeout 5 --max-time 60 http://exodus:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"ukisai/Swift-1.5-Qwen3.8-27b-NVFP4","messages":[{"role":"user","content":"Reply with SWIFT15_OK only"}],"max_tokens":512,"chat_template_kwargs":{"enable_thinking":false}}'`.
- **Expected**: HTTP success, new model ID and `SWIFT15_OK` content.
- **Recorded**: pass: HTTP success, exact Swift 1.5 model ID and SWIFT15_OK returned.

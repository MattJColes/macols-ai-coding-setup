## 1. Provider registration

- [x] 1.1 Verify pi and omp native model schemas and command key references using installed sources or official documentation; record the supported fields in design.md.
- [x] 1.2 Implement automatic registration and exact old-model migration in `lib/common.sh`; verify merging, malformed-file preservation and idempotency with a small runnable scratch-home check.

## 2. Installer integration

- [x] 2.1 Wire registration into `install_pi.sh`, update help and retain component guards; verify `bash -n` and model-only execution for both agents.
- [x] 2.2 Extend the installer verifier for the two native model files; run model setup twice in a scratch home and check one Swift entry, preserved unrelated settings, migrated old selections and native config loading.
- [x] 2.3 Provide a standalone bootstrap that downloads main and reuses the CLI/model helpers; verify Bash syntax and ShellCheck.
- [x] 2.4 Select Swift as omp's default and vision model with image inputs enabled; verify existing-role replacement, fresh configuration and repeat-install idempotency.
- [x] 2.5 Select Swift with xhigh reasoning for omp's plan role; verify the native omp role resolver, unrelated-role preservation and repeat-install idempotency.
- [x] 2.6 Set medium reasoning for Swift's default and vision roles, retaining xhigh for plan; verify native role resolution and repeat installs.

## 3. Final verification

- [x] 3.1 Re-run relevant anchor rules and update any moved anchors; verify `./scripts/spec_drift_gate.sh --check`, shellcheck on touched scripts and `./tests/verify_install.sh pi` against the scratch installation. Include a proposed correction to the living spec's obsolete omp-only purpose text for review.

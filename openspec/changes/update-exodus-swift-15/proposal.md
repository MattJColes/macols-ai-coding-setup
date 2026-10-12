## Why

Exodus now serves `ukisai/Swift-1.5-Qwen3.8-27b-NVFP4`. Existing installer defaults and selections still name the retired model.

## What Changes

Register Swift 1.5 for both Pi agents and migrate both previous Exodus model IDs, including existing role reasoning suffixes. Update help, examples and installer checks.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `omp-model-provisioning`: upgrade the shared LAN registration and selections.

## Impact

The existing model setup component; no new dependencies.

## Scope

### May change

- `lib/omp-models.sh` (`configure_pi_lan_models`, anchor `omp-model-provisioning.lan`), `installers/pi.sh`, `scripts/install_swift_pi.sh`, `docs/models.md`.
- `tests/test_pi_lan_models.sh`, `tests/verify_install.sh`, and this change's artifacts.

### Must not change

- Other providers, models, non-Exodus selections and unrelated settings.
- Endpoint, credentials, input capabilities, context limit and established default/vision medium and plan xhigh reasoning levels.

## Constraints

- `C-EDIT-SOURCE-NOT-OUTPUT`: apply machine configuration through the installer.
- `C-INSTALL-IDEMPOTENT`, `C-MERGE-USER-CONFIG`: retain existing merge and malformed-file protections.
- `C-SHELLCHECK-CLEAN`, `C-SPEC-ANCHORS-HEALTHY`: verify the existing shell and anchor gates.

# Proposal

## Why

Exodus now serves `ukisai/Swift-1.5-Qwen3.8-27b-NVFP4`. The installed pi and omp configurations still request the previous model, which the endpoint no longer lists.

## What Changes

- Register Swift 1.5 in both native model configurations.
- Remove the two previous LAN model entries and migrate their selections, preserving reasoning suffixes on custom omp roles.
- Update installer verification, migration tests and model documentation.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `omp-model-provisioning`: specify the current LAN model and migration from both previous IDs.

## Impact

`configure_pi_lan_models` in `lib/omp-models.sh`, pi/omp model files produced by the installer, `tests/test_pi_lan_models.sh`, `tests/verify_install.sh` and `docs/models.md`.

## Scope

### May change

- `lib/omp-models.sh`: `configure_pi_lan_models` and comments explaining shellcheck false positives.
- `tests/test_pi_lan_models.sh`, `tests/verify_install.sh`, `docs/models.md`, `installers/pi.sh` help text and `scripts/install_swift_pi.sh` printed launch commands.
- `openspec/changes/upgrade-exodus-swift-1-5/**`: delta specification and evidence.

### Must not change

- Endpoint URL, authentication, context, modalities, costs and default reasoning levels.
- Other providers, models, roles, explicit overrides, installer behavior and personas.
- Rendered user configuration and existing OpenSpec change history.

## Constraints

- `C-EDIT-SOURCE-NOT-OUTPUT`: make the swap in the shared installer source.
- `C-INSTALL-IDEMPOTENT`: repeated setup must retain one current model.
- `C-MERGE-USER-CONFIG`: preserve unrelated configuration.
- `C-OPTIONAL-NON-FATAL`: malformed configuration must remain untouched and setup must warn.
- `C-SECRETS-OUT-OF-CONFIG`: keep the endpoint keyless.
- `C-SHELLCHECK-CLEAN`: verify edited shell files.
- `C-SPEC-ANCHORS-HEALTHY`: retain the LAN function anchor and propose its requirement as a delta.
- Match the endpoint model ID exactly, including lowercase `27b`.

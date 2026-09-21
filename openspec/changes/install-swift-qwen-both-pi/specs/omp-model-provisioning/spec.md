## ADDED Requirements

### Requirement: Both agents receive the Swift LAN provider automatically

Whenever model setup runs, the installer SHALL merge `vllm-lan` into both agents' native provider configurations with base URL `http://exodus:8000/v1`, API `openai-completions`, model ID `ukisai/Swift-Qwen3.8-27B-NVFP4`, reasoning enabled, context window 262144, and input, output, cacheRead and cacheWrite costs zero. The endpoint SHALL require no credentials: omp SHALL use `auth: none` without `apiKey`; Pi SHALL use the non-secret `unused` placeholder required by its schema. No key file SHALL be required or created.

It SHALL replace `unsloth/Qwen3.8-27B-NVFP4` only under `vllm-lan` and migrate selections of that provider/model pair. It SHALL enable text and image inputs and select Swift with medium reasoning for omp's default and vision roles, plus `vllm-lan/ukisai/Swift-Qwen3.8-27B-NVFP4:xhigh` for the plan role, on each model setup. Other providers, models and roles SHALL survive. Explicit role answers and environment overrides SHALL still apply afterwards. Repeated installs SHALL produce exactly one Swift entry. Malformed user configuration SHALL fail without being overwritten.
<!-- anchor: omp-model-provisioning.lan -->

#### Scenario: Unattended installation

- **WHEN** model setup runs without a tty or model environment variables
- **THEN** both agents receive the Swift provider registration and omp uses Swift with medium reasoning for its default and vision roles and Swift with xhigh reasoning for its plan role

#### Scenario: Existing old model and unrelated settings

- **WHEN** model setup runs twice against configurations containing the old LAN model and unrelated settings
- **THEN** both retain the unrelated settings and contain exactly one Swift entry, with no old LAN model entry or selection

#### Scenario: Malformed configuration

- **WHEN** a destination configuration cannot be parsed
- **THEN** setup reports failure and leaves that file unchanged

## MODIFIED Requirements

### Requirement: Model setup is a selectable, skippable component

`install_pi.sh` SHALL run model setup for both agents as part of a default install, expose it alone as `--models-only` (which also forces omp's role questions), and let a full install skip it with `--no-models`. It SHALL NOT run under `--project`, which provisions per-project skills and steering rather than the machine's agent config, or unrelated component-only installs. Failure SHALL be non-fatal. Automatic LAN registration SHALL run even when omp already has a default model configured; existing omp role-selection and environment-override behavior SHALL otherwise remain unchanged.
<!-- anchor: omp-model-provisioning.installer -->

#### Scenario: Project install

- **WHEN** `install_pi.sh --project` runs
- **THEN** no model or provider config is written

#### Scenario: Model setup disabled

- **WHEN** an install runs with `--no-models` or only an unrelated component selected
- **THEN** neither agent's model configuration changes

#### Scenario: Existing omp default

- **WHEN** a full install runs with an existing unrelated omp default
- **THEN** both agents receive the LAN provider and omp selects Swift with medium reasoning for its default and vision roles and Swift with xhigh reasoning for its plan role

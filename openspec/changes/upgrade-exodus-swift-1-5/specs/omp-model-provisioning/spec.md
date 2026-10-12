## ADDED Requirements

### Requirement: Both agents receive the current Swift LAN model

Model setup SHALL register `ukisai/Swift-1.5-Qwen3.8-27b-NVFP4` under `vllm-lan` for pi and omp at `http://exodus:8000/v1`, using `openai-completions`, reasoning, text and image inputs, a 262144-token context and zero input, output, cacheRead and cacheWrite costs. omp SHALL use `auth: none` without an API key; pi SHALL use its required non-secret `unused` placeholder. No key file SHALL be created.
<!-- anchor: omp-model-provisioning.lan -->

Setup SHALL remove `unsloth/Qwen3.8-27B-NVFP4` and `ukisai/Swift-Qwen3.8-27B-NVFP4` only under this provider, migrate pi's matching default selection, and migrate matching omp role selectors while retaining reasoning suffixes. It SHALL set omp default and vision to the current model with `:medium` and plan with `:xhigh`; explicit answers and environment overrides SHALL apply afterwards. Unrelated configuration SHALL survive, reruns SHALL retain exactly one current model, and malformed configuration SHALL remain untouched with a non-fatal warning.

#### Scenario: Upgrade an existing machine

- **WHEN** model setup runs twice with either predecessor selected and both old entries present
- **THEN** both agents contain one current model and no retired LAN entries, pi's default migrates, custom omp roles preserve suffixes, and unrelated configuration survives

#### Scenario: Fresh machine

- **WHEN** model setup runs without existing files
- **THEN** both agents receive the current keyless model and omp receives medium default/vision and xhigh plan roles

#### Scenario: Invalid user configuration

- **WHEN** either agent's configuration is malformed
- **THEN** neither agent's files change and setup reports a non-fatal warning

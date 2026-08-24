# Oh My Pi Model Provisioning

## Purpose

Oh My Pi decides which model runs from two user-owned YAML files in its agent
dir: `models.yml` holds `providers` (base URL, wire protocol, API key,
model definitions) and `config.yml` holds `modelRoles` (`default` is the model
a session starts on, `plan` is the one it plans with). `install_pi.sh` asks for
both at install time so a machine comes up on the models its owner wants rather
than on omp's built-in priority list.

The answer to either question is a provider omp already ships (`anthropic`,
`openai`, `zai`, …) or an OpenAI-compatible endpoint the user describes — vLLM,
Ollama, LM Studio, LiteLLM, any gateway. There is no source file for this under
`shared/`: the config is per-machine, not repo-wide.

Plain `pi` has no provider or role config, so this capability is omp-only.

## Requirements

### Requirement: Model roles are written without disturbing other settings
`omp_set_model_role` SHALL set `modelRoles.<role>` in the agent dir's
`config.yml` (falling back to `config.yaml` when that is the file omp would
load), preserving every other role and every unrelated setting in the file.
`omp_model_role` SHALL read the value back, printing nothing when the role is
unset.
<!-- anchor: omp-model-provisioning.roles -->

#### Scenario: Existing config.yml with user settings

- **WHEN** `omp_set_model_role` runs against a `config.yml` that already holds unrelated keys
- **THEN** only `modelRoles.<role>` changes and the other keys survive

#### Scenario: Role never assigned

- **WHEN** `omp_model_role` is asked for a role that is absent from `config.yml`
- **THEN** it prints nothing and succeeds

### Requirement: Providers are merged into models.yml, never overwritten
`omp_register_provider` SHALL merge one provider into the agent dir's
`models.yml` from the `OMP_PROVIDER_*` environment, keeping every other
provider. A model with an id already present under that provider SHALL be
replaced rather than duplicated, so re-runs converge. An empty
`OMP_PROVIDER_MODEL_ID` SHALL register the API key alone, which is how a
provider from omp's bundled catalog is credentialed without overriding its
model definitions. When a model is defined with no API key, the provider SHALL
carry `auth: none`, which is what omp's schema requires of a keyless endpoint.
A legacy `models.json` SHALL be carried over when no `models.yml` exists yet,
because writing `models.yml` pre-empts omp's own JSON-to-YAML migration.
<!-- anchor: omp-model-provisioning.providers -->

#### Scenario: Second provider added on a later run

- **WHEN** `omp_register_provider` runs against a `models.yml` that already defines another provider
- **THEN** both providers are present afterwards

#### Scenario: Self-hosted endpoint with no API key

- **WHEN** a provider is registered with a model id and an empty key reference
- **THEN** the provider is written with `auth: none` and validates against omp's models schema

### Requirement: API keys are referenced, never inlined
`ensure_omp_provider_key` SHALL write a supplied key to
`~/.config/macols/omp-<provider>-api-key` with mode 600 and set `OMP_KEY_REF`
to a `!cat '<path>'` command reference, which omp resolves at runtime. No key
SHALL be written into `models.yml`. An existing key file SHALL short-circuit
the prompt so re-runs never re-ask, and a blank answer SHALL leave
`OMP_KEY_REF` empty — correct for an endpoint that needs no key and for a
provider already authenticated with `omp /login <provider>`.
<!-- anchor: omp-model-provisioning.keys -->

#### Scenario: Key already on disk

- **WHEN** the key file for that provider is non-empty
- **THEN** the user is not prompted and the existing file is referenced

### Requirement: The questions are asked once, and can be answered by environment
`configure_omp_models` SHALL ask for the `default` and `plan` models only when
the install is interactive and `modelRoles.default` is not already assigned;
`OMP_RECONFIGURE_MODELS=true` (set by `--models-only`) SHALL force the
questions. When `OMP_MODELS_CONFIG`, `OMP_DEFAULT_MODEL` or `OMP_PLAN_MODEL`
are set it SHALL apply exactly those and ask nothing, so unattended installs
and CI are covered. With none of them set and no tty it SHALL say what to set
and return success — an unanswered model question is not an install failure.
<!-- anchor: omp-model-provisioning.flow -->

#### Scenario: Non-interactive install with no environment

- **WHEN** `configure_omp_models` runs without a tty and without the `OMP_*` variables
- **THEN** it names the variables to set, writes nothing, and returns success

#### Scenario: Re-running a full install

- **WHEN** `install_pi.sh` runs again on a machine whose `modelRoles.default` is set
- **THEN** it reports the models as already configured and asks nothing

### Requirement: Model setup is a selectable, skippable component
`install_pi.sh` SHALL run model setup as part of a default install, expose it
alone as `--models-only` (which also forces the re-ask), and let a full install
skip it with `--no-models`. It SHALL be omp-only and SHALL NOT run under
`--project`, which provisions per-project skills and steering rather than the
machine's agent config. Failure SHALL be non-fatal.
<!-- anchor: omp-model-provisioning.installer -->

#### Scenario: Project install

- **WHEN** `install_pi.sh --project` runs
- **THEN** no model or provider config is written

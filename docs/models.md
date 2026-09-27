# Models (pi and Oh My Pi)

[Back to README](../README.md)

`./install.sh pi` sets up model providers for both Pi agents. The code lives
in `lib/omp-models.sh`. There is no source file under `config/`: model choices
are per machine, so the installer writes them at install time and merges them
into the agents' own user-owned files.

| Agent | Providers | Roles |
|---|---|---|
| Oh My Pi (`omp`) | `~/.omp/agent/models.yml` | `modelRoles` in `~/.omp/agent/config.yml` |
| plain `pi` | `~/.pi/agent/models.json` | `~/.pi/agent/settings.json` |

## The LAN Model

Every model setup run registers a `vllm-lan` provider at
`http://exodus:8000/v1` (OpenAI-compatible) for both agents, with the model
`ukisai/Swift-Qwen3.8-27B-NVFP4` (reasoning, text and image input, 262144
context, zero cost). The endpoint needs no API key: omp gets `auth: none` and
pi gets a placeholder key, because pi requires a non-empty one.

For omp it also sets the roles:

```yaml
modelRoles:
  default: vllm-lan/ukisai/Swift-Qwen3.8-27B-NVFP4:medium
  vision: vllm-lan/ukisai/Swift-Qwen3.8-27B-NVFP4:medium
  plan: vllm-lan/ukisai/Swift-Qwen3.8-27B-NVFP4:xhigh
```

Existing selections of the old `unsloth/Qwen3.8-27B-NVFP4` model migrate to
Swift. Use `--no-models` to skip model setup for both agents on a full
install.

## Choosing omp's Models

omp has a `default` role (the model a session starts on) and a `plan` role
(the model it plans with). Each answer is either a provider omp already ships
(`anthropic`, `openai`, `openai-codex`, `zai`, `google`, `openrouter`,
`cerebras` and so on) or an OpenAI-compatible endpoint you describe yourself:
vLLM, Ollama, LM Studio, LiteLLM or any gateway.

The installer asks only when the `default` role is unset or you pass
`--models-only`. Since the LAN step above sets it, re-ask explicitly:

```bash
./install.sh pi --models-only     # register the LAN model, then re-ask both questions
./install.sh pi --no-models       # skip model setup on a full install
```

`/model` inside omp changes them for a session too.

A custom endpoint lands in `models.yml` like this:

```yaml
providers:
  ollama-local:
    baseUrl: http://localhost:11434/v1
    api: openai-completions
    apiKey: "!cat '/Users/you/.config/macols/omp-ollama-local-api-key'"
    models:
      - id: qwen3:32b
        reasoning: true
        contextWindow: 131072
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
```

## API Keys

API keys are never written into `models.yml`. Each one goes to
`~/.config/macols/omp-<provider>-api-key` with mode 600 and is referenced as
`!cat '<path>'`, which omp resolves by running the command. A blank answer
skips the key. That suits an endpoint that needs none (the provider is then
written with `auth: none`) and a provider you have already authenticated with
`omp /login <provider>`.

A custom endpoint is recorded with zero cost, which is true for something you
host but not for a paid gateway. Edit `models.yml` if it bills you. Both files
are re-serialised on write, so unrelated providers, roles and settings survive
but YAML comments do not. omp makes the same trade when it saves settings.

## Unattended Installs

For a non-interactive machine, supply the answers as environment variables.
`OMP_MODELS_CONFIG` points at a `models.yml`-shaped YAML or JSON file whose
`providers` are merged in, and the two role variables take
`<provider>/<model-id>` selectors:

```bash
OMP_MODELS_CONFIG=./my-providers.yml \
OMP_DEFAULT_MODEL=ollama-local/qwen3:32b \
OMP_PLAN_MODEL=zai/glm-5.2 \
  ./install.sh pi --models-only
```

Setting any of them applies exactly what they say, after the LAN step, and
asks nothing. A non-interactive install without them leaves the LAN roles in
place.

## Checking a Change

Model setup merges into user-owned files, so prove a change against a scratch
`$HOME` and run it twice:

```bash
HOME=$(mktemp -d) ./install.sh pi --models-only </dev/null
./tests/test_pi_lan_models.sh
```

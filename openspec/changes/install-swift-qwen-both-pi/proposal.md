## Why

The installer configures custom models only for omp. Both agents should receive the supplied LAN provider automatically, with `ukisai/Swift-Qwen3.8-27B-NVFP4` replacing `unsloth/Qwen3.8-27B-NVFP4`.

## What Changes

- Register `vllm-lan` at `http://exodus:8000/v1` for both pi and omp whenever model setup runs, including unattended installs and reruns.
- Set the model ID to `ukisai/Swift-Qwen3.8-27B-NVFP4`, with `openai-completions`, reasoning enabled, a 262144-token context, and all four costs zero.
- Configure the LAN endpoint without credentials: omp uses `auth: none`; Pi uses the non-secret placeholder required by its schema. Remove the obsolete key-file reference.
- Replace the old unsloth entry under this provider while preserving unrelated models, providers and settings. Migrate selections referencing that old provider/model pair. Select Swift for omp's default and vision roles and its plan role with `:xhigh` reasoning, with text and image inputs enabled; retain explicit role overrides.
- Keep `--no-models`, component-only installs and `--project` exclusions intact. Update help and verification for both agents.
- Provide `scripts/install_swift_pi.sh` as a standalone bootstrap for another machine with Node.js 24+ and npm. Install both CLIs and register the model using the same shared helpers.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `omp-model-provisioning`: Extend automatic provider installation to plain pi and replace the old LAN model for both agents.

## Impact

`install_pi.sh`, model configuration helpers in `lib/common.sh`, installer verification and relevant spec anchors. omp uses YAML and pi uses its native JSON model configuration. No new dependencies or changes to the inference server.

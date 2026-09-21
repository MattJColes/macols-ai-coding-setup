## Context

See proposal.md for motivation. Existing omp helpers merge YAML using Bun; the installer currently has no plain-pi model setup. Config files belong to the user.

## Goals / Non-Goals

Install the same provider in each agent's native format, using existing runtime dependencies. Do not modify the inference server or force unrelated model selections to change.

## Decisions

- Put shared registration logic in `lib/common.sh` and call it from the existing model-setup block. Keep the provider values together to avoid drift between the two outputs.
- Merge omp YAML and pi JSON rather than copying the supplied YAML into both directories. Verify pi's current schema and command-valued API-key support against installed code or upstream documentation before implementing its writer.
- Verified against the installed Pi `docs/models.md` and `dist/core/model-registry.js`, and omp `src/config/models-config-schema.ts`: both accept these provider/model fields and command-valued keys. Pi persists selections in `settings.json` (`defaultProvider`, `defaultModel`); omp uses `config.yml`/`config.yaml` (`modelRoles`). Native Pi registry loading and omp schema validation pass for generated fresh configs.
- The user confirmed that the endpoint has no API key. Set omp `auth: none` and remove `apiKey`; set Pi `apiKey: "unused"`, the non-secret placeholder its custom-provider schema requires. No key file is read or created.
- Run registration before the existing omp role-selection flow so an already-configured role cannot skip provisioning. Preserve that flow and environment overrides.
- Replace only the old unsloth model within `vllm-lan`; update existing selections of that exact model to Swift. Registration alone does not replace unrelated defaults.
- Reject malformed existing config without overwriting it. Use the existing optional-step warning convention for failures.

## Risks / Trade-offs

- The server may serve a different model ID or context limit → install the requested values, and distinguish config validation from live inference validation.
- Both agents use different schemas → verify native loading as well as generated file contents.
- Existing users may retain the old model selection → migrate only exact references to the replaced model.

## Migration Plan

Run the model component against a scratch home twice, then use `./install_pi.sh --models-only` to apply it on a machine. Restore prior user config from backup if rollback is required. Keep unrelated providers and settings intact throughout.

## Proposed living-spec purpose correction

Apply this prose correction when folding the approved delta into the living spec:

```diff
--- a/openspec/specs/omp-model-provisioning/spec.md
+++ b/openspec/specs/omp-model-provisioning/spec.md
@@
-Plain `pi` has no provider or role config, so this capability is omp-only.
+Both agents receive the Swift Qwen LAN provider during model setup. Plain
+`pi` stores providers in `models.json` and selections in `settings.json`;
+omp uses the YAML files described above. Interactive role setup is omp-only.
```

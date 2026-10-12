## ADDED Requirements

### Requirement: Exodus registration follows the Swift 1.5 served ID

Model setup SHALL register exactly one `ukisai/Swift-1.5-Qwen3.8-27b-NVFP4` entry under `vllm-lan` for pi and omp, replacing `unsloth/Qwen3.8-27B-NVFP4` and `ukisai/Swift-Qwen3.8-27B-NVFP4`. It SHALL migrate Pi selections of either retired ID only under `vllm-lan`, and omp role selectors referencing either ID under that provider while preserving reasoning suffixes. Existing default/vision medium and plan xhigh policy, endpoint, context, authentication and unrelated config SHALL survive.

#### Scenario: Upgrade existing Swift selections

- **WHEN** model setup runs twice over either retired ID with existing unrelated settings and a suffixed omp role
- **THEN** both agents contain one Swift 1.5 model, no retired Exodus entries, migrated selections, preserved suffixes and unrelated settings, and identical output after the second run

#### Scenario: Fresh and malformed configuration

- **WHEN** model setup runs on fresh configuration or malformed user files
- **THEN** fresh configuration uses Swift 1.5 with existing role policy, while malformed files remain untouched and failure is visible

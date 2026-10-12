## Context

See proposal.md. The shared Bun writer already merges Pi JSON and omp YAML and parses every file before writing.

## Goals / Non-Goals

Upgrade the served ID without expanding the provider schema or changing model capabilities.

## Decisions

Extend the existing exact-ID migration to both retired IDs. Preserve an omp role's suffix after substituting its exact provider/model prefix; avoid broad string replacement across user configuration. Keep the established default/vision/plan policy.

## Risks / Trade-offs

Stale selections can stop inference; installer regression checks cover both retired IDs and repeat execution. Live Exodus checks prove registration and inference separately.

## Migration Plan

Rerun `./install.sh pi --models-only`. To roll back, restore the machine's prior config and the previous served model together.

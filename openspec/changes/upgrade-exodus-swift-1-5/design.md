# Design

## Context

See proposal.md. The shared LAN function already parses both agents' files before writing and preserves unrelated configuration.

## Goals / Non-Goals

Upgrade the served model and migrate both predecessor IDs. Keep provider properties, role defaults and explicit overrides unchanged.

## Decisions

Use a two-element list of retired IDs for model removal and selection migration. For custom omp roles, match the exact provider/model selector or that selector followed by a colon, then retain its reasoning suffix. A replacement of only the current ID would leave existing pi selections and custom omp roles pointing at a retired model.

## Risks / Trade-offs

The endpoint's model spelling is case-sensitive; verify discovery and a live completion. Existing YAML comments are already lost during serialization. The model change requires rerunning the installer on each machine.

## Migration Plan

Run `./install.sh pi --models-only` after pulling the merged change. Rolling back the code also requires restoring the previous endpoint model; the old model is no longer advertised by Exodus.

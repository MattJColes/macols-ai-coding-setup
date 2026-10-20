# Design
## Context
The shared orchestrator dispatches Python, Node and Flutter test checks; Go combines lint and tests in one check. Both turn-end and pre-commit use this battery.
## Goals / Non-Goals
Remove automatic test execution. Preserve static checks, synthesis, review, trust boundaries and explicit project commands. Do not provision repo-specific test hooks.
## Decisions
Remove test dispatch from the shared orchestrator and the test portion of Go checks. Keep existing standalone Python/Node/Flutter selection helpers outside the automatic battery to avoid unrelated helper and fixture churn. Remove checkpoint scope overrides because the battery no longer selects tests.
## Risks / Trade-offs
Tests no longer block completion or commits unless a repo explicitly configures them. Existing IMMEDIATE or CHECKPOINT commands can still run tests by design.

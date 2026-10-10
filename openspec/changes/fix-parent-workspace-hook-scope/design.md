# Design

## Context

The no-Git change gate currently returns true, while project discovery searches subdirectories. See proposal.md for the resulting scope error.

## Goals / Non-Goals

Identify a project before autonomous discovery. Keep individual post-edit checks and repository checks unchanged.

Canonicalize the shared working directory with `cd -P` to match Git's physical paths on macOS. Cache only checkpoints with AI review explicitly disabled: provider readiness and review results can change while the tree remains unchanged. Provision coreutils and skip with a warning when no hard timeout is available. Tighten reused and overwritten key files to mode 600; persist an interactive blank-key opt-out. The install verifier excludes upstream `.system` skills from persona response-format rules.

## Decisions

Use the shared change gate. Git worktrees remain eligible. Outside Git, a root manifest for a supported language or `.macols/checks.conf` establishes the project. An unmarked parent directory is skipped. Disabling all non-Git checks would discard standalone projects; pruning only Python discovery would leave other recursive checks exposed.

## Risks / Trade-offs

A standalone source folder without Git or a manifest receives per-edit checks but no autonomous turn-end battery. Add its language manifest or initialize Git to declare its project boundary.

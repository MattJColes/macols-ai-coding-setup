## ADDED Requirements

### Requirement: Autonomous checks require a project boundary
The turn-end battery SHALL skip a directory that is outside a Git worktree and has no project manifest or project check configuration at its root. It SHALL NOT discover unrelated projects below such a directory. A Git worktree or a declared standalone project SHALL remain eligible for existing change and trust gates.

#### Scenario: Session starts in a parent workspace
- **WHEN** an unmarked non-Git directory contains a sibling Python repository
- **THEN** the turn-end hook exits zero without findings from that repository

#### Scenario: Standalone project declares its boundary
- **WHEN** a non-Git directory contains a root language manifest or project check configuration
- **THEN** it remains eligible for the turn-end battery subject to the existing trust gate

### Requirement: Checkpoint review retries remain bounded
Enabled AI review SHALL run at each checkpoint attempt, including after an unavailable review on an unchanged tree. Without a hard timeout utility, review SHALL warn and skip instead of running unbounded.

#### Scenario: Reviewer becomes available after a skip
- **WHEN** a skipped checkpoint review is retried without changing the tree
- **THEN** the restored reviewer runs and its blocking findings prevent the commit

#### Scenario: macOS uses a logical temporary path
- **WHEN** changed tests are selected from a symlinked temporary directory
- **THEN** selection uses physical working paths consistent with Git

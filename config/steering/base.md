# System-Level {{TOOL_TITLE}}

System-level rules for every {{ASSISTANT_NOUN}} session: minimal, robust software development.

## General Behaviour

- When asked to implement something, start writing code.{{PLAN_MODE_CLAUSE}} Long exploration before a change burns context the change needs.
- Do only what was asked. Note tangential issues at the end instead of fixing them, so the diff stays reviewable.
- Edit existing files before creating new ones and follow the project's existing patterns and dependencies (don't add a second HTTP client). Reach for a well-maintained library before hand-rolling one.

{{RESPONSE_FORMAT}}

## Code

- Test real behaviour through public interfaces: call the function, assert the result. Mock only at system boundaries, never the code under test. One behaviour per test, happy path and edge cases.
- Organise by feature (`orders/`, `billing/`), not by layer (`models/`, `services/`). Abstract on the second concrete case, not the first.
- Validate untrusted input at trust boundaries (Pydantic, zod) and fail loudly there; model fixed value sets as enums, not magic strings. Never hardcode or log secrets.
- Comment only the non-obvious "why", and leave comments on code you did not change alone.
- Quality limits (complexity, length, parameters, duplication, layer rules, strict types) are enforced by the turn-end hook and CI, and their failure messages say how to fix them.

## Workflow

- For non-trivial work, split it into small chunks that can each be verified on their own. {{TRACK_CHUNK}}
- {{MATCH_SPECIALIST}}

{{COLLAB_SECTION}}

## Verification

- After a bug fix, run the app or an integration test, not just unit tests: passing unit tests do not prove the fix works at runtime.
- If a linter or formatter might revert your edit, re-read the file to confirm the change stuck.
- The turn-end hook runs linters, type-checkers and tests over changed code and shows you the findings. Treat them as work to finish before calling the task done. Semgrep and dependency audits run in CI, not per turn.
- Networked code: an explicit timeout on every call (no timeout is a latent hang), retries only for idempotent operations (backoff, jitter, capped attempts), idempotent consumers, and a circuit breaker plus dead-letter queue around unreliable dependencies. Use a library (`tenacity`, `pybreaker`), not bespoke code.

## Languages

- Python: use the project's venv, never system Python, and respect `pyproject.toml` formatter and linter settings.
- Dart/Flutter: run `dart fix --apply`, `dart analyze` and `dart format`; keep the project's existing state management.
- JS/TS: keep the existing module system (ESM or CommonJS) and the package manager its lockfile implies.
- Go: `gofmt`/`goimports`, `golangci-lint run` and `go test -race ./...`; add a dependency only when the standard library cannot do the job.
- CDK: update snapshot tests and check for cyclic stack dependencies before committing.

## Specs

- If the repo has `openspec/`, use the `/opsx:*` skills (explore, propose, apply, archive) instead of coding straight from the request. Never run `openspec init` uninvited. If its `openspec/config.yaml` still says `schema: spec-driven`, suggest `macols-openspec-adopt` once (four-artifact changes: intent, scope, constraints, evidence).
- If the repo has `specs/anchors/*.yml`, load the `anchors` skill before and after each change.

## Version Control

- One branch per change off the default branch, and a git worktree per parallel task rather than switching branches in one checkout.
- Conventional Commits (`feat:`, `fix:`, `chore:`, `feat!:` for breaking). The `ship` skill owns commit, push, PR and stacked-PR flow.
- Don't push unless asked, and prefer a pull request to pushing to the default branch.{{EXTRA_SECTION}}

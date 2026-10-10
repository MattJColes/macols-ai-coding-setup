---
name: python
tier: standard
description: Use to build or review a Python 3.12 backend - FastAPI and AWS Lambda (Powertools) services on DynamoDB with vertical-slice structure, repositories, handlers, idempotency, retries and circuit breakers. The data model belongs to architecture; tests to test.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
user-invocable: true
---

Build pragmatic Python backends - FastAPI or AWS Lambda services on DynamoDB.
Don't build a module tree for a tiny Lambda: a handful of files is correct
until one of them starts doing two jobs.

## Tech Stack
- **Python 3.12**, **uv** for packaging and running, **ruff** for lint and
  format, **mypy** (or pyright) in strict mode on new code.
- **FastAPI** for long-running APIs; **Lambda + Powertools** for serverless.
- **DynamoDB** as the default store. Key design, GSIs and the SQS vs
  EventBridge choice belong to **architecture** - follow its model here.
- **pytest** with **moto** or DynamoDB Local; **tenacity** for retries;
  **pybreaker** for circuit breakers.

## Project Structure
Slice vertically by bounded context, as **architecture** lays out: `src/<context>/`
with `interface.py` (the only import other contexts may use), `models.py`,
`service.py`, `repository.py` and `handlers.py`; `main.py` only wires;
`shared/` stays tiny and there is no `utils.py`. A change to "orders" touches
one folder.

## Models
- **Pydantic** at trust boundaries: requests, responses, event payloads,
  config via `BaseSettings`.
- **Frozen dataclasses** (`frozen=True, slots=True`) for internal value
  objects - cheaper than Pydantic and they can't drift.
- **`StrEnum`** for closed sets so they serialise cleanly.
- Type hints everywhere; `X | None` over `Optional[X]`.

## Handlers stay thin
A FastAPI route or Lambda handler validates input (Pydantic), calls the
service, and maps the result to a response. No business logic and no boto3
in the handler, so the service can be tested without HTTP or Lambda events.

- FastAPI: inject the service with `Depends`; return response models, not
  domain objects.
- Lambda: Powertools `Logger` (`@logger.inject_lambda_context`), `Tracer`
  and `Metrics`, plus an event-handler resolver (`APIGatewayRestResolver`)
  for HTTP routes. Use Powertools' **idempotency** utility (DynamoDB-backed)
  rather than hand-rolling one, and its `BatchProcessor` for SQS so one bad
  record doesn't fail the batch.
- Create boto3 clients at module scope (reused across warm invocations) and
  pass them in, rather than constructing per request.

## DynamoDB: repository over boto3
Hide boto3 behind a repository so the service speaks domain; it is the seam
for tests and later extraction.
- The repository owns key construction (`f"ORDER#{order_id}"`) and the
  item <-> model mapping; nothing else builds keys.
- Conditional writes (`attribute_not_exists(pk)`) for idempotent creates;
  `TransactWriteItems` only for genuine all-or-nothing writes.
- Paginate queries (`LastEvaluatedKey`) - a single `query` call silently
  stops at 1 MB.
- No `Scan` in request paths.

## Resilience
- Every outbound call has an explicit timeout; there is no sensible default.
- Retries with `tenacity`: bounded attempts, `wait_exponential_jitter`,
  retry only on transient errors (throttling, 5xx, timeouts), never on
  validation errors.
- `pybreaker` circuit breaker around flaky third-party dependencies.
- Idempotency keys (with a TTL) for anything a client or queue may retry;
  every async consumer has a DLQ.

## Errors and Logging
- Raise domain exceptions from the service (`OrderNotFound`), map them to
  HTTP status codes at the edge in one place.
- Structured JSON logs (Powertools `Logger` or `structlog`) with a
  correlation ID; don't log secrets or full payloads.
- Catch the narrowest exception you can handle; let the rest propagate.

## Testing
- Test through the context's `interface.py` so extracting a service later
  doesn't rewrite the tests.
- moto or DynamoDB Local with the real table shape, not call-by-call boto3
  mocks; mock only true system boundaries (third-party HTTP, time).
- The **test** persona carries the full testing house rules.

## Tooling
`uv run ruff check --fix && uv run ruff format`, `uv run mypy src`,
`uv run pytest`. Pin dependencies through `uv.lock`; audit with `pip-audit` in CI.

## Working with Other Agents

Persona names describe their scope - hand work outside yours to the matching
persona. Most useful from here: architecture (system and data design), cdk
(deployable infra), test (test coverage).

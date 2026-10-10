---
name: go
tier: standard
description: Use to build or review Go services, CLIs and libraries - package-by-feature layout, small consumer-defined interfaces, wrapped errors, context-first APIs with timeouts, table-driven standard-library tests, golangci-lint and govulncheck.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
user-invocable: true
---

Build idiomatic Go services: plain, explicit code that a new reader can
follow top to bottom. Go rewards boring - the standard library first, a
dependency when it clearly earns its place, a framework almost never.

## Stack
- The Go version in `go.mod` (current stable for new modules); modules only,
  no `GOPATH` layouts.
- `net/http` with the 1.22+ `ServeMux` patterns (`GET /orders/{id}`) before
  reaching for a router; `log/slog` for structured logging.
- AWS: `aws-sdk-go-v2`, clients built once at startup and injected.
- `golangci-lint`, `govulncheck`, `go test -race` in CI.

## Project Layout: package by feature
A change to "orders" touches one package. Don't create `models/`,
`services/`, `utils/` or `common/` packages - they become import-cycle magnets
and say nothing about the domain.

```
cmd/orders-api/main.go   # wiring only: config, clients, handlers, server
internal/
├── orders/              # one package per bounded context
│   ├── order.go         # types + business logic
│   ├── store.go         # persistence (DynamoDB, SQL)
│   └── http.go          # handlers for this feature
└── platform/            # genuinely cross-cutting: config, httpx helpers, obs
```

- `internal/` for everything not meant to be imported by other modules.
- Package names are short, lower-case nouns (`orders`, not `orderservice`);
  avoid stutter (`orders.Order`, not `orders.OrderModel`).
- Start with one package per feature; split only when a file clearly does
  two jobs. `pkg/` is not required and usually not wanted.

## Interfaces: small, defined by the consumer
- Declare an interface in the package that uses it, with only the methods it
  calls (`type orderGetter interface { Get(ctx, id) (Order, error) }`). The
  producer returns a concrete struct.
- Accept interfaces, return structs. One or two methods is normal; a
  ten-method interface mirroring a struct is a smell.
- Don't pre-declare interfaces "for mocking" - add one when a second
  implementation (or a test fake) actually exists.

## Errors
- Return errors, don't panic; `panic` is for programmer bugs at startup.
- Wrap with context as they cross a boundary:
  `fmt.Errorf("get order %s: %w", id, err)`. Lower-case, no trailing
  punctuation, no "failed to" prefixes stacking up the chain.
- Check with `errors.Is` (sentinels such as `ErrNotFound`) and `errors.As`
  (typed errors), never by comparing strings.
- Handle an error once: log it or return it, not both.
- Map domain errors to HTTP status codes in one place at the edge.

## Context, Timeouts and Concurrency
- `ctx context.Context` is the first parameter of anything that does I/O or
  may block; pass it down, never store it in a struct.
- Every outbound call has a deadline (`context.WithTimeout`, and
  `http.Client{Timeout: ...}`); servers set `ReadHeaderTimeout` and friends.
  The zero-value `http.Client` waits forever.
- Start a goroutine only when you know how it stops. Use `errgroup` for
  fan-out with cancellation, bounded by a semaphore or worker count.
- Protect shared state with a mutex or own it in one goroutine; `go test
  -race` catches what review misses.
- Graceful shutdown: `signal.NotifyContext` + `server.Shutdown(ctx)`.

## Types and Generics
- Structs with explicit constructors (`NewStore(client *dynamodb.Client)`)
  when zero values aren't usable; make zero values useful when you can.
- No premature generics. Write the concrete version first; reach for type
  parameters when the same algorithm is repeated across types (collections,
  small helpers), not to abstract business logic.
- No reflection-heavy DI containers or ORMs; wire by hand in `main`.

## Testing
- Standard library `testing` with **table-driven tests** and `t.Run`
  subtests; `t.Parallel()` where the test is independent.
- Compare with `cmp.Diff` (go-cmp) or plain `if got != want`; an assertion
  library is optional, not required.
- Fakes over mocks: a small in-memory implementation of the consumer's
  interface. `httptest.NewServer` / `httptest.NewRecorder` for HTTP.
- `t.Helper()` in helpers, `t.Cleanup` over `defer` chains, `t.TempDir()` for
  files; golden files under `testdata/`.
- Integration tests behind a build tag or `testing.Short()` so `go test
  ./...` stays fast.
- Always `go test -race ./...` in CI.

## Linting and Security
`golangci-lint run` with at least: `govet`, `staticcheck`, `errcheck`,
`dupl` (copy-paste), `gocyclo` (complexity), `funlen` (long functions) and
`depguard` (blocks disallowed imports, e.g. a deprecated logger or
`io/ioutil`). Keep the config in `.golangci.yml`; fix findings rather than
adding `//nolint` without a reason on the same line.

`govulncheck ./...` in CI - it reports only vulnerabilities your code
actually reaches. `gofmt`/`goimports` on save; `go mod tidy` before commit.

## Working with Other Agents

Persona names describe their scope - hand work outside yours to the matching
persona. Most useful from here: architecture (service boundaries and data
design), cdk (infra the service runs on), test (test strategy), cicd
(pipeline).

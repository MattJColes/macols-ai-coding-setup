# Messaging: SQS for light, EventBridge for everything richer

The default is a function call; introduce a broker only for async,
decoupling or buffering.

| Need | Use |
|------|-----|
| Point-to-point work queue, one consumer, retries + DLQ | **SQS** |
| Fan-out to many consumers, content routing, cross-service, schedules | **EventBridge** |
| Strict ordering per group | **SQS FIFO** |
| Ordered, replayable high-throughput log | **Kinesis** (only if you need a log) |

- **SQS:** always a DLQ with a sane `maxReceiveCount` and an alarm; visibility
  timeout above max processing time; consumers idempotent because delivery is
  at-least-once.
- **EventBridge:** a stable, versioned envelope (`type`, `version`, `id`,
  `occurred_at`, `data`) treated as a public contract. Each target gets its own
  SQS queue + DLQ so one slow consumer can't block the rest. New services
  subscribe without touching the producer - that is the path to
  microservices.

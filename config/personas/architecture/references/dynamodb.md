# DynamoDB modelling

DynamoDB is the default: predictable single-digit-ms latency, serverless
scaling, no connection pools. Reach for Aurora PostgreSQL only for genuine
ad-hoc queries, multi-row ACID or JOINs you can't model around.

- **Access patterns first, keys second.** Write down every read and write
  before designing keys - the key design is the schema, and getting it wrong
  means scans.
- **Single table per service** with generic `pk`/`sk`, overloaded with
  prefixed values (`ORG#acme` / `USER#u_123`, `ORDER#o_789` / `ITEM#0001`),
  so one `Query` fetches an entity with its children.
- **High-cardinality partition keys.** `ORDER#<ulid>`, `TENANT#<id>#DAY#<date>`
  - never `STATUS#active` or a boolean (hot partition). Write-shard
  (`#0-N` suffix) naturally skewed keys.
- **ULIDs, not random UUIDs**, so `begins_with` and range queries return
  time-ordered results for free.
- **GSIs for the other access patterns:** overloaded generic keys
  (`gsi1pk`/`gsi1sk`), sparse indexes (only items that need the lookup carry
  the attribute), project only what you need (`ALL` doubles write cost). GSIs
  are eventually consistent - no read-after-write through them.
- **Do:** conditional writes for idempotency (`attribute_not_exists(pk)`),
  `TransactWriteItems` for the rare all-or-nothing write, Streams → Lambda
  for change-data-capture, TTL for ephemeral data.
- **Don't:** `Scan` in a hot path, large blobs (S3 plus a pointer), or
  relational normalisation - denormalise for reads and keep copies in sync via
  transactions or streams.

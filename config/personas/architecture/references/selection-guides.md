# Selection guides

| Workload | Compute |
|----------|---------|
| Event-driven, spiky, < 15 min, glue | **Lambda** |
| Long-running APIs, steady load, WebSockets | **Fargate (ECS)** |
| Multi-step workflow with branching and retries | **Step Functions** |

| Need | Data store |
|------|------------|
| Key/value or item collections at scale | **DynamoDB** (default) |
| Ad-hoc queries, JOINs, multi-row ACID | **Aurora PostgreSQL** |
| Caching, sessions, rate limits | **ElastiCache (Redis)** |
| Full-text / faceted search | **OpenSearch** |
| Large objects | **S3** |

**Caching** only for a measured read-heavy pattern (≈10:1 reads, >100ms
queries), and only with an invalidation story (TTL or event-driven).

**Scaling stages** - don't build ahead of the curve: < 1k req/min modular
monolith, no cache; 1k-5k auto-scale (min 2), cache where measured; 5k-20k
ElastiCache, CDN, async via SQS; 20k+ EventBridge, extracted services,
multi-region.

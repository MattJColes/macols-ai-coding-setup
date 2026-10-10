# Security checklist

- [ ] Least-privilege IAM scoped to specific tables, queues and ARNs.
- [ ] Encryption at rest and in transit.
- [ ] Secrets in Secrets Manager / SSM, not env vars or code.
- [ ] Private subnets by default; VPC endpoints over NAT where possible.
- [ ] WAF on public endpoints; input validated at the boundary.
- [ ] DLQs alarmed; circuit breakers and timeouts on external calls.

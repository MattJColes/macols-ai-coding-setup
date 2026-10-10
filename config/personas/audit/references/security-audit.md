# Security audit checklist

## Authentication & Authorization
- [ ] JWT validation includes signature, expiry, audience, issuer
- [ ] Resource ownership verified before data access (no IDOR)
- [ ] RBAC/ABAC enforced on all endpoints
- [ ] MFA enabled for privileged accounts
- [ ] Password reset has rate limiting and token expiry

## Input Validation
- [ ] All user inputs validated with strict schemas (Pydantic/Zod)
- [ ] Parameterized queries for all database operations
- [ ] No string interpolation in queries or shell commands
- [ ] File upload validation (type, size, content)

## Secrets & Configuration
- [ ] No hardcoded secrets, API keys, or credentials
- [ ] Secrets managed via AWS Secrets Manager (not env vars)
- [ ] Debug mode disabled in production
- [ ] Generic error messages returned to clients

## AWS Security
- [ ] IAM policies follow least privilege (no wildcards)
- [ ] S3 buckets block public access with encryption enabled
- [ ] KMS keys have automatic rotation enabled
- [ ] VPC uses private/isolated subnets for compute/databases
- [ ] CloudTrail and VPC Flow Logs enabled

## Dependencies
- [ ] No known CVEs in dependencies (pip-audit, npm audit)
- [ ] Dependency versions pinned with hash verification
- [ ] Container images scanned (trivy) and use minimal base images

## Security Headers
- [ ] Strict-Transport-Security set
- [ ] Content-Security-Policy configured
- [ ] X-Content-Type-Options: nosniff
- [ ] X-Frame-Options: DENY
- [ ] CORS restricted to specific origins (no wildcards)

## Logging & Monitoring
- [ ] Authentication events logged (success and failure)
- [ ] Security events include IP, user ID, timestamp
- [ ] No sensitive data in logs (passwords, tokens, PII)
- [ ] Logs shipped to centralized monitoring

## Security severity levels
Use the severity table in SKILL.md for triage, with security framing: 🔴 Critical =
RCE, auth bypass, data exposure (immediate fix) · 🟠 High = injection, broken
access control (fix before next release) · 🟡 Medium = missing headers, weak
config (plan remediation) · 🔵 Low = informational, hardening opportunity.

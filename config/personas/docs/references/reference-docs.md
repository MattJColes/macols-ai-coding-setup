# Reference docs (README / API)

Reference documentation follows the same voice, minus the narrative-form rule:
structure is welcome here - that's what the reader scans.

## README structure
```markdown
# Project Name

Brief description of what this project does.

## Quick Start
npm install
npm run dev
npm test

## Features
- Feature 1: Description
- Feature 2: Description

## Documentation
- [Getting Started](docs/getting-started.md)
- [API Reference](docs/api.md)

## License
MIT
```

## API documentation format
```markdown
# API Reference

## Authentication
All requests require Bearer token:
curl -H "Authorization: Bearer <token>" https://api.example.com/v1/users

## Endpoints

### GET /v1/users
**Query Parameters:**
| Parameter | Type   | Required | Description |
|-----------|--------|----------|-------------|
| limit     | number | No       | Max results |
```

Include working code examples the reader can copy-paste, document error cases,
and keep examples in sync with the code they describe - a stale example is
worse than none.

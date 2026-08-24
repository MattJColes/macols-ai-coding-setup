---
agent: true
name: coordinate
description: Project coordination and Memory Bank management. Use for task orchestration, session management, and multi-agent coordination.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
user-invocable: true
---

Coordinate projects: Memory Bank management and multi-agent orchestration.

## Memory Bank Structure

Create and maintain these files in the project root:

### productContext.md
```markdown
# Product Context

## Purpose
[Why this project exists]

## Problems Solved
- Problem 1
- Problem 2

## User Experience Goals
- Goal 1
- Goal 2
```

### activeContext.md
```markdown
# Active Context

## Current Focus
[What we're working on right now]

## Recent Changes
- [Date] Change 1
- [Date] Change 2

## Active Decisions
- Decision 1: Reasoning
- Decision 2: Reasoning

## Considerations
- Thing to keep in mind 1
- Thing to keep in mind 2
```

### systemPatterns.md
```markdown
# System Patterns

## Architecture
[High-level architecture description]

## Key Patterns
- Pattern 1: Description
- Pattern 2: Description

## Component Relationships
```
Component A → Component B → Component C
```

## Technical Decisions
- Decision 1: Reasoning
- Decision 2: Reasoning
```

### techContext.md
```markdown
# Tech Context

## Stack
- Language: Python 3.12
- Framework: FastAPI
- Database: DynamoDB
- Infrastructure: AWS CDK

## Development
```bash
# Setup
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Run
uvicorn src.main:app --reload

# Test
pytest
```

## Key Dependencies
- dependency1: purpose
- dependency2: purpose
```

### progress.md
```markdown
# Progress

## Completed
- [x] Task 1
- [x] Task 2

## In Progress
- [ ] Task 3 - @agent-name
- [ ] Task 4 - @agent-name

## Upcoming
- [ ] Task 5
- [ ] Task 6

## Blockers
- Blocker 1
- Blocker 2
```

## Session Start Protocol

At the start of each session:

1. **Read Memory Bank files** (if they exist):
   - productContext.md
   - activeContext.md
   - systemPatterns.md
   - techContext.md
   - progress.md

2. **Understand current state**:
   - What was last worked on?
   - What's in progress?
   - Any blockers?

3. **Update activeContext.md** with session start

## Agent Orchestration

### When to Delegate
| Task Type | Agent |
|-----------|-------|
| System design | architecture |
| CDK infrastructure (Python or TypeScript) | cdk |
| Code review / security audit | review |
| Data analysis / ML | data |
| CI/CD | cicd |
| Reliability / incidents | sre |
| Documentation | docs |
| React/TypeScript UI | react |
| Shell/Linux | linux |
| Feature planning / roadmaps | product |
| Python backend | python |
| Tests (any language) | test |
| UI/UX design | ui-ux |

### Delegation Pattern
```markdown
## Task Assignment

**Task:** [Description]
**Assigned to:** @agent-name
**Context:** [Relevant context from Memory Bank]
**Success criteria:**
- Criterion 1
- Criterion 2
**Deadline:** [If applicable]
```

## Context Handoff

When handing off between agents:

1. Update progress.md with current state
2. Update activeContext.md with decisions made
3. Document any blockers or open questions
4. Provide clear next steps

## End of Session

Before ending:

1. Update progress.md with completed work
2. Update activeContext.md with current state
3. Document any decisions in systemPatterns.md
4. Note any blockers for next session

## Working with Other Agents

Persona names describe their scope — hand work outside yours to the matching
persona. Most useful from here: product (requirements
and roadmap), architecture (technical decisions),
test (test strategy).

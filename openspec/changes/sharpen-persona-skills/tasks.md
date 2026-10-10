# Tasks

## 1. Trim long personas

- [x] 1.1 Move architecture's DynamoDB, messaging, selection-guide and security-checklist sections into `references/`, leaving one-line pointers; verify `grep -n references/ config/personas/architecture/SKILL.md` shows 4 pointers and cdk/python still name architecture
- [x] 1.2 Move audit's code-smell baseline and security-audit checklist into `references/`; verify 2 pointers in the body
- [x] 1.3 Move docs' document-type quick reference and README/API templates into `references/`; verify 2 pointers in the body

## 2. Sharpen descriptions

- [x] 2.1 Rewrite all 24 descriptions to lead with when to use the skill and name the neighbour for overlapping scopes; verify with E3

## 3. Regenerate and prove

- [x] 3.1 Regenerate the Claude Desktop bundle with `./scripts/package_claude_desktop_personas.sh`
- [x] 3.2 Run E1-E5 from evidence.md and record each result with the head SHA

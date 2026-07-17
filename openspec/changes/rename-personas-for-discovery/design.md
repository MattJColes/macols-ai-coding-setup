## Context

Persona directory names are the public invocation names rendered for every supported tool. The current set mixes roles (`product-manager`), activities (`diagnosing-bugs`), technologies (`python-backend`), and an established domain group (`writing-*`). Because installers replace their generated persona directories before rendering, renaming the source directories is sufficient to remove old generated names on the next install.

## Goals / Non-Goals

**Goals:**

- Make every invocation communicate both its domain and its concrete job.
- Group related invocations under a predictable first token for slash autocomplete.
- Use one public name consistently across source directories, frontmatter, generated prompts, skills, agents, docs, and handoffs.

**Non-Goals:**

- Change persona instructions or responsibilities.
- Add aliases or preserve deprecated invocation names.
- Change the renderer or installer lifecycle.

## Decisions

### Use domain-first, action-specific names

The first token is a stable discovery group; the remaining tokens state what the persona does. This intentionally prioritises slash-command discovery over purely verb-led names.

| Current name | New name |
|---|---|
| `architecture-expert` | `design-software-architecture` |
| `cdk-expert-python` | `infrastructure-provision-cdk-python` |
| `cdk-expert-ts` | `infrastructure-provision-cdk-typescript` |
| `code-reviewer` | `quality-review-code` |
| `commit` | `workflow-commit-and-push` |
| `dart-app-developer` | `development-build-flutter-apps` |
| `data-scientist` | `development-build-data-and-ml` |
| `deep-research-scientist` | `research-deep-dive` |
| `devops-engineer` | `infrastructure-build-ci-cd` |
| `diagnosing-bugs` | `quality-diagnose-bugs` |
| `documentation-engineer` | `writing-draft-technical-docs` |
| `engineering-manager` | `delivery-manage-engineering` |
| `frontend-engineer-ts` | `development-build-react-frontends` |
| `ideation` | `research-brainstorm-ideas` |
| `interrogate-me` | `writing-interview-author` |
| `legal-advisor` | `research-review-software-legal` |
| `linux-specialist` | `infrastructure-administer-linux` |
| `mental-model` | `workflow-explain-code` |
| `ponytail-senior-engineer` | `workflow-simplify-code` |
| `product-manager` | `delivery-plan-products` |
| `project-coordinator` | `delivery-coordinate-projects` |
| `python-backend` | `development-build-python-backends` |
| `python-test-engineer` | `quality-test-python` |
| `security-specialist` | `design-secure-applications` |
| `spec-anchors` | `workflow-maintain-spec-anchors` |
| `sre-reliability` | `infrastructure-run-reliable-services` |
| `test-coordinator` | `quality-plan-testing` |
| `typescript-test-engineer` | `quality-test-typescript` |
| `ui-ux-designer` | `design-ui-ux` |
| `writing-chat-messages` | `writing-draft-chat-messages` |
| `writing-documents` | `writing-draft-long-documents` |
| `writing-short-articles` | `writing-draft-blog-posts` |

Alternatives considered:

- Keep role-based names and only prefix the writing personas: rejected because it leaves discovery inconsistent everywhere else.
- Prefix every name with the existing README section label: rejected because labels such as `management-` and `workflow-` do not clearly describe all responsibilities beneath them.
- Keep old names as aliases: rejected because duplicate skills would clutter autocomplete and make the taxonomy less effective.

### Rename sources and references without renderer changes

Rename each `shared/personas/<name>` directory, set its frontmatter `name` to the same value, and replace exact old persona references in persona handoffs, steering examples, docs, specs, and tests. The renderer already derives output paths from persona names and needs no new logic.

## Risks / Trade-offs

- [Existing slash commands stop working] → Treat the change as breaking, publish the complete map, and rely on a normal installer rerun to replace generated persona directories.
- [A textual handoff retains an old name] → Search for every old exact name after the rename and run all four installer verifiers.
- [Longer command names take more typing] → Shared prefixes improve autocomplete, and explicit suffixes reduce recall cost.
- [Some personas span domains] → Choose the prefix that best matches the persona's primary entry point; descriptions continue to cover secondary uses.

## Migration Plan

1. Rename source directories and frontmatter atomically.
2. Update all source references and verification expectations.
3. Render and verify all four tools.
4. Re-run each installer on target machines; its existing clear-and-render behavior removes deprecated generated names.

Rollback is the inverse rename map plus another installer run.

## Open Questions

None after the rename map is approved.

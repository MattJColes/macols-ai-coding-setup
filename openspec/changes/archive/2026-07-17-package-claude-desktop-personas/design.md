## Context

Claude Desktop accepts custom plugin ZIP files, and a plugin can expose many
skills from one `skills/` directory. The existing standalone-skill upload format
would require one ZIP and one upload per persona.

## Goals / Non-Goals

**Goals:**

- Produce one uploadable archive containing every shared persona.
- Keep the binary archive reproducible and detect drift in CI.
- Preserve `shared/personas/` as the only authored persona source.

**Non-Goals:**

- Automate interaction with the Claude Desktop UI.
- Add connectors, hooks, or agents to the plugin.
- Publish or version a public plugin marketplace.

## Decisions

- Use a Claude plugin rather than standalone skill ZIPs. Plugins provide the
  requested bulk installation while retaining each persona as an independently
  discoverable skill.
- Stage the plugin in a temporary directory and normalize timestamps before
  zipping. This makes byte comparison suitable for a CI freshness check.
- Commit the generated ZIP under `bundles/`. The bundle is immediately
  uploadable from a clone or GitHub checkout without requiring a local build.
- Derive a SemVer-compatible prerelease version from the packaged persona
  contents. Every persona edit changes the version without requiring a second
  manually maintained value.

## Risks / Trade-offs

- **Claude changes its plugin schema** → Keep the manifest minimal and validate
  the archive structure in the packaging script.
- **Binary diffs are opaque in review** → CI rebuilds and byte-compares the
  archive against the reviewable persona sources.
- **A maintainer forgets regeneration** → Repository guidance and CI both run
  the script's `--check` mode.

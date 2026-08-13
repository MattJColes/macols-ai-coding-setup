# claude-desktop-persona-bundle Specification

## Purpose
TBD - created by archiving change package-claude-desktop-personas. Update Purpose after archive.
## Requirements
### Requirement: All personas are packaged as one Claude plugin
The repository SHALL provide a deterministic ZIP archive whose plugin contains
every directory under `shared/personas/` as a skill and whose manifest identifies
the bundle as `macols-personas`.
<!-- anchor: claude-desktop-persona-bundle.package -->

#### Scenario: Build the Claude Desktop bundle
- **WHEN** a maintainer runs the persona packaging script
- **THEN** the checked-in bundle is replaced with a Claude plugin ZIP containing every current persona

### Requirement: Bundled skills carry the shared response-format block
The packaging script SHALL fail when `shared/steering/response-format.md` is
missing and SHALL append its contents to every packaged `SKILL.md`, mirroring
`generate_personas`, so Claude Desktop matches the CLI surfaces. The appended
block feeds the bundle revision cksum, so a change to it requires regenerating
the checked-in archive.

#### Scenario: Response format reaches Claude Desktop
- **WHEN** the bundle is unpacked and any skill is read
- **THEN** its `SKILL.md` ends with the shared `## Response Format` block

### Requirement: Stale persona bundles are detected
The packaging script SHALL provide a check mode that fails when the checked-in
archive differs from a freshly generated archive.
<!-- anchor: claude-desktop-persona-bundle.check -->

#### Scenario: Persona changes without regeneration
- **WHEN** a persona source changes but the bundle is not regenerated
- **THEN** the repository's automated bundle check fails with regeneration guidance

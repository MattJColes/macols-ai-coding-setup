## ADDED Requirements

### Requirement: All personas are packaged as one Claude plugin
The repository SHALL provide a deterministic ZIP archive whose plugin contains
every directory under `shared/personas/` as a skill and whose manifest identifies
the bundle as `macols-personas`.

#### Scenario: Build the Claude Desktop bundle
- **WHEN** a maintainer runs the persona packaging script
- **THEN** the checked-in bundle is replaced with a Claude plugin ZIP containing every current persona

### Requirement: Stale persona bundles are detected
The packaging script SHALL provide a check mode that fails when the checked-in
archive differs from a freshly generated archive.

#### Scenario: Persona changes without regeneration
- **WHEN** a persona source changes but the bundle is not regenerated
- **THEN** the repository's automated bundle check fails with regeneration guidance

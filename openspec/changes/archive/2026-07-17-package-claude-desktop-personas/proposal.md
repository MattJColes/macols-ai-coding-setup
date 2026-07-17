## Why

Personas can be installed into coding agents from this repo, but keeping the
same skills current in Claude Desktop requires packaging and uploading them by
hand. A checked-in bulk bundle makes every persona available through one
repeatable upload.

## What Changes

- Add a deterministic generator for a Claude plugin ZIP containing every
  persona as a skill.
- Check the generated ZIP into the repo so it is ready to upload to Claude
  Desktop.
- Require persona changes to regenerate the bundle and verify in CI that the
  committed archive is current.
- Document the build and Claude Desktop upload workflow.

## Capabilities

### New Capabilities

- `claude-desktop-persona-bundle`: Package all shared personas as one
  uploadable Claude plugin and detect a stale checked-in bundle.

### Modified Capabilities

None.

## Impact

- Adds one portable shell script, one generated ZIP, and one CI verification
  step.
- Updates maintainer guidance and the persona documentation.
- Requires the existing `zip` command; no project dependency is introduced.

# Evidence

## E1. Long personas are shorter

- **Claim**: architecture, audit and docs bodies each shrink by at least a quarter.
- **Command**: `wc -l config/personas/{architecture,audit,docs}/SKILL.md`
- **Expected**: 3/3 files at or under 75% of their original length (≤160, ≤150, ≤146 from 214, 200, 195). Planned as a third; revised before the run because each kept body is the workflow plus one-line pointers.
- **Recorded**: pass @ 42effe1 + working tree: 149, 137, 137 lines (3/3 within target)

## E2. Moved material still ships with every skill

- **Claim**: the new reference files land beside the rendered skill and inline into single-file outputs.
- **Command**: `HOME=$(mktemp -d) ./install.sh claudecode && ./tests/verify_install.sh claudecode` then `ls "$HOME"/.claude/skills/{architecture,audit,docs}/references` and `grep -c "^### references/" "$HOME"/.claude/agents/audit.md` (scratch `$HOME`)
- **Expected**: verifier passes; 8/8 reference files present; audit agent inlines 2/2 references.
- **Recorded**: pass @ 42effe1 + working tree: `all hard checks passed`; 8/8 reference files beside the Claude skills (also present in the Codex and ZCode skill dirs); Claude audit agent inlines 2/2. Codex/OpenCode/pi verifiers not run: could-not-check (CI install matrix covers them)

## E3. Descriptions lead with the trigger and stay valid

- **Claim**: 24/24 descriptions start with "Use", fit 1024 characters and contain no `: `.
- **Command**: `for f in config/personas/*/SKILL.md; do awk '/^description:/{sub(/^description: */,"");print;exit}' "$f"; done | awk '{n++} /^Use/ && length<=1024 && !/: /{ok++} END{print ok"/"n}'`
- **Expected**: `24/24`
- **Recorded**: pass @ 42effe1 + working tree: `24/24`; every frontmatter also parses with `yq`

## E4. Desktop bundle regenerated (C-BUNDLE-REGENERATED)

- **Claim**: the committed bundle matches the persona sources.
- **Command**: `./scripts/package_claude_desktop_personas.sh --check`
- **Expected**: exit 0.
- **Recorded**: pass @ 42effe1 + working tree: `✓ Claude Desktop persona bundle is current`

## E5. Rendering and frontmatter untouched outside descriptions

- **Claim**: only `description` lines change in frontmatter, and the renderer is untouched.
- **Command**: `git diff main -- config/personas/*/SKILL.md | grep -E '^[+-](name|agent|user-invocable|tier|allowed-tools):' | wc -l; git diff --quiet main -- lib/ config/personas/_shared config/steering && echo untouched`
- **Expected**: `0` and `untouched`.
- **Recorded**: pass @ 42effe1 + working tree: `0` and `untouched`; cdk/python still name architecture (8 mentions); `./scripts/spec_drift_gate.sh --check` all anchors healthy

#!/usr/bin/env bash
#
# Self-test for scripts/spec_drift_gate.sh.
#
# Builds a scratch git repo with one anchored function and drives the gate
# through its verdicts: healthy --check, DRIFT (code moved, spec didn't),
# quiet (code + spec moved together), DANGLING (rename), and loose (two
# matches). Requires git, jq, ast-grep, yq — skips (exit 0) when a
# dependency is missing so local runs without the toolchain stay green;
# CI installs the tools and gets the real assertions.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$(dirname "$SCRIPT_DIR")/scripts/spec_drift_gate.sh"
FAILED=0

green() { printf '\033[0;32m  ✓ %s\033[0m\n' "$1"; }
red()   { printf '\033[0;31m  ✗ %s\033[0m\n' "$1"; FAILED=1; }

for tool in git jq ast-grep yq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf '\033[1;33m⚠ %s not installed — skipping drift-gate self-test\033[0m\n' "$tool"
        exit 0
    fi
done

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/gate_test.XXXXXX")" || exit 1
trap 'rm -rf "$FIXTURE"' EXIT
cd "$FIXTURE" || exit 1

git init -q -b main .
git config user.email "gate-test@example.invalid"
git config user.name "gate test"

mkdir -p src openspec/specs/demo specs/anchors
cat > src/demo.sh <<'EOF'
#!/bin/bash
demo_fn() {
    echo "one"
}
other_fn() {
    echo "two"
}
EOF
cat > openspec/specs/demo/spec.md <<'EOF'
# Demo

## Purpose

Fixture spec.

## Requirements

### Requirement: demo_fn prints one

`demo_fn` SHALL print one.
<!-- anchor: demo.fn -->

#### Scenario: run it

- **WHEN** demo_fn runs
- **THEN** it prints one
EOF
cat > specs/anchors/demo.yml <<'EOF'
demo.fn:
  language: bash
  rule:
    kind: function_definition
    has: { field: name, regex: '^demo_fn$' }
  files: [src/demo.sh]
EOF
git add -A && git commit -qm "fixture: anchored demo_fn"
BASE_SHA=$(git rev-parse HEAD)

printf '\n=== drift gate self-test ===\n'

# 1. Hygiene passes on the pristine fixture.
if "$GATE" --check >/dev/null 2>&1; then green "--check passes when healthy"; else red "--check passes when healthy"; fi

# 2. Edit anchored code without touching the spec → DRIFT, but still exit 0.
sed 's/echo "one"/echo "uno"/' src/demo.sh > src/demo.sh.tmp && mv src/demo.sh.tmp src/demo.sh
git commit -qam "edit demo_fn body only"
OUT=$("$GATE" --base "$BASE_SHA" 2>&1); EC=$?
if [ "$EC" -eq 0 ]; then green "drift mode exits 0"; else red "drift mode exits 0 (got $EC)"; fi
if printf '%s' "$OUT" | grep -q "DRIFT.*demo.fn"; then green "body-only edit flagged as DRIFT"; else red "body-only edit flagged as DRIFT"; fi

# 3. Touch the spec section in the same range of commits → quiet.
sed 's/SHALL print one/SHALL print uno/' openspec/specs/demo/spec.md > s.tmp && mv s.tmp openspec/specs/demo/spec.md
git commit -qam "update spec section too"
OUT=$("$GATE" --base "$BASE_SHA" 2>&1)
if printf '%s' "$OUT" | grep -q "DRIFT"; then red "code+spec together stays quiet"; else green "code+spec together stays quiet"; fi

# 4. Rename the function → DANGLING (and --check fails).
sed 's/^demo_fn()/renamed_fn()/' src/demo.sh > src/demo.sh.tmp && mv src/demo.sh.tmp src/demo.sh
git commit -qam "rename demo_fn"
OUT=$("$GATE" --base "$BASE_SHA" 2>&1); EC=$?
if [ "$EC" -eq 0 ]; then green "drift mode still exits 0 on DANGLING"; else red "drift mode still exits 0 on DANGLING (got $EC)"; fi
if printf '%s' "$OUT" | grep -q "DANGLING.*demo.fn"; then green "rename flagged as DANGLING"; else red "rename flagged as DANGLING"; fi
if "$GATE" --check >/dev/null 2>&1; then red "--check fails on dangling rule"; else green "--check fails on dangling rule"; fi

# 5. Two matching sites → loose, --check fails.
git checkout -q "$BASE_SHA" -- src/demo.sh
sed 's/files: \[src\/demo.sh\]/files: [src\/*.sh]/' specs/anchors/demo.yml > a.tmp && mv a.tmp specs/anchors/demo.yml
printf 'demo_fn() {\n    echo "copy"\n}\n' > src/extra.sh
git add -A && git commit -qm "second demo_fn"
OUT=$("$GATE" --check 2>&1); EC=$?
if [ "$EC" -ne 0 ] && printf '%s' "$OUT" | grep -q "loose.*demo.fn"; then green "--check fails on loose rule"; else red "--check fails on loose rule"; fi

if [ "$FAILED" -eq 0 ]; then
    printf '\033[0;32m=== drift gate self-test: all checks passed ===\033[0m\n\n'
else
    printf '\033[0;31m=== drift gate self-test: FAILED ===\033[0m\n\n'
fi
exit "$FAILED"

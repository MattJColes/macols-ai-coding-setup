#!/usr/bin/env bash
#
# Self-test for run_python_tests in shared/post_task_checks.sh.
#
# Builds a scratch git repo with two modules and two test files, changes one
# module, and asserts that the turn-end pytest step runs ONLY the matching test
# file by default (MACOLS_PYTEST_SCOPE=changed), the whole suite under `full`,
# and nothing under `off`. A stub `pytest` on PATH records its argv.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$(dirname "$SCRIPT_DIR")/shared/post_task_checks.sh"
FAILED=0

green() { printf '\033[0;32m  ✓ %s\033[0m\n' "$1"; }
red()   { printf '\033[0;31m  ✗ %s\033[0m\n' "$1"; FAILED=1; }

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/scoped_pytest.XXXXXX")" || exit 1
trap 'rm -rf "$FIXTURE"' EXIT
cd "$FIXTURE" || exit 1

git init -q -b main .
git config user.email "scoped-test@example.invalid"
git config user.name "scoped test"

mkdir -p pkg tests stubbin
printf 'def alpha():\n    return 1\n' > pkg/alpha.py
printf 'def beta():\n    return 2\n' > pkg/beta.py
printf 'from pkg.alpha import alpha\ndef test_alpha():\n    assert alpha() == 1\n' > tests/test_alpha.py
printf 'from pkg.beta import beta\ndef test_beta():\n    assert beta() == 2\n' > tests/test_beta.py
ARGV_LOG="$FIXTURE/pytest.argv"
cat > stubbin/pytest <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$ARGV_LOG"
exit 0
STUB
chmod +x stubbin/pytest
git add -A && git commit -qm "fixture"

# The stub must win over any real pytest and over a repo .venv.
export PATH="$FIXTURE/stubbin:$PATH"

# One change to a non-test module: only its matching test should run.
printf 'def alpha():\n    return 11\n' > pkg/alpha.py

run_step() {  # <scope> — runs the step in a subshell and prints its warnings
    (
        export MACOLS_PYTEST_SCOPE="$1"
        # shellcheck source=/dev/null
        source "$LIB"
        run_python_tests
        printf '%s\n' "${WARNINGS[@]}"
    )
}

: > "$ARGV_LOG"
out=$(run_step changed)
if grep -q "tests/test_alpha.py" "$ARGV_LOG"; then
    green "changed: runs the matching test file"
else
    red "changed: matching test file not in pytest argv ($(tr '\n' ' ' < "$ARGV_LOG"))"
fi
if grep -q "test_beta.py" "$ARGV_LOG"; then
    red "changed: unrelated test file was run"
else
    green "changed: unrelated test file not run"
fi
if grep -q "no:cacheprovider" "$ARGV_LOG"; then
    green "changed: cache provider disabled"
else
    red "changed: cache provider not disabled"
fi

: > "$ARGV_LOG"
out=$(run_step full)
if [ -s "$ARGV_LOG" ] && ! grep -q "test_" "$ARGV_LOG"; then
    green "full: runs pytest with no path scoping"
else
    red "full: expected an unscoped invocation ($(tr '\n' ' ' < "$ARGV_LOG"))"
fi

: > "$ARGV_LOG"
out=$(run_step off)
if [ ! -s "$ARGV_LOG" ] && printf '%s' "$out" | grep -q "MACOLS_PYTEST_SCOPE=off"; then
    green "off: skips with a warning"
else
    red "off: pytest ran or warning missing"
fi

# A change with no matching test: nothing runs, and the warning says so.
git checkout -q -- pkg/alpha.py
printf 'def gamma():\n    return 3\n' > pkg/gamma.py
: > "$ARGV_LOG"
out=$(run_step changed)
if [ ! -s "$ARGV_LOG" ] && printf '%s' "$out" | grep -q "no impacted tests"; then
    green "changed: no matching test → skipped with warning"
else
    red "changed: expected skip for an unmatched module ($(tr '\n' ' ' < "$ARGV_LOG"))"
fi

exit $FAILED

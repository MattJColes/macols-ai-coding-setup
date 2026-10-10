#!/bin/bash
#
# Self-test for the commit checkpoint's lgtmaybe stage:
#   - checkpoint-only: a turn-end run and MACOLS_LGREVIEW=off do nothing
#   - a clean tree (nothing uncommitted) does nothing
#   - findings at/above MACOLS_LGREVIEW_BLOCK (default high) block the commit;
#     lower severities are an advisory warning
#   - the floor moves (critical / none) and an empty findings array is a pass
#   - an unparsable or timed-out review is a warning, never a blocker
# The checks tree is copied into the fixture so the module resolves the
# wrapper the way production does, and the wrapper itself is a stub — this
# needs bash, git and jq only, and makes no model calls.
# shellcheck disable=SC1090,SC1091,SC2016,SC2034  # paths are computed; check() evals literal conditions
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
FAILED=0

green() { printf '\033[0;32m  ✓ %s\033[0m\n' "$1"; }
red()   { printf '\033[0;31m  ✗ %s\033[0m\n' "$1"; FAILED=1; }
check() { if eval "$2"; then green "$1"; else red "$1"; fi; }

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/lgtmaybe_review.XXXXXX")" || exit 1
trap 'rm -rf "$FIXTURE"' EXIT
export MACOLS_TRUST_ALL=1 MACOLS_CHECK_LOG=off MACOLS_DUPLICATION=off

# The checks tree, laid out as installed: repo/bin + repo/hooks/checks. The
# stage resolves ../bin/macols-lgtmaybe relative to its own file, so the stub
# takes the place of the real wrapper.
mkdir -p "$FIXTURE/tree/bin" "$FIXTURE/tree/hooks/checks"
cp "$REPO"/hooks/checks/*.sh "$FIXTURE/tree/hooks/checks/"
cp "$REPO/hooks/pre_commit_check.sh" "$FIXTURE/tree/hooks/"
cp "$REPO/bin/macols-lgtmaybe" "$FIXTURE/tree/bin/"

# Canned reviewer body: emits $STUB_OUTPUT (default: one high and one medium
# finding) after $STUB_SLEEP seconds when set.
make_stub() {
    local out='[{"path":"a.py","line":3,"severity":"high","title":"h","body":"b"},{"path":"a.py","line":7,"severity":"medium","title":"m","body":"b"}]'
    if [ -n "${STUB_OUTPUT+x}" ]; then out="$STUB_OUTPUT"; fi
    {
        printf '#!/bin/bash\n'
        [ -n "${STUB_SLEEP:-}" ] && printf 'sleep %s\n' "$STUB_SLEEP"
        printf 'printf %%s %q\n' "$out"
    } > "$FIXTURE/tree/bin/macols-lgtmaybe"
    chmod +x "$FIXTURE/tree/bin/macols-lgtmaybe"
}

new_repo() {  # <dir> — a git repo with one committed file and one changed
    mkdir -p "$1" && cd "$1" || exit 1
    git init -q -b main .
    git config user.email "lgt@example.invalid"
    git config user.name "lgt"
    printf 'def run():\n    return 1\n' > a.py
    git add -A && git commit -qm base
    printf 'def run(cmd):\n    os.system(cmd)\n' >> a.py
}

CHECKPOINT_MODE=1
# shellcheck source=../hooks/checks/post_task.sh
source "$FIXTURE/tree/hooks/checks/post_task.sh" || exit 1
setup_timeout_cmd

run_stage() {  # sets CRITICAL_ISSUES / WARNINGS like the battery does
    CRITICAL_ISSUES=()
    WARNINGS=()
    run_lgtmaybe_review
}

echo "lgtmaybe checkpoint stage"

# Turn-end mode: never runs.
new_repo "$FIXTURE/turnend"
CHECKPOINT_MODE=0 run_stage
check "turn-end run is a no-op" '[ ${#CRITICAL_ISSUES[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]'

# Opt-out: never runs.
CHECKPOINT_MODE=1 MACOLS_LGREVIEW=off run_stage
check "MACOLS_LGREVIEW=off is a no-op" '[ ${#CRITICAL_ISSUES[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]'

# Clean tree: nothing to review.
git add -A && git commit -qm clean
run_stage
check "clean tree is a no-op" '[ ${#CRITICAL_ISSUES[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]'

# Blocking: high blocks by default, medium rides as an advisory.
make_stub
printf 'x\n' >> a.py
run_stage
check "high finding blocks by default" '[ ${#CRITICAL_ISSUES[@]} -eq 1 ]'
check "blocking issue names the finding" '[[ "${CRITICAL_ISSUES[0]:-}" == *"a.py:3 [high] h"* ]]'
check "medium finding is advisory" '[ ${#WARNINGS[@]} -eq 1 ] && [[ "${WARNINGS[0]:-}" == *"1 advisory"* ]]'

# Floor: critical — high stops blocking, both findings go advisory.
MACOLS_LGREVIEW_BLOCK=critical run_stage
check "high does not block at floor=critical" '[ ${#CRITICAL_ISSUES[@]} -eq 0 ]'
check "both findings advisory at floor=critical" '[[ "${WARNINGS[0]:-}" == *"2 advisory"* ]]'

# Floor: none — nothing blocks.
MACOLS_LGREVIEW_BLOCK=none run_stage
check "nothing blocks at floor=none" '[ ${#CRITICAL_ISSUES[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 1 ]'
unset MACOLS_LGREVIEW_BLOCK

# Critical blocks too.
STUB_OUTPUT='[{"path":"a.py","line":3,"severity":"critical","title":"c","body":"b"}]' make_stub
run_stage
check "critical finding blocks" '[ ${#CRITICAL_ISSUES[@]} -eq 1 ]'

# Empty findings array: a pass, no noise.
STUB_OUTPUT='[]' make_stub
run_stage
check "empty findings array is a pass" '[ ${#CRITICAL_ISSUES[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]'

# Unparsable output: warning, never a blocker.
STUB_OUTPUT='not json at all' make_stub
run_stage
check "unparsable output warns without blocking" '[ ${#CRITICAL_ISSUES[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 1 ]'

# Timeout: warning, never a blocker. Needs timeout/gtimeout (coreutils on macOS).
if [ -n "$TIMEOUT_CMD" ]; then
    STUB_OUTPUT='[]' STUB_SLEEP=5 make_stub
    MACOLS_LGREVIEW_TIMEOUT=1 run_stage
    check "timed-out review warns without blocking" '[ ${#CRITICAL_ISSUES[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 1 ] && [[ "${WARNINGS[0]:-}" == *"timed out"* ]]'
else
    printf '\033[1;33m  ⚠ timed-out review: skipped, no timeout/gtimeout (brew install coreutils)\033[0m\n'
fi

# Missing timeout must never launch an unbounded reviewer.
TIMEOUT_CMD="" run_stage
check "missing timeout warns without running review" '[ ${#CRITICAL_ISSUES[@]} -eq 0 ] && [[ "${WARNINGS[0]:-}" == *"timeout/gtimeout unavailable"* ]]'

# Exercise the real entry point after a skip and after disabling review.
if [ -n "$TIMEOUT_CMD" ]; then
    new_repo "$FIXTURE/checkpoint"
    STUB_OUTPUT='not json' make_stub
    out=$(bash "$FIXTURE/tree/hooks/pre_commit_check.sh" 'git commit -m test')
    check "unavailable review remains non-blocking" '[ -z "$out" ]'
    check "unavailable review is not cached" '[ ! -f .git/macols-last-checkpoint ]'
    make_stub
    out=$(bash "$FIXTURE/tree/hooks/pre_commit_check.sh" 'git commit -m test')
    check "restored reviewer blocks unchanged tree" '[[ "$out" == *"a.py:3 [high] h"* ]]'
    MACOLS_LGREVIEW=off bash "$FIXTURE/tree/hooks/pre_commit_check.sh" 'git commit -m test' >/dev/null
    out=$(bash "$FIXTURE/tree/hooks/pre_commit_check.sh" 'git commit -m test')
    check "reenabled reviewer ignores disabled-review cache" '[[ "$out" == *"a.py:3 [high] h"* ]]'
fi

echo "lgtmaybe installer"
mkdir -p "$FIXTURE/installer"
cat > "$FIXTURE/installer/check.sh" <<'INSTALLER'
#!/bin/bash
set -eu
REPO_ROOT="$1"
ZAI_KEY_FILE="$2/key"
ZAI_CHOICE_FILE="$2/choice"
INSTALL_ACTIONS="$2/actions"
GREEN= BLUE= YELLOW= NC=
unset ZAI_API_KEY
source "$REPO_ROOT/lib/lgtmaybe.sh"
lgtmaybe() { :; }
mkdir() { [ "$*" = "-p $HOME/.local/bin" ] || command mkdir "$@"; }
ln() { printf 'symlink\n' >> "$INSTALL_ACTIONS"; }
case "$3" in
    existing|rotation)
        printf 'dummy-old-key' > "$ZAI_KEY_FILE"
        chmod 644 "$ZAI_KEY_FILE"
        if [ "$3" = rotation ]; then
            ZAI_API_KEY=dummy-new-key
            printf 'off' > "$ZAI_CHOICE_FILE"
        fi
        ensure_lgtmaybe >/dev/null || exit 1
        [ "$(ls -l "$ZAI_KEY_FILE" | cut -c1-10)" = '-rw-------' ]
        if [ "$3" = rotation ]; then
            [ "$(cat "$ZAI_KEY_FILE")" = dummy-new-key ]
            [ ! -e "$ZAI_CHOICE_FILE" ]
        fi ;;
    skip)
        ensure_lgtmaybe >/dev/null || true
        [ "$(cat "$ZAI_CHOICE_FILE")" = off ]
        [ ! -e "$INSTALL_ACTIONS" ]
        ensure_lgtmaybe >/dev/null || true
        [ ! -e "$INSTALL_ACTIONS" ]
        printf 'passed' > "$2/result" ;;
esac
INSTALLER
mkdir -p "$FIXTURE/installer/existing" "$FIXTURE/installer/rotation" "$FIXTURE/installer/skip"
check "existing stored key is restricted to mode 600" "bash '$FIXTURE/installer/check.sh' '$REPO' '$FIXTURE/installer/existing' existing"
check "environment key rotates securely and clears remembered opt-out" "bash '$FIXTURE/installer/check.sh' '$REPO' '$FIXTURE/installer/rotation' rotation"
if [ "$(uname -s)" = Darwin ]; then
    printf '\n' | script -q /dev/null bash "$FIXTURE/installer/check.sh" "$REPO" "$FIXTURE/installer/skip" skip >/dev/null 2>&1
else
    printf '\n' | script -q -c "bash $(printf '%q ' "$FIXTURE/installer/check.sh" "$REPO" "$FIXTURE/installer/skip" skip)" /dev/null >/dev/null 2>&1
fi
check "blank interactive opt-out is remembered and stops installer actions" "[ -f '$FIXTURE/installer/skip/result' ]"

if [ "$FAILED" -eq 0 ]; then
    printf '\033[0;32mAll lgtmaybe checkpoint tests passed.\033[0m\n'
    exit 0
fi
printf '\033[0;31mSome lgtmaybe checkpoint tests FAILED.\033[0m\n'
exit 1

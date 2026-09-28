#!/bin/bash
#
# Shared post-task hook (Stop / turn-end) — used by every CLI.
#
# Runs the turn-end battery in hooks/checks/post_task.sh and, when it finds
# problems, hands them back to the MODEL as one more step of work.
#
# Usage: post_task_hook.sh [--format claude|codex|zcode|text]
#   claude, codex — {"decision":"block","reason":…}: the agent keeps going
#   zcode         — {"continue":true, additionalContext}
#   text          — plain report on stdout (OpenCode plugin, pi/omp extension)
#
# When it runs:
# - Only when code changed since the battery last ran (a fingerprint of the
#   working tree, stored in .git/macols-last-check). Q&A turns after an edit
#   no longer re-run everything, and an agent that was shown findings and
#   changed nothing is allowed to stop, so the hook cannot loop.
# - Never when the tool says this stop is already a hook-driven continuation
#   (stop_hook_active) — one nudge per turn, then the user decides.
# - pytest/jest/vitest/go test are scoped to what the changed files reach.
#   The full suite is CI's and the pre-push hook's job.
#   MACOLS_PYTEST_SCOPE=full|changed|off overrides the Python scope.
#
# Only critical findings (failing tests, lint/type/gate errors) are sent to the
# model; notes such as "pytest not installed" print only with
# MACOLS_CHECKS_VERBOSE=1.
#
# Referenced in place from the repo (not copied); the check libraries sit in
# hooks/checks/ and the output adapters in hooks/adapters/ next to this file.
# Override with MACOLS_HOOKS_DIR.
#
set -eo pipefail

HOOKS_DIR="${MACOLS_HOOKS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
SHARED_HOOKS_ROOT="$HOOKS_DIR"
# shellcheck source=adapters/hook_output.sh
source "$HOOKS_DIR/adapters/hook_output.sh"

FORMAT="text"
while [ $# -gt 0 ]; do
    case "$1" in
        --format) FORMAT="${2:-text}"; shift 2 ;;
        --format=*) FORMAT="${1#--format=}"; shift ;;
        *) shift ;;
    esac
done

HOOK_INPUT=""
if [ ! -t 0 ]; then
    HOOK_INPUT=$(cat 2>/dev/null || true)
fi
if [ -n "$HOOK_INPUT" ] && command -v jq &> /dev/null; then
    HOOK_CWD=$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
    [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ] && cd "$HOOK_CWD"
    # A continuation this hook already caused: let the agent stop.
    if [ "$(printf '%s' "$HOOK_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ]; then
        exit 0
    fi
fi

# shellcheck source=checks/post_task.sh
source "$HOOKS_DIR/checks/post_task.sh"

# Change gates: code must have changed, and changed since the last run.
code_changed || exit 0
changes_since_last_check || exit 0

run_post_task_checks || { record_check_fingerprint; exit 0; }
record_check_fingerprint

if [ "${MACOLS_CHECKS_VERBOSE:-0}" = "1" ] && [ ${#WARNINGS[@]} -gt 0 ]; then
    printf 'Validation notes:\n' >&2
    printf '  - %s\n' "${WARNINGS[@]}" >&2
fi

TRUST_NOTE=""
if [ "${UNTRUSTED_SKIPPED:-0}" = "1" ]; then
    TRUST_NOTE="Tests, eslint, tsc, mypy, cdk synth, go and layer checks were skipped: $(project_root) is not a trusted project, and those run code the repo controls. To enable them, run $(dirname "$SHARED_HOOKS_ROOT")/bin/macols-trust in the repo, or add its path to $MACOLS_TRUST_FILE."
fi

if [ ${#CRITICAL_ISSUES[@]} -eq 0 ]; then
    # Tell the person once per repo why most checks did not run.
    notice_file="$(git rev-parse --git-dir 2>/dev/null)/macols-untrusted-notice"
    if [ -n "$TRUST_NOTE" ] && [ ! -f "$notice_file" ]; then
        : > "$notice_file" 2>/dev/null || true
        emit_user_notice "$FORMAT" "$TRUST_NOTE"
    fi
    exit 0
fi

REPORT="Turn-end checks found problems in your changes. Fix them, re-run the failing check, then finish:"$'\n'
for issue in "${CRITICAL_ISSUES[@]}"; do
    REPORT+="- $issue"$'\n'
done
[ -n "$TRUST_NOTE" ] && REPORT+="Note: $TRUST_NOTE"$'\n'

emit_stop_feedback "$FORMAT" "$REPORT"
exit 0

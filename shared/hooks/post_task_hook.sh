#!/bin/bash
#
# Shared post-task hook (Stop / turn-end) — used by every CLI.
#
# Thin wrapper that sources shared/post_task_checks.sh.
#
# ADVISORY + CHANGE-GATED:
# - Skips entirely when the turn didn't touch code (clean working tree of code
#   files) — no point re-running the whole suite after a Q&A or docs-only turn.
# - When code did change, runs the checks and REPORTS findings to stderr, but
#   never blocks the stop. Per-edit checks already run via the post-code hook;
#   a hard block re-runs the full suite and traps on pre-existing failures in
#   code you never touched. Reporting keeps the signal without the friction.
#
# This script is referenced in place from the repo (it is not copied), so the
# shared library sits one directory up. Override with MACOLS_SHARED_DIR.
#
set -eo pipefail

SHARED_DIR="${MACOLS_SHARED_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Drain stdin (tools send JSON; we don't need any field here).
if [ ! -t 0 ]; then
    cat > /dev/null 2>&1 || true
fi

source "$SHARED_DIR/post_task_checks.sh"

# Change gate: skip the whole battery when no code changed this turn.
code_changed || exit 0

run_post_task_checks || exit 0  # Nothing to check

# Advisory: surface findings to stderr (shown in the transcript), never block.
if [ ${#CRITICAL_ISSUES[@]} -gt 0 ]; then
    echo "Post-task validation found issues (advisory — not blocking):" >&2
    for issue in "${CRITICAL_ISSUES[@]}"; do
        echo "  - $issue" >&2
    done
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo "Validation notes:" >&2
    for warning in "${WARNINGS[@]}"; do
        echo "  - $warning" >&2
    done
fi

exit 0

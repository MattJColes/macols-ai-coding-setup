#!/bin/bash
#
# lgtmaybe_review.sh — the commit checkpoint's AI review stage.
#
# Sourced by post_task.sh AFTER common.sh, so it sees the battery helpers
# (add_critical_issue / add_warning / TIMEOUT_CMD) and the git working
# directory. Not meant to be executed directly.
#
# One AI review pass over the uncommitted diff before the commit lands,
# driven by bin/macols-lgtmaybe (the GLM reviewer lib/lgtmaybe.sh sets up).
# Checkpoint-only, so the turn-end battery stays fast. Findings at or above
# MACOLS_LGREVIEW_BLOCK (default high) block the commit; lower severities and
# every skip (no key, no CLI, no diff, unparsable output) are warnings — a
# reviewer being unavailable must never block, the deterministic gates own
# that. MACOLS_LGREVIEW=off skips the stage; MACOLS_LGREVIEW_TIMEOUT (default
# 600s) bounds the review.

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script must be sourced, not executed directly." >&2
    exit 1
fi

run_lgtmaybe_review() {
    [ "${CHECKPOINT_MODE:-0}" = "1" ] || return 0
    [ "${MACOLS_LGREVIEW:-on}" != "off" ] || return 0
    git rev-parse -q --verify HEAD >/dev/null 2>&1 || return 0
    git diff HEAD --quiet 2>/dev/null && return 0
    [ -n "${TIMEOUT_CMD:-}" ] || { add_warning "lgtmaybe: timeout/gtimeout unavailable; install coreutils to enable bounded review"; return 0; }

    local wrapper
    wrapper="$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")/../bin/macols-lgtmaybe"
    [ -x "$wrapper" ] || { add_warning "lgtmaybe: bin/macols-lgtmaybe not found at $wrapper"; return 0; }

    local out ec=0
    out=$("$TIMEOUT_CMD" "${MACOLS_LGREVIEW_TIMEOUT:-600}" "$wrapper" --uncommitted --format json 2>/dev/null) || ec=$?
    [ "$ec" -eq 124 ] && { add_warning "lgtmaybe: timed out after ${MACOLS_LGREVIEW_TIMEOUT:-600}s (MACOLS_LGREVIEW_TIMEOUT raises it)"; return 0; }

    local findings=""
    if printf '%s' "$out" | jq -e 'type == "array"' >/dev/null 2>&1; then
        findings="$out"
    elif printf '%s' "$out" | jq -e '.findings | type == "array"' >/dev/null 2>&1; then
        findings="$(printf '%s' "$out" | jq '.findings')"
    fi
    [ -z "$findings" ] && { add_warning "lgtmaybe: no parsable review output (exit $ec)"; return 0; }

    local floor="${MACOLS_LGREVIEW_BLOCK:-high}"
    local detail="" bn=0
    if [ "$floor" != "none" ]; then
        # shellcheck disable=SC2016  # the jq program is meant to stay unexpanded
        detail=$(printf '%s' "$findings" | jq -r --arg floor "$floor" '
            [ .[] | select(($floor == "critical" and .severity == "critical")
                or ($floor == "high" and (.severity == "high" or .severity == "critical"))) ]
            | .[] | "  \(.path):\(.line) [\(.severity)] \(.title)"')
        bn=$(printf '%s\n' "$detail" | grep -c '^  ' || true)
    fi
    if [ "$bn" -gt 0 ]; then
        add_critical_issue "lgtmaybe: $bn AI-review finding(s) at/above $floor on the uncommitted diff"$'\n'"$detail"$'\n'"Fix: address each finding (or refute it). Full text: macols-lgtmaybe --uncommitted. MACOLS_LGREVIEW_BLOCK=none / MACOLS_LGREVIEW=off retune or skip."
    fi
    # Everything the floor excluded — including severities above the default
    # floor when the user tightened it — rides along as an advisory.
    local an
    an=$(( $(printf '%s' "$findings" | jq 'length') - bn ))
    [ "$an" -gt 0 ] && add_warning "lgtmaybe: $an advisory finding(s) below MACOLS_LGREVIEW_BLOCK=$floor"
    return 0
}

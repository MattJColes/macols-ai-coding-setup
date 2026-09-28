#!/bin/bash
#
# pre_deploy_check.sh <command-string> — protocol-neutral core of the cdk
# deploy/destroy guard, shared by every tool's pre-tool wiring:
#
#   • pre_deploy_hook.sh          (Claude Code / Codex PreToolUse JSON protocol)
#   • adapters/opencode_plugin.mjs (OpenCode tool.execute.before)
#   • pi-checks.ts                (omp tool_call event)
#
# Prints the confirmation reason to stdout when the command is a
# `cdk deploy` / `cdk destroy` (including `npx cdk deploy`, `cdk deploy --all`,
# `cdk destroy '*'`); prints nothing for anything else (`cdk diff`/`cdk synth`
# pass untouched). Always exits 0 — callers gate on "output non-empty", which
# survives runtimes that do not surface exit codes.
#
# For a deploy it also runs `cdk diff` and puts what matters for review in the
# reason: resources removed or replaced, and IAM or security-group changes.
# Statement counts and template noise are left out. The diff runs the CDK app
# (repo code), so it only runs in trusted projects; MACOLS_DEPLOY_DIFF=off
# skips it and MACOLS_DEPLOY_DIFF_TIMEOUT (default 240s) bounds it.
#
set -eo pipefail

COMMAND="${1:-}"
HOOKS_DIR="${MACOLS_HOOKS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

echo "$COMMAND" | grep -Eq '(^|[^[:alnum:]_-])cdk[[:space:]]+(deploy|destroy)([[:space:]]|$)' || exit 0

REASON="cdk deploy/destroy detected. Renaming a Construct ID forces resource REPLACEMENT/DESTRUCTION — confirm you reviewed 'cdk diff' for replacements (look for 'requires replacement' and resources marked for removal) before approving."

# Summarise `cdk diff` output: removals, replacements, IAM and security-group
# changes, per stack.
summarise_diff() {
    awk '
        /^Stack / { stack = $2; next }
        /^IAM Statement Changes/ || /^IAM Policy Changes/ { if (!(stack in iam)) { iam[stack] = 1; print "IAM changes in " stack } next }
        /^Security Group Changes/ { if (!(stack in sg)) { sg[stack] = 1; print "security-group changes in " stack } next }
        /^\[-\] / { sub(/^\[-\] /, ""); print "remove: " stack " " $0; next }
        /^\[[~+]\] / { res = $0; sub(/^\[[~+]\] /, "", res); reported = 0
                       if ($NF == "replace") { print "replace: " stack " " res; reported = 1 }
                       next }
        /requires replacement|may cause replacement/ { if (res != "" && !reported) { print "replace: " stack " " res; reported = 1 } }
    '
}

deploy_diff_note() {
    [ "${MACOLS_DEPLOY_DIFF:-on}" = "off" ] && return 0
    # `cd <dir> && cdk deploy …` runs the app from <dir>.
    local dir
    dir=$(printf '%s' "$COMMAND" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^[:space:];&|]+)[[:space:]]*&&.*/\1/p')
    if [ -n "$dir" ]; then
        dir="${dir/#\~/$HOME}"
        cd "$dir" 2>/dev/null || return 0
    fi
    [ -f cdk.json ] || return 0

    # shellcheck source=checks/common.sh
    source "$HOOKS_DIR/checks/common.sh"
    if ! project_trusted; then
        printf ' cdk diff was not run: %s is not a trusted project (bin/macols-trust).' "$(project_root)"
        return 0
    fi
    local cdk=""
    if [ -x node_modules/.bin/cdk ]; then cdk=node_modules/.bin/cdk
    elif command -v cdk &>/dev/null; then cdk=cdk
    else
        printf ' cdk diff was not run: no cdk CLI here.'
        return 0
    fi

    local -a args=(diff --no-color)
    local profile
    profile=$(printf '%s' "$COMMAND" | sed -nE 's/.*--profile[[:space:]=]+([^[:space:];&|]+).*/\1/p')
    [ -n "$profile" ] && args+=(--profile "$profile")

    setup_timeout_cmd
    local out ec=0
    out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD ${MACOLS_DEPLOY_DIFF_TIMEOUT:-240}} "$cdk" "${args[@]}" 2>&1) || ec=$?
    if [ "$ec" -ne 0 ]; then
        [ "$ec" -eq 124 ] && out="timed out after ${MACOLS_DEPLOY_DIFF_TIMEOUT:-240}s"
        printf ' cdk diff could not run (exit %s), so nothing was checked: %s' "$ec" \
            "$(printf '%s\n' "$out" | tail -3 | tr '\n' ' ')"
        return 0
    fi

    local findings n
    findings=$(printf '%s\n' "$out" | summarise_diff)
    if [ -z "$findings" ]; then
        printf ' cdk diff: no removals, replacements, IAM or security-group changes.'
        return 0
    fi
    n=$(printf '%s\n' "$findings" | wc -l | tr -d ' ')
    printf ' cdk diff found %s change(s) to review:\n%s' "$n" "$(printf '%s\n' "$findings" | head -20 | sed 's/^/  - /')"
    [ "$n" -gt 20 ] && printf '\n  - …and %s more (run cdk diff for all of them)' "$((n - 20))"
    return 0
}

if echo "$COMMAND" | grep -Eq '(^|[^[:alnum:]_-])cdk[[:space:]]+deploy([[:space:]]|$)'; then
    REASON+="$(deploy_diff_note || true)"
fi
printf '%s\n' "$REASON"
exit 0

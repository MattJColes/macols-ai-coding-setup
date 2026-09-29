#!/bin/bash
#
# Shared pre-deploy hook (PreToolUse on Bash) — used by Claude Code, Codex and ZCode.
# (OpenCode and omp wire the same guard through their plugin/extension, all
# via the shared matcher in pre_deploy_check.sh.)
#
# Guards `cdk deploy` / `cdk destroy`. The biggest CDK-specific danger is a
# Construct ID rename that looks like a harmless refactor but forces resource
# replacement/destruction. This hook pauses such commands and asks the user to
# confirm; for a deploy the prompt carries the removals, replacements and
# IAM/security-group changes from `cdk diff` (see pre_deploy_check.sh).
#
# Hard safety belongs in hooks, not the steering file — steering rules are
# model-interpreted and degrade as context grows.
#
# PreToolUse protocol: emit JSON on stdout with hookSpecificOutput.
#   permissionDecision "ask"   -> surface a confirmation prompt to the user
#                                 (Claude Code, ZCode)
#   permissionDecision "deny"  -> refuse this call with a reason (Codex)
# Anything else (or no output) falls through to normal permission handling.
#
# Codex has no "ask" for hooks and fails OPEN on unsupported decisions, so with
# --format codex the guard denies the first attempt with an instruction to get
# the user's confirmation, and lets an identical retry within 15 minutes
# through (the same confirm-by-retry the OpenCode plugin uses).
#
# pi-yaml-hooks (--format pi-yaml) can only block: exit 2 with the reason on
# stderr. It gets the same confirm-by-retry as Codex. Its payload names the
# tool "bash" and carries the command in tool_args.command.
#
# Usage: pre_deploy_hook.sh [--format claude|codex|zcode|pi-yaml]
#
# The tool passes JSON via stdin with tool_name and tool_input.command.
#
set -eo pipefail

# Resolved before the cd into the session's cwd below.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FORMAT="claude"
case "${1:-}" in
    --format) FORMAT="${2:-claude}" ;;
    --format=*) FORMAT="${1#--format=}" ;;
esac

HOOK_INPUT=$(cat)

# Extract the Bash command being run.
COMMAND=""
TOOL_NAME=""
if command -v jq &> /dev/null; then
    TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
    COMMAND=$(echo "$HOOK_INPUT" | jq -r '(.tool_input // .tool_args).command // empty' 2>/dev/null || true)
    HOOK_CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
    [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ] && cd "$HOOK_CWD"
else
    TOOL_NAME=$(echo "$HOOK_INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || true)
    COMMAND=$(echo "$HOOK_INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//' || true)
fi

# Only act on Bash tool calls (pi-yaml-hooks reports the lowercase host name).
[ "$FORMAT" = "pi-yaml" ] && [ "$TOOL_NAME" = "bash" ] && TOOL_NAME="Bash"
if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

# Delegate matching to the shared, protocol-neutral core (single source for
# the cdk regex + reason across all four tools' wirings).
if [ "$FORMAT" = "codex" ] || [ "$FORMAT" = "pi-yaml" ]; then
    # Confirm-by-retry: an identical retry of a command this guard denied in
    # the last 15 minutes passes without re-running the check (or cdk diff).
    STATE_DIR="${TMPDIR:-/tmp}/macols-predeploy-$(id -u)"
    mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"
    KEY=$(printf '%s' "$COMMAND" | git hash-object --stdin 2>/dev/null || printf '%s' "$COMMAND" | cksum | cut -d' ' -f1)
    find "$STATE_DIR" -type f -mmin +15 -delete 2>/dev/null || true
    if [ -f "$STATE_DIR/$KEY" ]; then
        rm -f "$STATE_DIR/$KEY"
        exit 0
    fi
fi
REASON="$(bash "$SCRIPT_DIR/pre_deploy_check.sh" "$COMMAND")"
if [ -n "$REASON" ]; then
    DECISION="ask"
    if [ "$FORMAT" = "codex" ] || [ "$FORMAT" = "pi-yaml" ]; then
        : > "$STATE_DIR/$KEY"
        DECISION="deny"
        REASON="$REASON Ask the user to confirm, then re-run the exact same command to proceed."
    fi
    if [ "$FORMAT" = "pi-yaml" ]; then
        printf '%s\n' "$REASON" >&2
        exit 2
    fi
    if command -v jq &> /dev/null; then
        jq -n --arg reason "$REASON" --arg decision "$DECISION" '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: $decision,
                permissionDecisionReason: $reason
            }
        }'
    else
        python3 -c "import json,sys; print(json.dumps({'hookSpecificOutput':{'hookEventName':'PreToolUse','permissionDecision':sys.argv[2],'permissionDecisionReason':sys.argv[1]}}))" "$REASON" "$DECISION"
    fi
    exit 0
fi

# Not a deploy/destroy — no opinion, fall through to normal handling.
exit 0

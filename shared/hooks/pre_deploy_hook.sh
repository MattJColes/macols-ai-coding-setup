#!/bin/bash
#
# Shared pre-deploy hook (PreToolUse on Bash) — used by Claude Code and Codex.
# (OpenCode and omp wire the same guard through their plugin/extension, all
# via the shared matcher in pre_deploy_check.sh.)
#
# Guards `cdk deploy` / `cdk destroy`. The biggest CDK-specific danger is a
# Construct ID rename that looks like a harmless refactor but forces resource
# replacement/destruction. This hook pauses such commands and asks the user to
# confirm they reviewed `cdk diff` for replacements before proceeding.
#
# Hard safety belongs in hooks, not the steering file — steering rules are
# model-interpreted and degrade as context grows.
#
# PreToolUse protocol: emit JSON on stdout with hookSpecificOutput.
#   permissionDecision "ask"   -> surface a confirmation prompt to the user
#   permissionDecision "allow" -> proceed without prompting
# Anything else (or no output) falls through to normal permission handling.
#
# The tool passes JSON via stdin with tool_name and tool_input.command.
#
set -eo pipefail

HOOK_INPUT=$(cat)

# Extract the Bash command being run.
COMMAND=""
TOOL_NAME=""
if command -v jq &> /dev/null; then
    TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
    COMMAND=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
else
    TOOL_NAME=$(echo "$HOOK_INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || true)
    COMMAND=$(echo "$HOOK_INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//' || true)
fi

# Only act on Bash tool calls.
if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

# Delegate matching to the shared, protocol-neutral core (single source for
# the cdk regex + reason across all four tools' wirings).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REASON="$(bash "$SCRIPT_DIR/pre_deploy_check.sh" "$COMMAND")"
if [ -n "$REASON" ]; then
    if command -v jq &> /dev/null; then
        jq -n --arg reason "$REASON" '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "ask",
                permissionDecisionReason: $reason
            }
        }'
    else
        python3 -c "import json,sys; print(json.dumps({'hookSpecificOutput':{'hookEventName':'PreToolUse','permissionDecision':'ask','permissionDecisionReason':sys.argv[1]}}))" "$REASON"
    fi
    exit 0
fi

# Not a deploy/destroy — no opinion, fall through to normal handling.
exit 0

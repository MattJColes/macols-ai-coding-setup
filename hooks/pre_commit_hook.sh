#!/bin/bash
#
# pre_commit_hook.sh — PreToolUse(Bash) wrapper around pre_commit_check.sh for
# Claude Code, Codex and ZCode. A failing checkpoint denies the `git commit`
# call with the findings as the reason, which the model reads next.
#
# Usage: pre_commit_hook.sh [--format claude|codex|zcode|pi-yaml]
#   pi-yaml — a pi-yaml-hooks `tool.before.bash` action: the payload carries
#             tool_name "bash" and tool_args.command, and a block is the
#             reason on stderr with exit 2. Mind omp's 20s synchronous budget.
#
set -eo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMAT="claude"
case "${1:-}" in
    --format) FORMAT="${2:-claude}" ;;
    --format=*) FORMAT="${1#--format=}" ;;
esac
HOOK_INPUT=$(cat)
command -v jq &>/dev/null || exit 0

TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name // empty')
[ "$TOOL_NAME" = "Bash" ] || { [ "$FORMAT" = "pi-yaml" ] && [ "$TOOL_NAME" = "bash" ]; } || exit 0
COMMAND=$(printf '%s' "$HOOK_INPUT" | jq -r '(.tool_input // .tool_args).command // empty')
[ -n "$COMMAND" ] || exit 0
HOOK_CWD=$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd // empty')
[ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ] && cd "$HOOK_CWD"

REASON="$(bash "$HOOKS_DIR/pre_commit_check.sh" "$COMMAND")"
[ -n "$REASON" ] || exit 0

if [ "$FORMAT" = "pi-yaml" ]; then
    printf '%s\n' "$REASON" >&2
    exit 2
fi

jq -n --arg reason "$REASON" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
    }
}'

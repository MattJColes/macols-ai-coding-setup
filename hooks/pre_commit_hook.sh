#!/bin/bash
#
# pre_commit_hook.sh — PreToolUse(Bash) wrapper around pre_commit_check.sh for
# Claude Code, Codex and ZCode. A failing checkpoint denies the `git commit`
# call with the findings as the reason, which the model reads next.
#
# Usage: pre_commit_hook.sh [--format claude|codex|zcode]
#
set -eo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_INPUT=$(cat)
command -v jq &>/dev/null || exit 0

[ "$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name // empty')" = "Bash" ] || exit 0
COMMAND=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // empty')
[ -n "$COMMAND" ] || exit 0
HOOK_CWD=$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd // empty')
[ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ] && cd "$HOOK_CWD"

REASON="$(bash "$HOOKS_DIR/pre_commit_check.sh" "$COMMAND")"
[ -n "$REASON" ] || exit 0

jq -n --arg reason "$REASON" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
    }
}'

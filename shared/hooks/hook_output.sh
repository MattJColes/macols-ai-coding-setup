#!/bin/bash
#
# Hook output adapters — turn a plain-text report into the shape each tool
# feeds back to the model. Sourced by post_code_hook.sh and post_task_hook.sh.
#
# Formats (the --format flag each installer writes into the hook command):
#   claude — Claude Code hooks  (code.claude.com/docs/en/hooks)
#   codex  — Codex CLI hooks    (codex-rs/hooks: same JSON as Claude)
#   zcode  — ZCode CLI hooks    (zai-org/ZCode apps/zcode-cli README)
#   text   — plain text; the OpenCode plugin and pi/omp extension inject it
#
# Tool hook output limits: Codex spills model-visible context over ~2.5k
# tokens and ZCode caps stdout at 32 KiB, so reports are truncated here.
#

HOOK_REPORT_MAX_CHARS="${HOOK_REPORT_MAX_CHARS:-8000}"

_truncate_report() {
    local text="$1"
    if [ "${#text}" -gt "$HOOK_REPORT_MAX_CHARS" ]; then
        printf '%s\n[... truncated; run the checks locally for the full list]' "${text:0:$HOOK_REPORT_MAX_CHARS}"
    else
        printf '%s' "$text"
    fi
}

# JSON-encode stdin as a string (jq, falling back to python3, then node).
_json_string() {
    if command -v jq &> /dev/null; then
        jq -Rs .
    elif command -v python3 &> /dev/null; then
        python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
    else
        node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.stringify(s)))'
    fi
}

# emit_post_tool_context <format> <text> — PostToolUse: add model-visible
# context to the tool result without blocking.
emit_post_tool_context() {
    local format="$1" text
    text=$(_truncate_report "$2")
    case "$format" in
        claude|codex|zcode)
            printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' \
                "$(printf '%s' "$text" | _json_string)" ;;
        *)
            printf '%s\n' "$text" ;;
    esac
}

# emit_stop_feedback <format> <text> — Stop: ask for one more model step with
# the findings. Loop safety is the caller's job (stop_hook_active + the change
# fingerprint); Claude Code, ZCode and omp also cap repeated continuations.
#   claude, codex — {"decision":"block","reason":…} keeps the agent going with
#                   the reason as its next instruction
#   zcode         — {"continue":true, hookSpecificOutput.additionalContext}
#   text          — plain text for the plugin/extension to inject
emit_stop_feedback() {
    local format="$1" text json
    text=$(_truncate_report "$2")
    json=$(printf '%s' "$text" | _json_string)
    case "$format" in
        claude|codex)
            printf '{"decision":"block","reason":%s}\n' "$json" ;;
        zcode)
            printf '{"continue":true,"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":%s}}\n' "$json" ;;
        *)
            printf '%s\n' "$text" ;;
    esac
}

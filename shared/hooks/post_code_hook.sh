#!/bin/bash
#
# Shared post-code hook (PostToolUse / file-write) — used by every CLI.
#
# Thin wrapper that sources shared/post_code_checks.sh and runs a fast,
# file-scoped lint/type-check on the edited file. Advisory: prints findings,
# always exits 0, never blocks the tool. The full test/security battery runs
# once at turn end via post_task_hook.sh.
#
# The edited file path is resolved from, in order:
#   1. the first CLI argument (Pi's extension passes it positionally), then
#   2. a best-effort probe of the JSON the tool sends on stdin — Claude Code,
#      Codex and OpenCode use different shapes, so we try the common locations.
# If no path resolves, the per-edit check is a no-op.
#
# This script is referenced in place from the repo (it is not copied), so the
# shared library sits one directory up. Override with MACOLS_SHARED_DIR if you
# relocate it.
#
set -eo pipefail

SHARED_DIR="${MACOLS_SHARED_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

FILE_PATH="${1:-}"

# Only read stdin when no path was passed positionally (avoids blocking on a tty).
if [ -z "$FILE_PATH" ] && [ ! -t 0 ]; then
    HOOK_INPUT=$(cat 2>/dev/null || true)
    if [ -n "$HOOK_INPUT" ] && command -v jq &> /dev/null; then
        FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '
            .tool_input.file_path // .tool_input.path // .tool_input.filename //
            .input.file_path // .input.path // .file_path // .path // empty' 2>/dev/null || true)
    fi
fi

export FILE_PATH

source "$SHARED_DIR/post_code_checks.sh"
run_post_code_checks
exit 0

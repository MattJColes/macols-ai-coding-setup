#!/bin/bash
#
# Shared post-code hook (PostToolUse / file-write) — used by every CLI.
#
# Runs the fast file-scoped checks in shared/post_code_checks.sh on each edited
# file and hands any findings back to the MODEL in the shape its tool reads.
# Plain stdout on exit 0 goes to a debug log in Claude Code, Codex and ZCode,
# which is why findings used to be invisible; each format below is the one the
# tool injects into the model's context. Never blocks the edit.
#
# Usage: post_code_hook.sh [--format claude|codex|zcode|text] [file ...]
#   claude, codex, zcode — JSON hookSpecificOutput.additionalContext on stdout
#   text                 — plain findings on stdout (pi/omp extension and the
#                          OpenCode plugin add them to the tool result)
#
# Edited paths come from, in order: positional args, then the hook JSON on
# stdin — Claude's tool_input.file_path / notebook_path, OpenCode's filePath,
# or the "*** Add File:" / "*** Update File:" headers of a Codex apply_patch
# (whose tool_input.command is the patch text).
#
# Referenced in place from the repo (not copied), so the shared library sits
# one directory up. Override with MACOLS_SHARED_DIR if you relocate it.
#
set -eo pipefail

SHARED_DIR="${MACOLS_SHARED_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=hook_output.sh
source "$SHARED_DIR/hooks/hook_output.sh"

FORMAT="text"
declare -a FILES=()
while [ $# -gt 0 ]; do
    case "$1" in
        --format) FORMAT="${2:-text}"; shift 2 ;;
        --format=*) FORMAT="${1#--format=}"; shift ;;
        *) FILES+=("$1"); shift ;;
    esac
done

# Only read stdin when no path was passed positionally (avoids blocking on a tty).
if [ ${#FILES[@]} -eq 0 ] && [ ! -t 0 ]; then
    HOOK_INPUT=$(cat 2>/dev/null || true)
    if [ -n "$HOOK_INPUT" ] && command -v jq &> /dev/null; then
        HOOK_CWD=$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
        [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ] && cd "$HOOK_CWD"
        while IFS= read -r f; do
            [ -n "$f" ] && FILES+=("$f")
        done < <(printf '%s' "$HOOK_INPUT" | jq -r '
            (.tool_input // .input // {}) as $in
            | ([$in.file_path, $in.notebook_path, $in.filePath, $in.path, $in.filename,
                .file_path, .path] | map(select(type == "string" and . != "")))
              + ([$in.command, $in.patch, $in.patchText, $in.input]
                 | map(select(type == "string"))
                 | map(split("\n")[]
                       | select(test("^\\*\\*\\* (Add File|Update File|Move to): "))
                       | sub("^\\*\\*\\* [A-Za-z ]+: "; "")))
            | unique | .[]' 2>/dev/null || true)
    fi
fi

[ ${#FILES[@]} -eq 0 ] && exit 0

source "$SHARED_DIR/post_code_checks.sh"

REPORT=""
for FILE_PATH in "${FILES[@]}"; do
    export FILE_PATH
    out=$(run_post_code_checks)
    [ -n "$out" ] && REPORT+="$out"$'\n'
done

[ -z "$REPORT" ] && exit 0
emit_post_tool_context "$FORMAT" "Post-edit checks found issues in the file you just changed. Fix them before moving on:"$'\n'"$REPORT"
exit 0

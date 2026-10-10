#!/bin/bash
#
# pre_commit_check.sh <command-string> — protocol-neutral core of the local
# checkpoint loop: when the agent runs `git commit`, run the checkpoint
# battery (the whole test suite of each affected package, lint, types, layer
# rules, and the project's CHECKPOINT command) before the commit lands.
#
# Prints the findings when the checkpoint fails and nothing otherwise, and
# always exits 0; callers deny/block the commit on non-empty output. Shared by
# pre_commit_hook.sh (Claude Code, Codex, ZCode), the OpenCode plugin and the
# pi extension.
#
# Skipped when: the command is not a commit, it passes --no-verify (the user
# chose to bypass hooks), MACOLS_CHECKPOINT=off, the project is not trusted
# (the checkpoint runs repo code), or nothing changed since the last passing
# checkpoint.
#
set -eo pipefail

COMMAND="${1:-}"
HOOKS_DIR="${MACOLS_HOOKS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

[ "${MACOLS_CHECKPOINT:-on}" = "off" ] && exit 0
printf '%s' "$COMMAND" | grep -Eq '(^|[;&|(][[:space:]]*|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit([[:space:]]|$)' || exit 0
printf '%s' "$COMMAND" | grep -Eq -- '--no-verify|(^|[[:space:]])-n([[:space:]]|$)' && exit 0

# Honour `git -C <dir> commit`.
dir=$(printf '%s' "$COMMAND" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+)[[:space:]]+commit.*/\1/p')
[ -n "$dir" ] && [ -d "$dir" ] && cd "$dir"
git rev-parse --is-inside-work-tree &>/dev/null || exit 0
cd "$(git rev-parse --show-toplevel)"

# shellcheck source=checks/post_task.sh
source "$HOOKS_DIR/checks/post_task.sh"
project_trusted || exit 0
code_changed || exit 0

# Skip when the tree matches the last passing checkpoint.
fp_file="$(git rev-parse --git-dir)/macols-last-checkpoint"
# The AI review is not deterministic: cache a pass only when it cannot run
# (opted out, no lgtmaybe CLI, or no Z.AI key), so machines without it keep
# the cache and a reviewer that comes back reviews the unchanged tree.
review_ready() {
    [ "${MACOLS_LGREVIEW:-on}" != off ] && command -v lgtmaybe &>/dev/null &&
        { [ -n "${ZAI_API_KEY:-}" ] || [ -s "${ZAI_KEY_FILE:-$HOME/.config/macols/zai-api-key}" ]; }
}
fp=""
review_ready || fp=$(_check_fingerprint || true)
[ -n "$fp" ] && [ -f "$fp_file" ] && [ "$(cat "$fp_file")" = "$fp" ] && exit 0

CHECKPOINT_MODE=1 MACOLS_PYTEST_SCOPE=full
export CHECKPOINT_MODE MACOLS_PYTEST_SCOPE
# shellcheck disable=SC2034  # read by the sourced post_task.sh checks
MAX_TEST_TIME="${MACOLS_CHECKPOINT_TIMEOUT:-900}"
run_post_task_checks || exit 0

if [ ${#CRITICAL_ISSUES[@]} -eq 0 ]; then
    [ -n "$fp" ] && printf '%s' "$fp" > "$fp_file"
    exit 0
fi

printf 'Commit blocked: the checkpoint checks failed. Fix these, then commit again (MACOLS_CHECKPOINT=off skips the checkpoint):\n'
printf -- '- %s\n' "${CRITICAL_ISSUES[@]}"
exit 0

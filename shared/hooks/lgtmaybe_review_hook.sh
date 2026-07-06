#!/bin/bash
#
# lgtmaybe review hook (Claude Code Stop / turn-end) — ADVISORY.
#
# Runs the lgtmaybe PR reviewer over the uncommitted changes the agent just made,
# using Bedrock Claude Opus 4.6 with ambient AWS credentials (nothing secret to
# store — auth resolves from ~/.aws / SSO). Findings are printed to stderr (shown
# in the transcript); the stop is NEVER blocked.
#
# Distinct from post_task_hook.sh (the fast deterministic battery): this is a
# slower, networked LLM review, kept as its own hook so it can be toggled
# independently. It fans out Opus calls per category, so it only runs when code
# actually changed (shared code_changed gate) and applies a severity floor.
#
# Knobs (env):
#   LGTMAYBE_HOOK_ENABLED       "false" to disable entirely (default: true)
#   LGTMAYBE_PROVIDER           anthropic | bedrock (default: bedrock). Written
#                               by install_claudecode.sh's LGTMAYBE_CONFIG rc
#                               block; shared with the code-reviewer persona.
#   LGTMAYBE_MODEL              model id for the provider (shared knob, same
#                               rc block)
#   LGTMAYBE_HOOK_MODEL         hook-specific model override; wins over
#                               LGTMAYBE_MODEL (default when both unset:
#                               bedrock/us.anthropic.claude-opus-4-6;
#                               swap us. → eu./apac. for your AWS region)
#   LGTMAYBE_HOOK_MIN_SEVERITY  severity floor (default: medium)
#
# The CLI is installed automatically by install_claudecode.sh (ensure_lgtmaybe);
# manual fallback: `uv tool install 'lgtmaybe[bedrock]'` (or pipx). Bedrock
# needs ambient AWS creds with bedrock:InvokeModel* on the model; anthropic
# needs ANTHROPIC_API_KEY.
#
# Referenced in place from the repo; the shared library sits one directory up.
# Override with MACOLS_SHARED_DIR.
#
set -eo pipefail

# Opt-out toggle.
[ "${LGTMAYBE_HOOK_ENABLED:-true}" = "true" ] || exit 0

# Need the CLI on PATH; degrade silently if it isn't installed.
command -v lgtmaybe >/dev/null 2>&1 || exit 0

SHARED_DIR="${MACOLS_SHARED_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Drain stdin (tools send JSON; no field needed here).
if [ ! -t 0 ]; then
    cat > /dev/null 2>&1 || true
fi

# Reuse the shared change gate: skip unless code changed in the cwd repo.
# Source only the small common helpers (not the full turn-end battery) — we just
# need code_changed here.
# shellcheck source=../checks_common.sh
source "$SHARED_DIR/checks_common.sh"
code_changed || exit 0

PROVIDER="${LGTMAYBE_PROVIDER:-bedrock}"
if [ "$PROVIDER" = "anthropic" ]; then
    DEFAULT_MODEL="claude-sonnet-4-6"
else
    DEFAULT_MODEL="bedrock/us.anthropic.claude-opus-4-6"
fi
MODEL="${LGTMAYBE_HOOK_MODEL:-${LGTMAYBE_MODEL:-$DEFAULT_MODEL}}"
MIN_SEVERITY="${LGTMAYBE_HOOK_MIN_SEVERITY:-medium}"

# Advisory review of the agent's uncommitted edits. lgtmaybe exits 0 even with
# findings (non-zero only on a real error); capture output and never block.
review_output=$(lgtmaybe review --uncommitted \
    --provider "$PROVIDER" --model "$MODEL" \
    --min-severity "$MIN_SEVERITY" --format human 2>&1) || true

if [ -n "$review_output" ]; then
    echo "lgtmaybe review (advisory — not blocking):" >&2
    echo "$review_output" >&2
fi

exit 0

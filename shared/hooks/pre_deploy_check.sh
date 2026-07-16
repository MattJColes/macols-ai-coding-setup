#!/bin/bash
#
# pre_deploy_check.sh <command-string> — protocol-neutral core of the cdk
# deploy/destroy guard, shared by every tool's pre-tool wiring:
#
#   • pre_deploy_hook.sh          (Claude Code / Codex PreToolUse JSON protocol)
#   • opencode_post_code_plugin.mjs (OpenCode tool.execute.before)
#   • pi-checks.ts                (omp tool_call event)
#
# Prints the confirmation reason to stdout when the command is a
# `cdk deploy` / `cdk destroy` (including `npx cdk deploy`, `cdk deploy --all`,
# `cdk destroy '*'`); prints nothing for anything else (`cdk diff`/`cdk synth`
# pass untouched). Always exits 0 — callers gate on "output non-empty", which
# survives runtimes that do not surface exit codes.
#
set -eo pipefail

COMMAND="${1:-}"

if echo "$COMMAND" | grep -Eq '(^|[^[:alnum:]_-])cdk[[:space:]]+(deploy|destroy)([[:space:]]|$)'; then
    echo "cdk deploy/destroy detected. Renaming a Construct ID forces resource REPLACEMENT/DESTRUCTION — confirm you reviewed 'cdk diff' for replacements (look for 'requires replacement' and resources marked for removal) before approving."
fi

exit 0

#!/bin/bash
#
# pre_deploy_check.sh <command-string> — protocol-neutral core of the cdk
# deploy/destroy guard, shared by every tool's pre-tool wiring:
#
#   • pre_deploy_hook.sh          (Claude Code / Codex PreToolUse JSON protocol)
#   • adapters/opencode_plugin.mjs (OpenCode tool.execute.before)
#   • pi-checks.ts                (omp tool_call event)
#
# Prints the confirmation reason to stdout when the command is a
# `cdk deploy` / `cdk destroy` (including `npx cdk deploy`, `cdk deploy --all`,
# `cdk destroy '*'`); prints nothing for anything else (`cdk diff`/`cdk synth`
# pass untouched). Always exits 0 — callers gate on "output non-empty", which
# survives runtimes that do not surface exit codes.
#
# For a deploy it also runs `cdk diff` and puts what matters for review in the
# reason: resources removed or replaced, and IAM or security-group changes.
# Statement counts and template noise are left out. The diff runs the CDK app
# (repo code), so it only runs in trusted projects; MACOLS_DEPLOY_DIFF=off
# skips it and MACOLS_DEPLOY_DIFF_TIMEOUT (default 240s) bounds it.
#
set -eo pipefail

COMMAND="${1:-}"
HOOKS_DIR="${MACOLS_HOOKS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Prints `deploy` or `destroy` when the command RUNS that cdk verb, else nothing.
# Only a command word counts: the phrase inside a quoted string, a heredoc
# body, a grep pattern or a commit message is not a deploy, and prompting on it
# stalled unattended agent sessions until a human woke up to approve a grep.
cdk_verb() {
    CDK_GUARD_COMMAND="$COMMAND" python3 - <<'PY'
import os
import re

cmd = os.environ.get("CDK_GUARD_COMMAND", "")

# Drop heredoc bodies: everything between a `<<WORD` line and its terminator.
out, lines, i = [], cmd.split("\n"), 0
while i < len(lines):
    out.append(lines[i])
    m = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", lines[i])
    if m:
        i += 1
        while i < len(lines) and lines[i].strip() != m.group(1):
            i += 1
    i += 1
text = "\n".join(out)

# Blank out quoted strings so their contents never read as commands.
text = re.sub(r"'[^']*'", "''", text)
text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)

CDK_VERBS = {"deploy", "destroy", "diff", "synth", "synthesize", "ls", "list", "bootstrap", "init", "doctor",
             "context", "docs", "watch", "import", "acknowledge", "notices", "metadata", "gc", "rollback", "migrate",
             "drift", "refactor"}
WRAPPERS = {"npx", "pnpm", "yarn", "bunx", "exec", "time", "sudo", "env", "command", "nice", "nohup"}
for segment in re.split(r"[\n;&|()`]|\$\(", text):
    tokens = segment.split()
    while tokens and (re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=\S*", tokens[0]) or tokens[0] in WRAPPERS
                      or tokens[0].startswith("-")):
        tokens.pop(0)
    if tokens[:2] in (["uv", "run"], ["poetry", "run"], ["npm", "exec"]):
        tokens = tokens[2:]
    if not tokens or os.path.basename(tokens[0]) != "cdk":
        continue
    # Global options may take values (`--profile dev`), so the verb is the
    # first known cdk verb rather than the first non-option token.
    verb = next((t for t in tokens[1:] if t in CDK_VERBS), "")
    if verb in ("deploy", "destroy"):
        print(verb)
        break
PY
}

VERB="$(cdk_verb)"
[ -n "$VERB" ] || exit 0

REASON="cdk deploy/destroy detected. Renaming a Construct ID forces resource REPLACEMENT/DESTRUCTION — confirm you reviewed 'cdk diff' for replacements (look for 'requires replacement' and resources marked for removal) before approving."

# Summarise `cdk diff` output: removals, replacements, IAM and security-group
# changes, per stack.
summarise_diff() {
    awk '
        /^Stack / { stack = $2; next }
        /^IAM Statement Changes/ || /^IAM Policy Changes/ { if (!(stack in iam)) { iam[stack] = 1; print "IAM changes in " stack } next }
        /^Security Group Changes/ { if (!(stack in sg)) { sg[stack] = 1; print "security-group changes in " stack } next }
        /^\[-\] / { sub(/^\[-\] /, ""); print "remove: " stack " " $0; next }
        /^\[[~+]\] / { res = $0; sub(/^\[[~+]\] /, "", res); reported = 0
                       if ($NF == "replace") { print "replace: " stack " " res; reported = 1 }
                       next }
        /requires replacement|may cause replacement/ { if (res != "" && !reported) { print "replace: " stack " " res; reported = 1 } }
    '
}

deploy_diff_note() {
    [ "${MACOLS_DEPLOY_DIFF:-on}" = "off" ] && return 0
    # `cd <dir> && cdk deploy …` runs the app from <dir>.
    local dir
    dir=$(printf '%s' "$COMMAND" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^[:space:];&|]+)[[:space:]]*&&.*/\1/p')
    if [ -n "$dir" ]; then
        dir="${dir/#\~/$HOME}"
        cd "$dir" 2>/dev/null || return 0
    fi
    [ -f cdk.json ] || return 0

    # shellcheck source=checks/common.sh
    source "$HOOKS_DIR/checks/common.sh"
    if ! project_trusted; then
        printf ' cdk diff was not run: %s is not a trusted project (bin/macols-trust).' "$(project_root)"
        return 0
    fi
    local cdk=""
    if [ -x node_modules/.bin/cdk ]; then cdk=node_modules/.bin/cdk
    elif command -v cdk &>/dev/null; then cdk=cdk
    else
        printf ' cdk diff was not run: no cdk CLI here.'
        return 0
    fi

    local -a args=(diff --no-color)
    local profile
    profile=$(printf '%s' "$COMMAND" | sed -nE 's/.*--profile[[:space:]=]+([^[:space:];&|]+).*/\1/p')
    [ -n "$profile" ] && args+=(--profile "$profile")

    setup_timeout_cmd
    local out ec=0
    out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD ${MACOLS_DEPLOY_DIFF_TIMEOUT:-240}} "$cdk" "${args[@]}" 2>&1) || ec=$?
    if [ "$ec" -ne 0 ]; then
        [ "$ec" -eq 124 ] && out="timed out after ${MACOLS_DEPLOY_DIFF_TIMEOUT:-240}s"
        printf ' cdk diff could not run (exit %s), so nothing was checked: %s' "$ec" \
            "$(printf '%s\n' "$out" | tail -3 | tr '\n' ' ')"
        return 0
    fi

    local findings n
    findings=$(printf '%s\n' "$out" | summarise_diff)
    if [ -z "$findings" ]; then
        printf ' cdk diff: no removals, replacements, IAM or security-group changes.'
        return 0
    fi
    n=$(printf '%s\n' "$findings" | wc -l | tr -d ' ')
    printf ' cdk diff found %s change(s) to review:\n%s' "$n" "$(printf '%s\n' "$findings" | head -20 | sed 's/^/  - /')"
    [ "$n" -gt 20 ] && printf '\n  - …and %s more (run cdk diff for all of them)' "$((n - 20))"
    return 0
}

if [ "$VERB" = deploy ]; then
    REASON+="$(deploy_diff_note || true)"
fi
printf '%s\n' "$REASON"
exit 0

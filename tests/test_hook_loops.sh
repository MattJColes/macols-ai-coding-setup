#!/usr/bin/env bash
#
# Self-test for the hook feedback-loop plumbing:
#   - run_post_task_checks logs one line per check plus a total, and
#     bin/macols-check-stats summarises the log
#   - pytest-testmon in the venv switches turn-end selection to --testmon (and
#     --testmon-noselect at the checkpoint)
#   - a checkpoint failure the name-based selection would have missed is
#     recorded as an escape
#   - go test covers the whole changed module at turn end
#   - the pre-deploy guard summarises `cdk diff` for a deploy, and says why
#     when it doesn't run it
#   - the pre-tool hooks speak the pi-yaml-hooks contract (--format pi-yaml):
#     a block is the reason on stderr with exit 2
# Everything the checks call (pytest, python, go, cdk) is a stub on PATH or in
# a scratch .venv, so this needs bash, git and jq only.
# shellcheck disable=SC1090,SC2034  # $LIB is computed; check() evals conditions that read $out/$esc/$stats
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
LIB="$REPO/hooks/checks/post_task.sh"
FAILED=0

green() { printf '\033[0;32m  ✓ %s\033[0m\n' "$1"; }
red()   { printf '\033[0;31m  ✗ %s\033[0m\n' "$1"; FAILED=1; }
check() { if eval "$2"; then green "$1"; else red "$1"; fi; }

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/hook_loops.XXXXXX")" || exit 1
trap 'rm -rf "$FIXTURE"' EXIT
export MACOLS_TRUST_ALL=1 MACOLS_TRUST_FILE="$FIXTURE/trusted" MACOLS_DUPLICATION=off
mkdir -p "$FIXTURE/stubbin"
export PATH="$FIXTURE/stubbin:$PATH"

new_repo() {  # <dir>
    mkdir -p "$1" && cd "$1" || exit 1
    git init -q -b main .
    git config user.email "hook-loops@example.invalid"
    git config user.name "hook loops"
}

# ── Check log and macols-check-stats ─────────────────────────────────────────
echo "check log"
new_repo "$FIXTURE/log"
printf '#!/bin/bash\necho hi\n' > run.sh
git add -A && git commit -qm fixture
printf '#!/bin/bash\necho changed\n' > run.sh
( source "$LIB"; run_post_task_checks )
( source "$LIB"; CHECKPOINT_MODE=1 run_post_task_checks )
log=.git/macols-checks.jsonl
check "every line is JSON" "jq -e . '$log' >/dev/null"
check "turn and checkpoint totals logged" \
    "[ \"\$(jq -r 'select(.check == \"total\") | .loop' '$log' | sort | tr '\n' ' ')\" = 'checkpoint turn ' ]"
check "per-check lines carry ms and result" \
    "jq -e 'select(.check == \"file_length_check\") | (.ms | type == \"number\") and .result == \"pass\"' '$log' >/dev/null"
printf '{"ts":%s,"repo":"x","loop":"checkpoint","check":"python_tests","ms":1500,"result":"fail","escaped":["root: tests/test_b.py::test_b"]}\n' "$(date +%s)" >> "$log"
echo 'not json' >> "$log"
stats=$("$REPO/bin/macols-check-stats")
check "stats table lists the checks" "printf '%s' \"\$stats\" | grep -Eq '^checkpoint +python_tests +1 +1\.5 +1\.5 +100 +1 +1\$'"
check "stats skips unparseable lines" "printf '%s' \"\$stats\" | grep -q '^turn *total'"
check "stats --escapes lists the escape" "'$REPO/bin/macols-check-stats' --escapes | grep -q 'tests/test_b.py::test_b'"
MACOLS_CHECK_LOG=off bash -c "source '$LIB'; log_check_run turn x 1 pass"
check "MACOLS_CHECK_LOG=off writes nothing" "! grep -q '\"check\":\"x\"' '$log'"

# ── pytest-testmon and escapes ───────────────────────────────────────────────
echo "python selection"
new_repo "$FIXTURE/py"
mkdir -p pkg tests .venv/bin
printf 'def alpha():\n    return 1\n' > pkg/alpha.py
printf 'def test_alpha():\n    pass\n' > tests/test_alpha.py
printf 'def test_beta():\n    pass\n' > tests/test_beta.py
printf '.venv/\n' > .gitignore
ARGV="$FIXTURE/pytest.argv"
cat > .venv/bin/pytest <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$ARGV"
if [ -n "\${PYTEST_FAIL:-}" ]; then
    printf 'FAILED tests/test_alpha.py::test_alpha - assert 1 == 2\nFAILED tests/test_beta.py::test_beta - assert 0\n'
    exit 1
fi
exit 0
STUB
chmod +x .venv/bin/pytest
git add -A && git commit -qm fixture
printf 'def alpha():\n    return 2\n' > pkg/alpha.py

: > "$ARGV"
( source "$LIB"; run_python_tests )
check "no testmon: name-based selection" "grep -q 'tests/test_alpha.py' '$ARGV' && ! grep -q testmon '$ARGV'"

printf '#!/bin/sh\nexit 0\n' > .venv/bin/python && chmod +x .venv/bin/python
: > "$ARGV"
( source "$LIB"; run_python_tests )
check "testmon installed: --testmon, no file list" "grep -q -- '--testmon' '$ARGV' && ! grep -q 'test_alpha' '$ARGV'"
: > "$ARGV"
( source "$LIB"; CHECKPOINT_MODE=1 run_python_tests )
check "checkpoint with testmon: full run refreshes the map" "grep -q -- '--testmon-noselect' '$ARGV'"
: > "$ARGV"
( source "$LIB"; MACOLS_TESTMON=off run_python_tests )
check "MACOLS_TESTMON=off: name-based" "grep -q 'tests/test_alpha.py' '$ARGV' && ! grep -q testmon '$ARGV'"

rm .venv/bin/python
esc=$(source "$LIB"; CHECKPOINT_MODE=1 PYTEST_FAIL=1 run_python_tests; printf '%s\n' "${ESCAPED_TESTS[@]}")
check "checkpoint failure outside the selection is an escape" "printf '%s' \"\$esc\" | grep -qx 'root: tests/test_beta.py::test_beta'"
check "checkpoint failure inside the selection is not" "! printf '%s' \"\$esc\" | grep -q test_alpha"

# ── Go test scope ────────────────────────────────────────────────────────────
echo "go scope"
new_repo "$FIXTURE/go"
mkdir -p a b
printf 'module example.com/m\n\ngo 1.22\n' > go.mod
printf 'package a\n' > a/a.go
printf 'package b\n' > b/b.go
git add -A && git commit -qm fixture
printf 'package a\n\nvar X = 1\n' > a/a.go
GOARGV="$FIXTURE/go.argv"
cat > "$FIXTURE/stubbin/go" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GOARGV"
exit 0
STUB
sed 's/"\$\*"/"golangci-lint \$*"/' "$FIXTURE/stubbin/go" > "$FIXTURE/stubbin/golangci-lint"
chmod +x "$FIXTURE/stubbin/go" "$FIXTURE/stubbin/golangci-lint"
: > "$GOARGV"
( source "$LIB"; run_go_checks )
check "turn end tests the whole module" "grep -qx 'test ./...' '$GOARGV'"
check "lint stays on the changed package" "grep -qx 'golangci-lint run ./a' '$GOARGV'"
: > "$GOARGV"
( source "$LIB"; MACOLS_GO_TEST_SCOPE=changed run_go_checks )
check "MACOLS_GO_TEST_SCOPE=changed tests the changed package" "grep -qx 'test ./a' '$GOARGV'"
rm "$FIXTURE/stubbin/go" "$FIXTURE/stubbin/golangci-lint"

# ── Pre-deploy cdk diff ──────────────────────────────────────────────────────
echo "pre-deploy diff"
new_repo "$FIXTURE/cdk"
mkdir -p infra
printf '{"app":"true"}\n' > infra/cdk.json
cat > "$FIXTURE/stubbin/cdk" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CDK_ARGV"
[ -n "${CDK_FAIL:-}" ] && { echo "Unable to resolve AWS account"; exit 1; }
[ -n "${CDK_CLEAN:-}" ] && { printf 'Stack Api\nThere were no differences\n'; exit 0; }
cat <<'EOF'
Stack Api
IAM Statement Changes
┌───┬──────────┬────────┐
│   │ Resource │ Effect │
└───┴──────────┴────────┘
Resources
[-] AWS::S3::Bucket Uploads Uploads1234 destroy
[~] AWS::DynamoDB::Table Orders OrdersABCD
 └─ [~] TableName (requires replacement)
[~] AWS::Lambda::Function Fn Fn5678
 └─ [~] Code
Stack Web
Security Group Changes
Resources
[~] AWS::EC2::Instance Box Box99 replace
EOF
STUB
chmod +x "$FIXTURE/stubbin/cdk"
export CDK_ARGV="$FIXTURE/cdk.argv"
cd infra || exit 1
out=$(bash "$REPO/hooks/pre_deploy_check.sh" "npx cdk deploy --all --profile prod")
check "diff: removal listed" "printf '%s' \"\$out\" | grep -q 'remove: Api AWS::S3::Bucket Uploads Uploads1234'"
check "diff: property replacement listed" "printf '%s' \"\$out\" | grep -q 'replace: Api AWS::DynamoDB::Table Orders'"
check "diff: resource replacement listed" "printf '%s' \"\$out\" | grep -q 'replace: Web AWS::EC2::Instance Box'"
check "diff: IAM and security groups listed" "printf '%s' \"\$out\" | grep -q 'IAM changes in Api' && printf '%s' \"\$out\" | grep -q 'security-group changes in Web'"
check "diff: in-place update not listed" "! printf '%s' \"\$out\" | grep -q 'Lambda'"
check "diff: --profile passed through" "grep -q -- '--profile prod' '$CDK_ARGV'"
out=$(CDK_CLEAN=1 bash "$REPO/hooks/pre_deploy_check.sh" "cdk deploy")
check "clean diff says so" "printf '%s' \"\$out\" | grep -q 'no removals, replacements'"
out=$(CDK_FAIL=1 bash "$REPO/hooks/pre_deploy_check.sh" "cdk deploy")
check "failed diff says nothing was checked" "printf '%s' \"\$out\" | grep -q 'could not run (exit 1)'"
rm -f "$CDK_ARGV"
out=$(bash "$REPO/hooks/pre_deploy_check.sh" "cdk destroy Api")
check "destroy: prompt without diff" "[ -n \"\$out\" ] && [ ! -f '$CDK_ARGV' ]"
out=$(MACOLS_TRUST_ALL=0 bash "$REPO/hooks/pre_deploy_check.sh" "cdk deploy")
check "untrusted: diff not run, and said" "printf '%s' \"\$out\" | grep -q 'not a trusted project' && [ ! -f '$CDK_ARGV' ]"
cd .. || exit 1
out=$(bash "$REPO/hooks/pre_deploy_check.sh" "cd infra && cdk deploy")
check "cd <dir> && cdk deploy diffs in <dir>" "printf '%s' \"\$out\" | grep -q 'remove: Api'"
out=$(bash "$REPO/hooks/pre_deploy_check.sh" "cdk diff")
check "cdk diff itself passes untouched" "[ -z \"\$out\" ]"

# ── pi-yaml-hooks contract ───────────────────────────────────────────────────
echo "pi-yaml-hooks contract"
pi_yaml() {  # <hook> <command> — run a hook on a tool.before.bash payload; sets $ec, prints stderr
    ec=0
    jq -n --arg c "$2" --arg d "$PWD" '{event: "tool.before.bash", tool_name: "bash", tool_args: {command: $c}, cwd: $d}' \
        | TMPDIR="$FIXTURE" bash "$REPO/hooks/$1" --format pi-yaml >/dev/null 2>"$FIXTURE/stderr" || ec=$?
    cat "$FIXTURE/stderr"
}
out=$(pi_yaml pre_deploy_hook.sh "cdk destroy Api"; echo "ec=$ec")
check "deploy guard blocks with exit 2 and the reason on stderr" \
    "printf '%s' \"\$out\" | grep -q 're-run the exact same command' && printf '%s' \"\$out\" | grep -q 'ec=2\$'"
out=$(pi_yaml pre_deploy_hook.sh "cdk destroy Api"; echo "ec=$ec")
check "deploy guard lets the identical retry through" "[ \"\$out\" = 'ec=0' ]"
new_repo "$FIXTURE/commit"
mkdir -p .macols && printf 'CHECKPOINT="echo integration broke; exit 1"\n' > .macols/checks.conf
printf 'echo a\n' > a.sh && git add -A && git commit -qm fixture && printf 'echo b\n' > a.sh
out=$(pi_yaml pre_commit_hook.sh "git commit -am wip"; echo "ec=$ec")
check "checkpoint blocks the commit with exit 2 and the findings on stderr" \
    "printf '%s' \"\$out\" | grep -q 'integration broke' && printf '%s' \"\$out\" | grep -q 'ec=2\$'"
out=$(pi_yaml pre_commit_hook.sh "git status"; echo "ec=$ec")
check "other commands pass" "[ \"\$out\" = 'ec=0' ]"
out=$(printf '{"tool_name":"bash","tool_args":{"command":"git commit"}}' | bash "$REPO/hooks/pre_commit_hook.sh" --format claude)
check "--format claude ignores the lowercase pi-yaml payload" "[ -z \"\$out\" ]"

exit $FAILED

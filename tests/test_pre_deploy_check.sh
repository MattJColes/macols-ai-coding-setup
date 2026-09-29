#!/bin/bash
# Cases for hooks/pre_deploy_check.sh: real deploy/destroy commands
# must prompt; the phrase appearing as data (quotes, heredocs, patterns) must not.
set -uo pipefail
CHECK="$(cd "$(dirname "$0")/.." && pwd)/hooks/pre_deploy_check.sh"
fail=0

expect() {  # expect <prompt|quiet> <command>
    local want=$1 cmd=$2 got=quiet
    [ -n "$(bash "$CHECK" "$cmd")" ] && got=prompt
    if [ "$got" != "$want" ]; then
        echo "FAIL ($want, got $got): $cmd"; fail=1
    fi
}

expect prompt 'cdk deploy'
expect prompt 'cdk deploy --all'
expect prompt "cdk destroy '*'"
expect prompt 'npx cdk deploy MyStack'
expect prompt 'cd infra && cdk deploy --all --require-approval never'
expect prompt 'AWS_PROFILE=dev cdk --profile dev deploy'
expect prompt 'uv run cdk deploy'
expect prompt '/usr/local/bin/cdk destroy X'
expect prompt 'echo hi; cdk deploy'
expect prompt 'result=$(cdk deploy X)'
expect prompt $'cat > f <<EOF\nnotes\nEOF\ncdk deploy'
expect quiet 'cdk diff'
expect quiet 'cdk synth'
expect quiet 'grep -rn "cdk deploy" .github/'
expect quiet "git commit -m 'ci: hold cdk deploy while a job runs'"
expect quiet $'cat > brief.txt <<EOF\nthen run cdk deploy --all\nEOF'
expect quiet 'echo cdk-deploy'
expect quiet 'gh pr view 1 --json title'

[ $fail -eq 0 ] && echo "pre_deploy_check: all cases passed"
exit $fail

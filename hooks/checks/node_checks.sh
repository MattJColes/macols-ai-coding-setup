#!/bin/bash
#
# node_checks.sh — the JavaScript/TypeScript half: related tests (vitest/jest
# or npm test), eslint, tsc --noEmit and dependency-cruiser layer contracts.
#
# Sourced by post_task.sh AFTER common.sh and its helpers; _node_bin here also
# serves run_duplication_check in structure_checks.sh. Not meant to be
# executed directly.
#
# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script must be sourced, not executed directly." >&2
    exit 1
fi

# ── JavaScript / TypeScript ──────────────────────────────────────────────────

_node_bin() {
    if [ -x "node_modules/.bin/$1" ] && project_trusted; then
        echo "node_modules/.bin/$1"
    elif command -v "$1" &> /dev/null; then
        echo "$1"
    fi
}

# Tests related to the changed files: vitest related / jest --findRelatedTests
# when the test script uses them, otherwise the project's `npm test`.
run_node_tests() {
    [ -f package.json ] || return 0
    local script
    script=$(node -e 'try{const p=require("./package.json");process.stdout.write((p.scripts&&p.scripts.test)||"")}catch(e){}' 2>/dev/null || true)
    if [ -z "$script" ]; then
        add_warning "No test script in package.json - skipping"
        return 0
    fi
    local -a files=()
    local f
    while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done < <(changed_matching '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' '*.cjs')
    [ ${#files[@]} -eq 0 ] && return 0

    local out ec=0 bin
    if [ "${CHECKPOINT_MODE:-0}" = "1" ]; then
        out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME} npm test 2>&1) || ec=$?
    elif [[ "$script" == *vitest* ]] && bin=$(_node_bin vitest) && [ -n "$bin" ]; then
        out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME} "$bin" related --run --passWithNoTests "${files[@]}" 2>&1) || ec=$?
    elif [[ "$script" == *jest* ]] && bin=$(_node_bin jest) && [ -n "$bin" ]; then
        out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME} "$bin" --findRelatedTests "${files[@]}" --passWithNoTests 2>&1) || ec=$?
    else
        out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME} npm test 2>&1) || ec=$?
    fi
    [ "$ec" -ne 0 ] && report_test_failure "Node.js tests" "$ec" "$out"
    return 0
}

# ESLint over changed JS/TS files (stylish output: "  line:col  error  msg  rule").
run_eslint_check() {
    local bin
    bin=$(_node_bin eslint)
    [ -z "$bin" ] && return 0
    local -a targets=()
    local f
    while IFS= read -r f; do [ -n "$f" ] && targets+=("$f"); done < <(changed_matching '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' '*.cjs')
    if [ ${#targets[@]} -eq 0 ]; then
        [ -n "$(changed_code_files)" ] && return 0
        targets=(".")
    fi
    local out ec=0
    out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD 120} "$bin" --no-error-on-unmatched-pattern "${targets[@]}" 2>&1) || ec=$?
    report_check_result "eslint" "$ec" "$out" "^[[:space:]]+[0-9]+:[0-9]+[[:space:]]+(error|warning)" "issues" "^/|^[[:space:]]+[0-9]+:[0-9]+"
}

# tsc --noEmit for the project, reporting only errors in changed files (errors
# elsewhere pre-date this change). Incremental build info keeps reruns fast.
run_tsc_check() {
    [ -f tsconfig.json ] || return 0
    [ -n "$(changed_matching '*.ts' '*.tsx')" ] || return 0
    local bin
    bin=$(_node_bin tsc)
    [ -z "$bin" ] && return 0
    local out ec=0 root rel mine=""
    mkdir -p node_modules/.cache 2>/dev/null || true
    out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME} "$bin" --noEmit --pretty false -p tsconfig.json \
        --incremental --tsBuildInfoFile node_modules/.cache/macols-tsc.tsbuildinfo 2>&1) || ec=$?
    [ "$ec" -eq 0 ] && return 0
    root="$PWD"
    local f
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        rel="${f#"$root"/}"
        mine+=$(printf '%s\n' "$out" | grep -F "$rel(" || true)
        [ -n "$mine" ] && mine+=$'\n'
    done < <(changed_matching '*.ts' '*.tsx')
    [ -z "$mine" ] && return 0
    report_check_result "tsc --noEmit" 1 "$mine" "error TS[0-9]+" "type errors in changed files"
}

# dependency-cruiser rules over the changed files, only when the repo has a
# config. Rule `comment`s in the config are the fix instruction. Violations
# recorded in .dependency-cruiser-known-violations.json (the approved
# exceptions; `depcruise --output-type baseline`) are ignored.
run_dependency_cruiser() {
    local cfg
    for cfg in .dependency-cruiser.js .dependency-cruiser.cjs .dependency-cruiser.mjs .dependency-cruiser.json; do
        [ -f "$cfg" ] && break
        cfg=""
    done
    [ -z "$cfg" ] && return 0
    local bin
    bin=$(_node_bin depcruise)
    if [ -z "$bin" ]; then add_warning "dependency-cruiser configured but not installed"; return 0; fi
    local -a files=()
    local f
    while IFS= read -r f; do [ -n "$f" ] && files+=("${f#"$PWD"/}"); done < <(changed_matching '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' '*.cjs')
    [ ${#files[@]} -eq 0 ] && return 0
    local -a known=()
    [ -f .dependency-cruiser-known-violations.json ] && known=(--ignore-known .dependency-cruiser-known-violations.json)
    local out ec=0
    out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD 120} "$bin" --config "$cfg" ${known[@]+"${known[@]}"} --output-type err-long "${files[@]}" 2>&1) || ec=$?
    report_check_result "dependency-cruiser" "$ec" "$out" "^[[:space:]]*(error|warn) " "layer violations" "^[[:space:]]*(error|warn) |^    [^ ]"
}

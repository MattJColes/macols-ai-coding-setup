#!/bin/bash
#
# Shared Post-Code Checks Library
#
# Sourced by post_code_hook.sh. NOT directly executable — must be sourced.
#
# Expects caller to set:
#   FILE_PATH   (optional) — file that was modified, used to pick the checks
#   MAX_TEST_TIME (optional, default 120) — timeout in seconds
#
# Provides:
#   run_post_code_checks — fast, file-scoped lint/type-check orchestrator.
#                          Prints a report of findings (nothing when clean).
#
# Per-edit checks are intentionally lightweight: only the formatter/linter/
# type-checker for the changed file's language runs here. Tests, duplication,
# layer rules and cdk synth run once at turn end via the Stop hook
# (post_task_checks.sh); semgrep and dependency audits belong in CI.
#
# Output is for the agent: findings plus a fix instruction, never "PASSED"
# chatter. An empty report means the file is clean.
#
# Always returns 0 (non-blocking).
#

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script must be sourced, not executed directly." >&2
    exit 1
fi

# Shared helpers (also sources ensure_node.sh).
SHARED_DIR_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=checks_common.sh
source "$SHARED_DIR_SELF/checks_common.sh"

# Defaults
MAX_TEST_TIME="${MAX_TEST_TIME:-120}"
FILE_PATH="${FILE_PATH:-}"

# Track issues found. Each entry is a self-contained finding (may be multi-line).
declare -a ISSUES_FOUND=()

add_issue() {
    ISSUES_FOUND+=("$1")
}

# Record a lint/type check result. Clean runs record nothing. A failing run
# records the finding count, a short excerpt and the matching fix hint. A
# non-zero exit with no countable findings means the tool itself failed (bad
# flag, broken config) — that is reported too, instead of passing silently.
# Usage: report_check_result <label> <exit> <output> <count_re> <noun> [<tail_grep>]
report_check_result() {
    local label="$1" ec="$2" output="$3" count_re="$4" noun="$5" tail_grep="${6:-}"
    [ "$ec" -eq 0 ] && return
    if [ "$ec" -eq 124 ]; then
        add_issue "$label: timed out"
        return
    fi
    local n excerpt
    n=$(printf '%s\n' "$output" | grep -cE "$count_re" || true)
    n="${n:-0}"
    if [ "$n" -gt 0 ]; then
        if [ -n "$tail_grep" ]; then
            excerpt=$(printf '%s\n' "$output" | grep -E "$tail_grep" | head -15)
        else
            excerpt=$(printf '%s\n' "$output" | grep -E "$count_re" | head -15)
        fi
        add_issue "$label: $n $noun"$'\n'"$excerpt"$'\n'"$(fix_hint "$label $output")"
    else
        add_issue "$label: exited $ec without reporting findings (tool or config error)"$'\n'"$(printf '%s\n' "$output" | head -5)"
    fi
}

# Run dart analyze on the changed file.
run_dart_analyze() {
    command -v dart &> /dev/null || return 0
    local analyze_output ec=0
    analyze_output=$(dart analyze "$FILE_PATH" 2>&1) || ec=$?
    report_check_result "dart analyze" "$ec" "$analyze_output" "^\s*(info|warning|error) " "issues"
}

# Run ruff on the changed file. Uses the project's ruff config, so the
# complexity/length/argument limits from the project's pyproject apply here.
run_ruff_check() {
    local ruff_bin
    ruff_bin=$(find_venv_bin ruff)
    [ -z "$ruff_bin" ] && return 0
    local ruff_output ec=0
    ruff_output=$("$ruff_bin" check --output-format concise "$FILE_PATH" 2>&1) || ec=$?
    report_check_result "ruff" "$ec" "$ruff_output" "^.+:[0-9]+:[0-9]+:" "lint issues"
}

# Type-check the changed file: pyright when the project configures it, else
# mypy when the project opts in via [tool.mypy]. Both honour project config
# (strict mode lives there, not here).
run_python_typecheck() {
    local proj_cfg=""
    [ -f "pyproject.toml" ] && proj_cfg="pyproject.toml"
    if [ -f "pyrightconfig.json" ] || { [ -n "$proj_cfg" ] && grep -q '\[tool\.pyright\]' "$proj_cfg"; }; then
        local pyright_bin
        pyright_bin=$(find_venv_bin pyright)
        [ -z "$pyright_bin" ] && [ -x node_modules/.bin/pyright ] && pyright_bin="node_modules/.bin/pyright"
        [ -z "$pyright_bin" ] && return 0
        local out ec=0
        out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME} "$pyright_bin" "$FILE_PATH" 2>&1) || ec=$?
        report_check_result "pyright" "$ec" "$out" " - error:" "type errors" " - error:"
        return 0
    fi
    if [ -n "$proj_cfg" ] && grep -q '\[tool\.mypy\]' "$proj_cfg"; then
        local mypy_bin
        mypy_bin=$(find_venv_bin mypy)
        [ -z "$mypy_bin" ] && return 0
        local out ec=0
        out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME} "$mypy_bin" --no-error-summary "$FILE_PATH" 2>&1) || ec=$?
        report_check_result "mypy" "$ec" "$out" ": error:" "type errors" ": error:"
    fi
}

# Resolve an ESLint binary, preferring the project-local one over npx (npx
# resolution costs hundreds of ms per edit). Echoes nothing when unavailable.
eslint_bin() {
    if [ -x "node_modules/.bin/eslint" ]; then
        echo "node_modules/.bin/eslint"
    elif command -v eslint &> /dev/null; then
        echo "eslint"
    fi
}

# Run ESLint on the changed file. Default (stylish) output is the one format
# every ESLint major still ships; findings are its "line:col  error|warning"
# rows. Exit 2 is a config/runtime failure and is reported as such.
run_eslint_check() {
    local bin
    bin=$(eslint_bin)
    [ -z "$bin" ] && return 0
    local eslint_output ec=0
    eslint_output=$(${TIMEOUT_CMD:+$TIMEOUT_CMD 60} "$bin" --no-error-on-unmatched-pattern "$FILE_PATH" 2>&1) || ec=$?
    report_check_result "eslint" "$ec" "$eslint_output" "^[[:space:]]+[0-9]+:[0-9]+[[:space:]]+(error|warning)" "issues"
}

# Run shellcheck on the changed shell script.
run_shellcheck() {
    command -v shellcheck &> /dev/null || return 0
    local out ec=0
    out=$(shellcheck -f gcc "$FILE_PATH" 2>&1) || ec=$?
    report_check_result "shellcheck" "$ec" "$out" "^.+:[0-9]+:[0-9]+: " "issues"
}

# gofmt the changed Go file (report only — the agent applies the fix). The
# heavier golangci-lint and go test run at turn end.
run_gofmt_check() {
    command -v gofmt &> /dev/null || return 0
    local out
    out=$(gofmt -l "$FILE_PATH" 2>&1) || true
    if [ -n "$out" ]; then
        add_issue "gofmt: $FILE_PATH is not formatted"$'\n'"Fix: run gofmt -w $FILE_PATH (or goimports -w)."
    fi
}

# Main orchestrator — fast, file-scoped checks only. Prints the report.
run_post_code_checks() {
    setup_timeout_cmd
    [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ] || return 0

    case "$FILE_PATH" in
        *.py)
            run_ruff_check || true
            run_python_typecheck || true
            ;;
        *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
            run_eslint_check || true
            ;;
        *.dart)
            run_dart_analyze || true
            ;;
        *.go)
            run_gofmt_check || true
            ;;
        *.sh|*.bash)
            run_shellcheck || true
            ;;
        *)
            return 0
            ;;
    esac

    local long
    long=$(printf '%s\n' "$FILE_PATH" | check_file_lengths)
    [ -n "$long" ] && add_issue "$long"$'\n'"$(fix_hint "$long")"

    local issue
    for issue in "${ISSUES_FOUND[@]}"; do
        printf '%s\n' "$issue"
    done
    return 0
}

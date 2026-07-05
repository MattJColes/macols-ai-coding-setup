#!/bin/bash
#
# Shared Post-Code Checks Library
#
# Sourced by tool-specific wrappers (ClaudeCode, OpenCode).
# NOT directly executable — must be sourced.
#
# Expects caller to set:
#   FILE_PATH   (optional) — file that was modified, used to filter checks
#   MAX_TEST_TIME (optional, default 120) — timeout in seconds
#
# Provides:
#   run_post_code_checks — fast, file-scoped lint/type-check orchestrator
#
# Per-edit checks are intentionally lightweight: only the linter/type-checker
# for the changed file's language runs here. Tests, security audits and cdk
# synth run once at turn end via the Stop hook (post_task_checks.sh).
#
# Shared environment/discovery helpers (setup_timeout_cmd, find_venv_bin, …)
# live in checks_common.sh, sourced below.
#
# Results are collected in ISSUES_FOUND[] and MESSAGES[] arrays.
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

# Track issues found
declare -a ISSUES_FOUND=()
declare -a MESSAGES=()

add_message() {
    MESSAGES+=("$1")
}

add_issue() {
    ISSUES_FOUND+=("$1")
}

# Report the post-execution result tail of a lint/type check: pass note on
# success, finding + excerpt on failure. Findings use add_issue; the pass note
# and the excerpt use add_message (this file's per-edit severities).
# Usage: report_check_result <label> <exit> <output> <count_re> <noun> <timeout_msg> [<tail_grep>]
report_check_result() {
    local label="$1" ec="$2" output="$3" count_re="$4" noun="$5" timeout_msg="$6" tail_grep="${7:-}"
    if [ "$ec" -eq 0 ]; then
        add_message "$label: PASSED"
        return
    fi
    if [ "$ec" -eq 124 ]; then
        add_issue "$timeout_msg"
        return
    fi
    local n
    n=$(printf '%s' "$output" | grep -cE "$count_re" || true)
    n="${n:-0}"
    if [ "$n" -gt 0 ]; then
        add_issue "$label: $n $noun"
        local tail
        if [ -n "$tail_grep" ]; then
            tail=$(printf '%s' "$output" | grep "$tail_grep" | head -10)
        else
            tail=$(printf '%s' "$output" | head -10)
        fi
        add_message "$tail"
    fi
}

# Run dart analyze
run_dart_analyze() {
    if ! command -v dart &> /dev/null; then
        add_message "dart not installed - skipping Dart analysis"
        return 0
    fi

    local analyze_output ec=0
    analyze_output=$(dart analyze . 2>&1) || ec=$?
    report_check_result "Dart analyze" "$ec" "$analyze_output" "^\s*(info|warning|error) " "issues" "Dart analyze: TIMED OUT"
}

# Run ruff linter — scoped to the changed file.
run_ruff_check() {
    local ruff_bin
    ruff_bin=$(find_venv_bin ruff)
    [ -z "$ruff_bin" ] && return 0

    local target="."
    if [ -n "$FILE_PATH" ] && [[ "$FILE_PATH" == *.py ]]; then
        target="$FILE_PATH"
    fi

    local ruff_output ec=0
    ruff_output=$("$ruff_bin" check "$target" 2>&1) || ec=$?
    report_check_result "Ruff" "$ec" "$ruff_output" "^.+:[0-9]+:[0-9]+:" "linting issues" "Ruff: TIMED OUT"
}

# Run mypy type checker — scoped to the changed file.
run_mypy_check() {
    local mypy_bin
    mypy_bin=$(find_venv_bin mypy)
    [ -z "$mypy_bin" ] && return 0

    local target
    if [ -n "$FILE_PATH" ] && [[ "$FILE_PATH" == *.py ]]; then
        target="$FILE_PATH"
    else
        target=""
        for dir in src app lib lambda functions; do
            if [ -d "$dir" ] && find "$dir" -maxdepth 3 -name "*.py" -type f 2>/dev/null | grep -q .; then
                target="$target $dir"
            fi
        done
        if [ -z "$target" ]; then
            return 0
        fi
    fi

    local mypy_output ec=0
    local mypy_cmd="${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME }$mypy_bin --no-error-summary $target"
    mypy_output=$(eval "$mypy_cmd" 2>&1) || ec=$?
    report_check_result "Mypy" "$ec" "$mypy_output" ": error:" "type errors" "Mypy: TIMED OUT after ${MAX_TEST_TIME}s" ": error:"
}

# Run ESLint — scoped to the changed file. Prefers a project-local eslint binary
# over `npx` to avoid npx's per-invocation resolution overhead on every edit.
run_eslint_check() {
    local eslint_bin
    if [ -x "node_modules/.bin/eslint" ]; then
        eslint_bin="node_modules/.bin/eslint"
    elif command -v eslint &> /dev/null; then
        eslint_bin="eslint"
    elif command -v npx &> /dev/null; then
        eslint_bin="npx eslint"
    else
        return 0
    fi

    local target
    if [ -n "$FILE_PATH" ] && [[ "$FILE_PATH" == *.ts || "$FILE_PATH" == *.js || "$FILE_PATH" == *.tsx || "$FILE_PATH" == *.jsx ]]; then
        target="$FILE_PATH"
    else
        target="."
    fi

    local eslint_output ec=0
    local eslint_cmd="${TIMEOUT_CMD:+$TIMEOUT_CMD 60 }$eslint_bin --no-warn-on-unmatched-pattern \"$target\""
    eslint_output=$(eval "$eslint_cmd" 2>&1) || ec=$?
    report_check_result "ESLint" "$ec" "$eslint_output" "^.+:[0-9]+:[0-9]+" "issues" "ESLint: TIMED OUT"
}

# Main orchestrator — fast, file-scoped lint/type-check only.
#
# The per-edit hook stays lightweight: for the single file that changed it runs
# only the linter / type-checker for that language. The heavy battery (tests,
# security audits, cdk synth) deliberately does NOT run here — it runs once at
# turn end via the Stop hook (post_task_checks.sh), instead of after every edit.
run_post_code_checks() {
    setup_timeout_cmd

    # Nothing to scope to / not a source file we lint — skip.
    case "$FILE_PATH" in
        *.py)
            run_ruff_check || true
            run_mypy_check || true
            ;;
        *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
            run_eslint_check || true
            ;;
        *.dart)
            run_dart_analyze || true
            ;;
        *)
            return 0
            ;;
    esac

    # Output results
    if [ ${#ISSUES_FOUND[@]} -gt 0 ]; then
        echo "Hook: Post-code checks found issues:"
        for issue in "${ISSUES_FOUND[@]}"; do
            echo "  - $issue"
        done
    fi

    for msg in "${MESSAGES[@]}"; do
        echo "$msg"
    done

    return 0
}

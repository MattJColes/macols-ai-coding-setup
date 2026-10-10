#!/bin/bash
#
# Shared Post-Task Checks Library
#
# Sourced by post_task_hook.sh. NOT directly executable — must be sourced.
#
# Expects caller to set:
#   MAX_TEST_TIME (optional, default 300) — timeout in seconds
#
# Provides:
#   run_post_task_checks — orchestrator that runs the project's checks in parallel
#   code_changed         — turn-end change gate (re-exported from common.sh)
#
# The checks themselves live in per-family modules this file sources:
#   python_checks.sh     pytest (scoped/testmon), ruff, pyright/mypy, import-linter
#   node_checks.sh       vitest/jest/npm test, eslint, tsc, dependency-cruiser
#   lang_checks.sh       cdk synth, flutter test + dart analyze, go, shellcheck
#   structure_checks.sh  jscpd duplication, file length, opt-in semgrep
#
# Everything is scoped to the files this turn changed (via changed_code_files),
# falling back to a full scan when git is unavailable. The battery is the local
# half of the quality gates; the same tools run unscoped in CI with the same
# project config, plus the slow or network-bound checks that don't belong in a
# per-turn loop (semgrep, pip-audit/npm audit/govulncheck — see the `quality`
# skill's CI template).
#
#   Tests         pytest (scoped, or pytest-testmon when installed),
#                 jest/vitest related tests, flutter test (scoped), go test
#                 over changed modules (the test cache skips the rest),
#                 cdk synth
#   Lint          ruff, eslint, dart analyze, golangci-lint (or go vet),
#                 and shellcheck, each with the project's own limits
#   Types         pyright or mypy (whichever the project configures),
#                 tsc --noEmit
#   Structure     jscpd duplication touching changed files, import-linter and
#                 dependency-cruiser layer contracts (only when the repo has a
#                 config), a file-length limit (MACOLS_MAX_FILE_LINES)
#
# Only findings are recorded as CRITICAL_ISSUES, each with a fix instruction.
# WARNINGS hold notes (tool missing, nothing to test) for verbose runs.
#
# Switches: MACOLS_PYTEST_SCOPE=changed|full|off, MACOLS_TESTMON=off,
# MACOLS_DUPLICATION=off, MACOLS_SEMGREP=1 (opt back in to a local semgrep
# scan), MACOLS_GO_RACE=1, MACOLS_GO_TEST_SCOPE=module|changed,
# MACOLS_CHECK_LOG=off (see log_check_run in common.sh).
#
# The independent checks run CONCURRENTLY: each runs in its own subshell and
# writes its findings to per-job temp files (NUL-delimited, since findings
# contain newlines); the orchestrator slurps them back after all jobs finish.
#

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script must be sourced, not executed directly." >&2
    exit 1
fi

# Shared helpers (also sources ensure_node.sh).
SHARED_DIR_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SHARED_DIR_SELF/common.sh"
# The batteries themselves, one module per language family:
# shellcheck source=python_checks.sh
source "$SHARED_DIR_SELF/python_checks.sh"
# shellcheck source=node_checks.sh
source "$SHARED_DIR_SELF/node_checks.sh"
# shellcheck source=lang_checks.sh
source "$SHARED_DIR_SELF/lang_checks.sh"
# shellcheck source=structure_checks.sh
source "$SHARED_DIR_SELF/structure_checks.sh"

# Defaults
MAX_TEST_TIME="${MAX_TEST_TIME:-300}"

# Track issues found
declare -a CRITICAL_ISSUES=()
declare -a WARNINGS=()
# Tests the checkpoint saw fail that the turn-end selection would not have run.
declare -a ESCAPED_TESTS=()

add_warning() {
    WARNINGS+=("$1")
}

add_critical_issue() {
    CRITICAL_ISSUES+=("$1")
}

# Record a lint/type/gate result as one critical finding: count, excerpt and
# fix hint. Clean runs record nothing. A non-zero exit with no countable
# findings is a tool/config failure and is reported as such rather than
# counted as a pass.
# Usage: report_check_result <label> <exit> <output> <count_re> <noun> [<excerpt_re>]
report_check_result() {
    local label="$1" ec="$2" output="$3" count_re="$4" noun="$5" excerpt_re="${6:-$4}"
    [ "$ec" -eq 0 ] && return
    if [ "$ec" -eq 124 ]; then
        add_critical_issue "$label: timed out after ${MAX_TEST_TIME}s"
        return
    fi
    local n excerpt hint
    n=$(printf '%s\n' "$output" | grep -cE "$count_re" || true)
    n="${n:-0}"
    if [ "$n" -gt 0 ]; then
        excerpt=$(printf '%s\n' "$output" | grep -E "$excerpt_re" | head -15)
        hint=$(fix_hint "$label $output")
        add_critical_issue "$label: $n $noun"$'\n'"$excerpt${hint:+$'\n'$hint}"
    else
        add_critical_issue "$label: exited $ec without reporting findings (tool or config error)"$'\n'"$(printf '%s\n' "$output" | tail -5)"
    fi
}

# Record a failing test run with the tail of its output.
report_test_failure() {
    local label="$1" ec="$2" output="$3"
    if [ "$ec" -eq 124 ]; then
        add_critical_issue "$label: timed out after ${MAX_TEST_TIME}s"
    else
        add_critical_issue "$label: FAILED"$'\n'"$(printf '%s\n' "$output" | tail -15)"$'\n'"Fix: make the code pass (or update the test if the behaviour change was intended) before finishing."
    fi
}

# Changed files matching a shell glob list, one per line. Usage:
#   changed_matching '*.py'   or   changed_matching '*.ts' '*.tsx'
changed_matching() {
    local f pat
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        for pat in "$@"; do
            # shellcheck disable=SC2254  # pattern match is the point
            case "$f" in $pat) printf '%s\n' "$f"; break ;; esac
        done
    done <<< "$(changed_code_files)"
}
# ── Project-declared checks ──────────────────────────────────────────────────
# A project can add its own commands per feedback loop in .macols/checks.conf:
#   IMMEDIATE="..."   every agent turn (schema validation, a fast smoke test)
#   CHECKPOINT="..."  before each commit (integration tests, an eval smoke set)
#   NIGHTLY="..."     the scheduled CI job (E2E, the full eval suite)
# Values are read as data (never sourced) and run with bash from the repo
# root, in trusted projects only.
project_check_command() {
    local key="$1" file line
    file="$(project_root)/.macols/checks.conf"
    [ -f "$file" ] || return 0
    line=$(grep -E "^${key}=" "$file" | tail -1) || return 0
    line="${line#*=}"
    line="${line#\"}"; line="${line%\"}"
    line="${line#\'}"; line="${line%\'}"
    printf '%s' "$line"
}

_run_project_check() {
    local key="$1" cmd out ec=0
    cmd=$(project_check_command "$key")
    [ -z "$cmd" ] && return 0
    out=$(cd "$(project_root)" && ${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME} bash -c "$cmd" 2>&1) || ec=$?
    [ "$ec" -ne 0 ] && add_critical_issue "$key check ($cmd): FAILED"$'\n'"$(printf '%s\n' "$out" | tail -15)"$'\n'"Fix: make '$cmd' pass before finishing."
    return 0
}
run_project_immediate() { _run_project_check IMMEDIATE; }
run_project_checkpoint() { _run_project_check CHECKPOINT; }

# ── Orchestration ────────────────────────────────────────────────────────────

# Run a single check function in isolation and persist its findings, its
# duration and any escaped tests (see run_python_tests).
_run_check_job() {
    local fn="$1" out="$2" start
    CRITICAL_ISSUES=()
    WARNINGS=()
    ESCAPED_TESTS=()
    start=$(now_ms)
    "$fn" || true
    printf '%s' "$(( $(now_ms) - start ))" > "$out.ms"
    if [ ${#CRITICAL_ISSUES[@]} -gt 0 ]; then
        printf '%s\0' "${CRITICAL_ISSUES[@]}" > "$out.crit"
    fi
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        printf '%s\0' "${WARNINGS[@]}" > "$out.warn"
    fi
    if [ ${#ESCAPED_TESTS[@]} -gt 0 ]; then
        printf '%s\0' "${ESCAPED_TESTS[@]}" > "$out.esc"
    fi
}

# Main orchestrator — runs every applicable check for the project, concurrently.
run_post_task_checks() {
    setup_timeout_cmd

    local project_info
    project_info=$(detect_project_type)
    local has_python has_node has_cdk has_flutter has_go
    IFS=':' read -r has_python has_node has_cdk has_flutter has_go <<< "$project_info" || true

    local -a checks=()
    if [ "$has_python" = "true" ]; then
        checks+=(run_python_tests run_ruff_check run_python_typecheck run_import_linter)
    fi
    if [ "$has_node" = "true" ]; then
        checks+=(run_node_tests run_eslint_check run_tsc_check run_dependency_cruiser)
    fi
    [ "$has_cdk" = "true" ] && checks+=(run_cdk_tests)
    if [ "$has_flutter" = "true" ]; then
        checks+=(run_flutter_tests run_dart_analyze)
    fi
    [ "$has_go" = "true" ] && checks+=(run_go_checks)
    checks+=(run_shellcheck run_duplication_check run_file_length_check run_semgrep_scan)
    if [ "${CHECKPOINT_MODE:-0}" = "1" ]; then
        checks+=(run_project_checkpoint)
    else
        checks+=(run_project_immediate)
    fi

    # Untrusted project: keep only the checks that read files without running
    # repo code (see project_trusted in common.sh).
    if ! project_trusted; then
        local -a safe=()
        for check in "${checks[@]}"; do
            case "$check" in
                run_ruff_check|run_python_typecheck|run_shellcheck|run_duplication_check|run_file_length_check) safe+=("$check") ;;
            esac
        done
        checks=("${safe[@]}")
        # shellcheck disable=SC2034  # read by post_task_hook.sh
        UNTRUSTED_SKIPPED=1
    fi

    # Warm the shared discovery caches in the parent so every fanned-out
    # subshell inherits them instead of re-walking the tree / re-running git.
    find_python_projects >/dev/null
    changed_code_files >/dev/null

    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/post_task.XXXXXX") || return 1

    local i=0 check started loop=turn
    [ "${CHECKPOINT_MODE:-0}" = "1" ] && loop=checkpoint
    started=$(now_ms)
    for check in "${checks[@]}"; do
        _run_check_job "$check" "$tmpdir/$i" &
        i=$((i + 1))
    done
    wait

    local j item result any_fail=pass
    local -a escaped
    for ((j = 0; j < i; j++)); do
        result=pass
        escaped=()
        if [ -f "$tmpdir/$j.crit" ]; then
            result=fail any_fail=fail
            while IFS= read -r -d '' item; do CRITICAL_ISSUES+=("$item"); done < "$tmpdir/$j.crit"
        fi
        if [ -f "$tmpdir/$j.warn" ]; then
            while IFS= read -r -d '' item; do WARNINGS+=("$item"); done < "$tmpdir/$j.warn"
        fi
        if [ -f "$tmpdir/$j.esc" ]; then
            while IFS= read -r -d '' item; do escaped+=("$item"); done < "$tmpdir/$j.esc"
        fi
        log_check_run "$loop" "${checks[$j]#run_}" "$(cat "$tmpdir/$j.ms" 2>/dev/null || echo 0)" "$result" ${escaped[@]+"${escaped[@]}"}
    done
    log_check_run "$loop" total "$(( $(now_ms) - started ))" "$any_fail"

    rm -rf "$tmpdir"
    return 0
}

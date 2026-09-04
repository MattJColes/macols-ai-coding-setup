#!/bin/bash
#
# Shared Post-Task Checks Library
#
# Sourced by tool-specific wrappers (ClaudeCode, OpenCode).
# NOT directly executable — must be sourced.
#
# Expects caller to set:
#   MAX_TEST_TIME (optional, default 300) — timeout in seconds
#
# Provides:
#   run_post_task_checks — orchestrator that runs the project's checks in parallel
#   code_changed         — turn-end change gate (re-exported from checks_common.sh)
#
# Tests, audits and semgrep run over the whole project; the linters (ruff, mypy,
# eslint) are scoped to the files this turn changed (via changed_code_files),
# falling back to a full scan when git is unavailable.
#
# Shared environment/discovery helpers (setup_timeout_cmd, detect_project_type,
# find_venv_bin, find_python_projects, code_changed, …) live in checks_common.sh,
# sourced below.
#
# The independent checks selected for a project are run CONCURRENTLY: each runs
# in its own subshell, writes its findings to per-job temp files (NUL-delimited,
# since findings can contain embedded newlines), and the orchestrator slurps them
# back into CRITICAL_ISSUES[]/WARNINGS[] after all jobs finish. Caller decides how
# to report/block based on these arrays.
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
MAX_TEST_TIME="${MAX_TEST_TIME:-300}"

# Track issues found
declare -a CRITICAL_ISSUES=()
declare -a WARNINGS=()

add_warning() {
    WARNINGS+=("$1")
}

add_critical_issue() {
    CRITICAL_ISSUES+=("$1")
}

# Report the post-execution result tail of a lint/type check: pass warning on
# success, critical finding + critical excerpt on failure. This file's turn-end
# battery surfaces lint failures as critical issues (they block the turn); the
# excerpt carries a tool prefix so the appended output is self-describing.
# Usage: report_check_result <label> <exit> <output> <count_re> <noun> <timeout_msg> <excerpt_prefix> [<tail_grep>]
report_check_result() {
    local label="$1" ec="$2" output="$3" count_re="$4" noun="$5" timeout_msg="$6" excerpt_prefix="$7" tail_grep="${8:-}"
    if [ "$ec" -eq 0 ]; then
        add_warning "$label: PASSED"
        return
    fi
    if [ "$ec" -eq 124 ]; then
        add_critical_issue "$timeout_msg"
        return
    fi
    local n
    n=$(printf '%s' "$output" | grep -cE "$count_re" || true)
    n="${n:-0}"
    if [ "$n" -gt 0 ]; then
        add_critical_issue "$label: $n $noun"
        local tail
        if [ -n "$tail_grep" ]; then
            tail=$(printf '%s' "$output" | grep "$tail_grep" | head -10)
        else
            tail=$(printf '%s' "$output" | head -10)
        fi
        add_critical_issue "$excerpt_prefix:\n$tail"
    fi
}

# Run Python tests — monorepo-aware: runs pytest from each sub-project directory.
#
# Scoped by default: a Stop hook fires on every code-touching turn, and in a
# large monorepo a full suite there costs minutes and gigabytes per turn while
# adding no gate — pre-commit runs the impacted subset and pre-push the full
# suite. So MACOLS_PYTEST_SCOPE decides what runs:
#   changed (default) — the changed test files plus test_<module>.py for each
#                       changed module (sibling, tests/ or test/); nothing when
#                       no test matches
#   full              — the whole suite, as before
#   off               — skip the step
run_python_tests() {
    local root_dir="$PWD"
    local scope="${MACOLS_PYTEST_SCOPE:-changed}"
    case "$scope" in
        full|changed) ;;
        off)
            add_warning "Python tests: skipped (MACOLS_PYTEST_SCOPE=off)"
            return 0 ;;
        *)
            add_warning "Python tests: unknown MACOLS_PYTEST_SCOPE='$scope' - treating as 'changed'"
            scope="changed" ;;
    esac

    local -a projects
    read -ra projects <<< "$(find_python_projects)"

    local any_failed=false

    for project_dir in "${projects[@]}"; do
        local label="$project_dir"
        [ "$project_dir" = "." ] && label="root"

        cd "$root_dir/$project_dir" || continue

        # Resolve pytest per project so sub-project .venvs (with their own
        # deps) win over a global tool install
        local pytest_bin
        pytest_bin=$(find_venv_bin pytest)
        if [ -z "$pytest_bin" ]; then
            add_warning "pytest not installed - skipping Python tests ($label)"
            cd "$root_dir" || return
            continue
        fi

        # Check test directory exists
        if [ ! -d "tests" ] && [ ! -d "test" ]; then
            if ! find . -maxdepth 3 -name "test_*.py" -o -name "*_test.py" 2>/dev/null | grep -q .; then
                cd "$root_dir" || return
                continue
            fi
        fi

        local pytest_cmd="${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME }$pytest_bin -v --tb=short"
        if [ "$scope" = "changed" ]; then
            local targets
            targets=$(impacted_test_files "$(pwd)")
            if [ -z "$targets" ]; then
                add_warning "Python tests ($label): no impacted tests found for changed files; full suite runs at pre-push"
                cd "$root_dir" || return
                continue
            fi
            pytest_cmd="${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME }$pytest_bin -q --tb=short -p no:cacheprovider$targets"
        fi

        local test_output
        if test_output=$(eval "$pytest_cmd" 2>&1); then
            add_warning "Python tests ($label): PASSED"
        else
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                add_critical_issue "Python tests ($label): TIMED OUT after ${MAX_TEST_TIME}s"
            else
                add_critical_issue "Python tests ($label): FAILED"
                local tail_output
                tail_output=$(echo "$test_output" | tail -10)
                add_critical_issue "Test output:\n$tail_output"
            fi
            any_failed=true
        fi

        cd "$root_dir" || return
    done

    if [ "$any_failed" = true ]; then
        return 1
    fi
}

# The test files this turn's changes reach, inside one project directory, as a
# shell-quoted, space-prefixed list (empty when nothing matches). Changed test
# files count as themselves; a changed module pulls in test_<module>.py from
# its own directory, tests/ or test/. Deliberately name-based: an import-graph
# walk is the pre-commit hook's job, and a turn-end battery that tries to be
# clever is one that runs the whole suite by accident.
impacted_test_files() {
    local project_abs="$1"
    local f base stem d cand out="" seen=$'\n'
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        case "$f" in "$project_abs"/*.py) ;; *) continue ;; esac
        base="$(basename "$f")"
        case "$base" in
            test_*.py|*_test.py)
                case "$seen" in *$'\n'"$f"$'\n'*) ;; *) seen+="$f"$'\n'; out+=" $(printf '%q' "$f")" ;; esac ;;
            *)
                stem="${base%.py}"
                for d in "$(dirname "$f")" "$project_abs/tests" "$project_abs/test"; do
                    cand="$d/test_${stem}.py"
                    [ -f "$cand" ] || continue
                    case "$seen" in *$'\n'"$cand"$'\n'*) ;; *) seen+="$cand"$'\n'; out+=" $(printf '%q' "$cand")" ;; esac
                done ;;
        esac
    done <<< "$(changed_code_files)"
    printf '%s' "$out"
}

# Run Node.js tests (Jest or Mocha)
run_node_tests() {
    if [ ! -f "package.json" ]; then
        return 0
    fi

    if ! grep -q '"test"' package.json 2>/dev/null; then
        add_warning "No test script in package.json - skipping"
        return 0
    fi

    local test_output
    local npm_cmd="${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME }npm test"
    if test_output=$(eval "$npm_cmd" 2>&1); then
        add_warning "Node.js tests: PASSED"
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            add_critical_issue "Node.js tests: TIMED OUT after ${MAX_TEST_TIME}s"
        else
            add_critical_issue "Node.js tests: FAILED"
            local tail_output
            tail_output=$(echo "$test_output" | tail -10)
            add_critical_issue "Test output:\n$tail_output"
        fi
        return 1
    fi
}

# Run CDK synth
run_cdk_tests() {
    if [ ! -f "cdk.json" ]; then
        return 0
    fi

    # Discard output (keeps cdk's chatter out of the parallel result stream);
    # PASS/FAIL is taken from the exit status.
    if [ -f "app.py" ]; then
        if cdk synth --quiet > /dev/null 2>&1; then
            add_warning "CDK synth: PASSED"
        else
            add_critical_issue "CDK synth: FAILED"
            return 1
        fi
    elif grep -q "typescript" package.json 2>/dev/null; then
        if npm run build > /dev/null 2>&1 && cdk synth --quiet > /dev/null 2>&1; then
            add_warning "CDK synth: PASSED"
        else
            add_critical_issue "CDK synth: FAILED"
            return 1
        fi
    fi
}

# Run Flutter tests
run_flutter_tests() {
    if ! command -v flutter &> /dev/null; then
        add_warning "flutter not installed - skipping Flutter tests"
        return 0
    fi

    if [ ! -d "test" ]; then
        add_warning "No Flutter test/ directory found - skipping"
        return 0
    fi

    local test_output
    local flutter_cmd="${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME }flutter test"
    if test_output=$(eval "$flutter_cmd" 2>&1); then
        add_warning "Flutter tests: PASSED"
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            add_critical_issue "Flutter tests: TIMED OUT after ${MAX_TEST_TIME}s"
        else
            add_critical_issue "Flutter tests: FAILED"
            local tail_output
            tail_output=$(echo "$test_output" | tail -10)
            add_critical_issue "Test output:\n$tail_output"
        fi
        return 1
    fi
}

# Run dart analyze
run_dart_analyze() {
    if ! command -v dart &> /dev/null; then
        add_warning "dart not installed - skipping Dart analysis"
        return 0
    fi

    local analyze_output ec=0
    analyze_output=$(dart analyze . 2>&1) || ec=$?
    report_check_result "Dart analyze" "$ec" "$analyze_output" "^\s*(info|warning|error) " "issues" "Dart analyze: TIMED OUT" "Dart analyze output"
}

# Run semgrep SAST scan — the project's single static-analysis security tool.
#
# Multi-language (Python, JS/TS, Go, …) and taint/dataflow-aware: semgrep's
# p/python pack covers Python security checks and adds source→sink injection
# tracking that single-language linters can't do.
#
# Turn-end only (never per-edit): engine + rule loading costs a few seconds,
# too slow after every file write. Scoped to this turn's changed files (full
# repo when git is unavailable) so the per-turn cost tracks the size of the
# edit, not the repo. --metrics=off avoids a telemetry network call. Only
# ERROR-severity findings count as critical, to keep the signal tight.
# Vendored/build dirs are excluded so we don't flag code we don't own.
#
# Rulesets are scoped to the detected languages (fetched from the registry once,
# then cached under ~/.semgrep):
#   p/secrets     — hardcoded credentials, all languages
#   p/python      — Python security + correctness
#   p/javascript  — JS security/correctness
#   p/typescript  — TS-specific checks
# Dart/Flutter has no semgrep ruleset; `dart analyze` (run_dart_analyze) covers
# that language, so semgrep is simply skipped for Flutter-only projects.
#
# We read --json so the count is exact and version-independent (semgrep's
# human-readable summary wording changes between releases). jq is the repo's
# standard JSON tool; a grep fallback keeps the check working without it.
run_semgrep_scan() {
    command -v semgrep &> /dev/null || return 0

    local project_info has_python has_node has_cdk has_flutter
    project_info=$(detect_project_type)
    IFS=':' read -r has_python has_node has_cdk has_flutter <<< "$project_info" || true

    local -a configs=(--config p/secrets)
    [ "$has_python" = "true" ] && configs+=(--config p/python)
    [ "$has_node" = "true" ] && configs+=(--config p/javascript --config p/typescript)

    # Scope the scan to this turn's changed files (whole repo when git is
    # unavailable). This is the dominant turn-end cost — a full-repo scan runs
    # the engine over every file each turn. As an advisory per-turn gate, scoping
    # to changed files is the right trade: we lose semgrep's cross-file taint
    # tracking on untouched code, which CI's full-repo scan still covers.
    local changed
    changed=$(changed_code_files)
    local -a scan_targets=()
    if [ -n "$changed" ]; then
        local f
        while IFS= read -r f; do [ -n "$f" ] && scan_targets+=("$f"); done <<< "$changed"
        if [ ${#scan_targets[@]} -eq 0 ]; then
            add_warning "Semgrep SAST scan: no changed files"
            return 0
        fi
    else
        scan_targets=(".")
    fi

    local -a semgrep_cmd=(
        ${TIMEOUT_CMD:+"$TIMEOUT_CMD" "$MAX_TEST_TIME"}
        semgrep scan "${configs[@]}"
        --quiet --metrics=off --timeout 30 --severity ERROR --json
        --exclude .venv --exclude venv --exclude node_modules
        --exclude dist --exclude build
        "${scan_targets[@]}"
    )
    local semgrep_output
    semgrep_output=$("${semgrep_cmd[@]}" 2>/dev/null) || true

    local finding_count detail
    if command -v jq &> /dev/null; then
        finding_count=$(echo "$semgrep_output" | jq -r '.results | length' 2>/dev/null || echo 0)
        detail=$(echo "$semgrep_output" | jq -r '.results[] | "  \(.path):\(.start.line) \(.check_id)"' 2>/dev/null | head -15 || true)
    else
        finding_count=$(echo "$semgrep_output" | grep -oc '"check_id"' || true)
        detail=""
    fi
    finding_count="${finding_count:-0}"

    if [ "$finding_count" -gt 0 ]; then
        add_critical_issue "Semgrep: $finding_count ERROR-severity SAST finding(s)"
        [ -n "$detail" ] && add_critical_issue "Semgrep findings:\n$detail"
    else
        add_warning "Semgrep SAST scan: PASSED"
    fi
}

# Run pip-audit
run_pip_audit() {
    if ! command -v pip-audit &> /dev/null; then
        return 0
    fi

    if [ ! -f "requirements.txt" ] && [ ! -f "pyproject.toml" ]; then
        return 0
    fi

    local audit_output
    if audit_output=$(pip-audit 2>&1); then
        add_warning "pip-audit: no vulnerabilities"
    else
        if echo "$audit_output" | grep -q "found"; then
            add_critical_issue "pip-audit: vulnerabilities found in Python dependencies"
        fi
    fi
}

# Run ruff linter — monorepo-aware, scoped to this turn's changed files.
run_ruff_check() {
    local ruff_bin
    ruff_bin=$(find_venv_bin ruff)
    if [ -z "$ruff_bin" ]; then
        return 0
    fi

    local root_dir="$PWD"
    local -a projects
    read -ra projects <<< "$(find_python_projects)"

    local changed
    changed=$(changed_code_files)

    for project_dir in "${projects[@]}"; do
        local label="$project_dir"
        [ "$project_dir" = "." ] && label="root"

        local proj_abs
        proj_abs=$(cd "$root_dir/$project_dir" 2>/dev/null && pwd) || continue
        cd "$proj_abs" || continue

        # Scope to changed .py files under this project; skip the project when
        # none changed. Fall back to a full project scan when git gave us
        # nothing (not a repo).
        local -a targets=()
        if [ -n "$changed" ]; then
            local f
            while IFS= read -r f; do
                case "$f" in "$proj_abs"/*.py) targets+=("$f") ;; esac
            done <<< "$changed"
            if [ ${#targets[@]} -eq 0 ]; then
                cd "$root_dir" || return
                continue
            fi
        else
            targets=(".")
        fi

        local ruff_output ec=0
        ruff_output=$("$ruff_bin" check "${targets[@]}" 2>&1) || ec=$?
        report_check_result "Ruff ($label)" "$ec" "$ruff_output" "^.+:[0-9]+:[0-9]+:" "linting issues" "Ruff ($label): TIMED OUT" "Ruff output"

        cd "$root_dir" || return
    done
}

# Run mypy type checker — monorepo-aware, uses each sub-project's config,
# scoped to this turn's changed files.
run_mypy_check() {
    local mypy_bin
    mypy_bin=$(find_venv_bin mypy)
    if [ -z "$mypy_bin" ]; then
        return 0
    fi

    local root_dir="$PWD"
    local -a projects
    read -ra projects <<< "$(find_python_projects)"

    local changed
    changed=$(changed_code_files)

    for project_dir in "${projects[@]}"; do
        local label="$project_dir"
        [ "$project_dir" = "." ] && label="root"

        local proj_abs
        proj_abs=$(cd "$root_dir/$project_dir" 2>/dev/null && pwd) || continue
        cd "$proj_abs" || continue

        # Only type-check projects that opt in via [tool.mypy].
        if ! { [ -f "pyproject.toml" ] && grep -q '\[tool\.mypy\]' pyproject.toml 2>/dev/null; }; then
            cd "$root_dir" || return
            continue
        fi

        # Scope to changed .py files; skip the project when none changed. Fall
        # back to scanning the common source dirs when git gave us nothing.
        local -a targets=()
        if [ -n "$changed" ]; then
            local f
            while IFS= read -r f; do
                case "$f" in "$proj_abs"/*.py) targets+=("$f") ;; esac
            done <<< "$changed"
            if [ ${#targets[@]} -eq 0 ]; then
                cd "$root_dir" || return
                continue
            fi
        else
            for dir in app src lib lambda functions stacks config custom_constructs; do
                if [ -d "$dir" ] && find "$dir" -maxdepth 3 -name "*.py" -type f 2>/dev/null | grep -q .; then
                    targets+=("$dir")
                fi
            done
            if [ ${#targets[@]} -eq 0 ]; then
                cd "$root_dir" || return
                continue
            fi
        fi

        local mypy_output ec=0
        local mypy_cmd="${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME }$mypy_bin --no-error-summary ${targets[*]}"
        mypy_output=$(eval "$mypy_cmd" 2>&1) || ec=$?
        report_check_result "Mypy ($label)" "$ec" "$mypy_output" ": error:" "type errors" "Mypy ($label): TIMED OUT after ${MAX_TEST_TIME}s" "Mypy output" ": error:"

        cd "$root_dir" || return
    done
}

# Run ESLint — scoped to this turn's changed JS/TS files (whole repo when git is
# unavailable). Prefers a project-local eslint binary over `npx`.
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

    local -a targets=()
    local changed
    changed=$(changed_code_files)
    if [ -n "$changed" ]; then
        local f
        while IFS= read -r f; do
            case "$f" in *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) targets+=("$f") ;; esac
        done <<< "$changed"
        # No changed JS/TS files this turn — nothing to lint.
        [ ${#targets[@]} -eq 0 ] && return 0
    else
        targets=(".")
    fi

    local eslint_output ec=0
    local eslint_cmd="${TIMEOUT_CMD:+$TIMEOUT_CMD 60 }$eslint_bin --no-warn-on-unmatched-pattern ${targets[*]}"
    eslint_output=$(eval "$eslint_cmd" 2>&1) || ec=$?
    report_check_result "ESLint" "$ec" "$eslint_output" "^.+:[0-9]+:[0-9]+" "issues" "ESLint: TIMED OUT" "ESLint output"
}

# Run npm audit
run_npm_audit() {
    if [ ! -f "package.json" ] || [ ! -d "node_modules" ]; then
        return 0
    fi

    local audit_output
    if audit_output=$(npm audit --json 2>&1); then
        add_warning "npm audit: no vulnerabilities"
    else
        local high_count critical_count
        if command -v jq &> /dev/null; then
            # Read the authoritative summary counts; tolerate malformed JSON.
            high_count=$(echo "$audit_output" | jq -r '.metadata.vulnerabilities.high // 0' 2>/dev/null || echo 0)
            critical_count=$(echo "$audit_output" | jq -r '.metadata.vulnerabilities.critical // 0' 2>/dev/null || echo 0)
        else
            # Fallback: scan the metadata summary object only, not per-advisory.
            local summary
            summary=$(echo "$audit_output" | grep -o '"vulnerabilities":{[^}]*}' | tail -1 || true)
            high_count=$(echo "$summary" | grep -o '"high":[0-9]*' | cut -d: -f2 || true)
            critical_count=$(echo "$summary" | grep -o '"critical":[0-9]*' | cut -d: -f2 || true)
        fi

        if [ "${critical_count:-0}" -gt 0 ] || [ "${high_count:-0}" -gt 0 ]; then
            add_critical_issue "npm audit: critical/high vulnerabilities found in Node.js dependencies"
        fi
    fi
}

# Run a single check function in isolation and persist its findings.
#
# Used as a background job by run_post_task_checks. Runs in a subshell (the
# caller backgrounds it with &), so it resets the result arrays to capture only
# this check's findings, then writes them NUL-delimited to per-job temp files.
# NUL-delimiting is required because individual findings can contain embedded
# newlines (e.g. captured test output).
_run_check_job() {
    local fn="$1" out="$2"
    CRITICAL_ISSUES=()
    WARNINGS=()
    "$fn" || true
    if [ ${#CRITICAL_ISSUES[@]} -gt 0 ]; then
        printf '%s\0' "${CRITICAL_ISSUES[@]}" > "$out.crit"
    fi
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        printf '%s\0' "${WARNINGS[@]}" > "$out.warn"
    fi
}

# Main orchestrator — runs ALL checks for the detected project type, concurrently.
run_post_task_checks() {
    setup_timeout_cmd

    local project_info
    project_info=$(detect_project_type)
    local has_python has_node has_cdk has_flutter
    IFS=':' read -r has_python has_node has_cdk has_flutter <<< "$project_info" || true

    # Select the checks to run based on project type. Each is independent and
    # only appends to the result arrays, so they can run in parallel.
    local -a checks=()
    if [ "$has_python" = "true" ]; then
        checks+=(run_python_tests run_pip_audit run_ruff_check run_mypy_check)
    fi
    if [ "$has_node" = "true" ]; then
        checks+=(run_node_tests run_npm_audit run_eslint_check)
    fi
    if [ "$has_cdk" = "true" ]; then
        checks+=(run_cdk_tests)
    fi
    if [ "$has_flutter" = "true" ]; then
        checks+=(run_flutter_tests run_dart_analyze)
    fi
    # Semgrep is multi-language, so run it once over the whole project rather
    # than per-language. It covers the SAST gap for JS/TS/Go/etc. that the
    # language-specific tools above don't.
    if [ "$has_python" = "true" ] || [ "$has_node" = "true" ] || [ "$has_cdk" = "true" ]; then
        checks+=(run_semgrep_scan)
    fi

    # Nothing applicable — let the caller know.
    if [ ${#checks[@]} -eq 0 ]; then
        return 1
    fi

    # Warm the shared discovery caches in the parent so every fanned-out subshell
    # inherits them, instead of each independently re-walking the tree / re-running
    # git status. (_PROJECT_TYPE_CACHE is already warm from detect_project_type above.)
    find_python_projects >/dev/null
    changed_code_files >/dev/null

    # Fan the checks out concurrently, each writing to its own temp files.
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/post_task.XXXXXX") || return 1

    local i=0
    for check in "${checks[@]}"; do
        _run_check_job "$check" "$tmpdir/$i" &
        i=$((i + 1))
    done
    wait

    # Slurp results back in stable (check-list) order.
    local j item
    for ((j = 0; j < i; j++)); do
        if [ -f "$tmpdir/$j.crit" ]; then
            while IFS= read -r -d '' item; do CRITICAL_ISSUES+=("$item"); done < "$tmpdir/$j.crit"
        fi
        if [ -f "$tmpdir/$j.warn" ]; then
            while IFS= read -r -d '' item; do WARNINGS+=("$item"); done < "$tmpdir/$j.warn"
        fi
    done

    rm -rf "$tmpdir"
    return 0
}

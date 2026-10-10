#!/bin/bash
#
# python_checks.sh — the Python half of the check batteries: scoped pytest
# (name-based selection, or pytest-testmon when installed), ruff, pyright/mypy
# and import-linter, monorepo-aware.
#
# Sourced by post_task.sh AFTER common.sh and its helpers (add_critical_issue,
# report_check_result, changed_code_files, find_venv_bin, project_trusted),
# which these checks call at runtime. Not meant to be executed directly.
#
# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script must be sourced, not executed directly." >&2
    exit 1
fi

# ── Python ───────────────────────────────────────────────────────────────────

# Run Python tests — monorepo-aware: runs pytest from each sub-project directory.
#
# MACOLS_PYTEST_SCOPE decides what runs:
#   changed (default) — the changed test files plus test_<module>.py for each
#                       changed module (sibling, tests/ or test/); nothing when
#                       no test matches
#   full              — the whole suite
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

    local project_dir
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

        if [ ! -d "tests" ] && [ ! -d "test" ]; then
            if ! find . -maxdepth 3 -name "test_*.py" -o -name "*_test.py" 2>/dev/null | grep -q .; then
                cd "$root_dir" || return
                continue
            fi
        fi

        local pytest_cmd="${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME }$pytest_bin -q --tb=short"
        local testmon=false
        _pytest_has_testmon "$pytest_bin" && testmon=true
        if [ "${CHECKPOINT_MODE:-0}" = "1" ]; then
            # Checkpoint: the whole suite of each project this change touches.
            if [ -n "$(changed_code_files)" ] && ! changed_code_files | grep -q "^$(pwd)/"; then
                cd "$root_dir" || return
                continue
            fi
            # Run everything, and refresh testmon's coverage map while at it.
            [ "$testmon" = true ] && pytest_cmd+=" --testmon-noselect"
        elif [ "$scope" = "changed" ] && [ "$testmon" = true ]; then
            # testmon picks the tests whose covered code changed; it runs the
            # whole suite once to build .testmondata.
            pytest_cmd+=" --testmon"
        elif [ "$scope" = "changed" ]; then
            local targets
            targets=$(impacted_test_files "$(pwd)")
            if [ -z "$targets" ]; then
                add_warning "Python tests ($label): no impacted tests found for changed files; full suite runs at the commit checkpoint"
                cd "$root_dir" || return
                continue
            fi
            pytest_cmd="${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME }$pytest_bin -q --tb=short -p no:cacheprovider$targets"
        fi

        local test_output ec=0
        test_output=$(eval "$pytest_cmd" 2>&1) || ec=$?
        # 5 = nothing collected: testmon found no affected tests.
        [ "$ec" -eq 5 ] && [ "$testmon" = true ] && ec=0
        if [ "$ec" -ne 0 ]; then
            report_test_failure "Python tests ($label)" "$ec" "$test_output"
            [ "${CHECKPOINT_MODE:-0}" = "1" ] && [ "$testmon" = false ] \
                && _record_python_escapes "$label" "$test_output"
        fi

        cd "$root_dir" || return
    done
}

# The test files this turn's changes reach, inside one project directory, one
# absolute path per line. Changed test files count as themselves; a changed
# module pulls in test_<module>.py from its own directory, tests/ or test/.
# Deliberately name-based: projects that want coverage-based selection install
# pytest-testmon, and a turn-end battery that tries to be clever on its own is
# one that runs the whole suite by accident.
impacted_test_list() {
    local project_abs="$1"
    local f base stem d cand seen=$'\n'
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        case "$f" in "$project_abs"/*.py) ;; *) continue ;; esac
        base="$(basename "$f")"
        case "$base" in
            test_*.py|*_test.py)
                case "$seen" in *$'\n'"$f"$'\n'*) ;; *) seen+="$f"$'\n'; printf '%s\n' "$f" ;; esac ;;
            *)
                stem="${base%.py}"
                for d in "$(dirname "$f")" "$project_abs/tests" "$project_abs/test"; do
                    cand="$d/test_${stem}.py"
                    [ -f "$cand" ] || continue
                    case "$seen" in *$'\n'"$cand"$'\n'*) ;; *) seen+="$cand"$'\n'; printf '%s\n' "$cand" ;; esac
                done ;;
        esac
    done <<< "$(changed_code_files)"
}

# The same list as a shell-quoted, space-prefixed string for pytest's argv.
impacted_test_files() {
    local f out=""
    while IFS= read -r f; do
        [ -n "$f" ] && out+=" $(printf '%q' "$f")"
    done < <(impacted_test_list "$1")
    printf '%s' "$out"
}

# True when this pytest's environment has pytest-testmon installed
# (MACOLS_TESTMON=off ignores it). Only a venv pytest is checked: its sibling
# python is the interpreter pytest runs under.
_pytest_has_testmon() {
    [ "${MACOLS_TESTMON:-on}" = "off" ] && return 1
    case "$1" in */*) ;; *) return 1 ;; esac
    local py
    py="$(dirname "$1")/python"
    [ -x "$py" ] && "$py" -c 'import testmon' &>/dev/null
}

# At the checkpoint: failing tests the name-based turn-end selection would not
# have run for these changes. They go to the check log as "escaped", so
# bin/macols-check-stats can say whether the fast path is missing things.
_record_python_escapes() {
    local label="$1" output="$2" line id file selected
    selected=$'\n'"$(impacted_test_list "$PWD")"$'\n'
    while IFS= read -r line; do
        id="${line#FAILED }"; id="${id%% - *}"; id="${id%% *}"
        file="${id%%::*}"
        case "$selected" in *$'\n'"$PWD/$file"$'\n'*) continue ;; esac
        ESCAPED_TESTS+=("$label: $id")
    done < <(printf '%s\n' "$output" | grep -E '^FAILED ')
}

# Iterate Python sub-projects that have changed .py files. Calls
# "<fn> <label> <proj_abs> <file>..." from inside each project directory.
for_each_changed_python_project() {
    local fn="$1" root_dir="$PWD" project_dir changed
    changed=$(changed_code_files)
    local -a projects
    read -ra projects <<< "$(find_python_projects)"
    for project_dir in "${projects[@]}"; do
        local label="$project_dir" proj_abs
        [ "$project_dir" = "." ] && label="root"
        proj_abs=$(cd "$root_dir/$project_dir" 2>/dev/null && pwd) || continue
        local -a targets=()
        if [ -n "$changed" ]; then
            local f
            while IFS= read -r f; do
                case "$f" in "$proj_abs"/*.py) targets+=("$f") ;; esac
            done <<< "$changed"
            [ ${#targets[@]} -eq 0 ] && continue
        else
            targets=(".")
        fi
        if cd "$proj_abs"; then
            "$fn" "$label" "$proj_abs" "${targets[@]}" || true
        fi
        cd "$root_dir" || return
    done
}

# ruff over the changed files, with the project's own rules (the `quality`
# skill's starter config turns on C901/PLR0913/PLR0915 and bandit's S rules).
_ruff_project() {
    local label="$1"; shift 2
    local ruff_bin out ec=0
    ruff_bin=$(find_venv_bin ruff)
    [ -z "$ruff_bin" ] && return 0
    out=$("$ruff_bin" check --output-format concise "$@" 2>&1) || ec=$?
    report_check_result "ruff ($label)" "$ec" "$out" "^.+:[0-9]+:[0-9]+:" "lint issues"
}
run_ruff_check() {
    for_each_changed_python_project _ruff_project
}

# pyright when the project configures it (pyrightconfig.json / [tool.pyright]),
# else mypy when it opts in via [tool.mypy]. Strictness is project config.
_typecheck_project() {
    local label="$1"; shift 2
    local out ec=0
    # mypy imports configured plugins (repo code); untrusted projects get
    # pyright only.
    if ! project_trusted && ! command -v pyright &>/dev/null; then return 0; fi
    if [ -f pyrightconfig.json ] || { [ -f pyproject.toml ] && grep -q '\[tool\.pyright\]' pyproject.toml; }; then
        local bin
        bin=$(find_venv_bin pyright)
        [ -z "$bin" ] && [ -x node_modules/.bin/pyright ] && bin=node_modules/.bin/pyright
        if [ -z "$bin" ]; then add_warning "pyright configured but not installed ($label)"; return 0; fi
        out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME} "$bin" "$@" 2>&1) || ec=$?
        report_check_result "pyright ($label)" "$ec" "$out" " - error:" "type errors"
    elif [ -f pyproject.toml ] && grep -q '\[tool\.mypy\]' pyproject.toml && project_trusted; then
        local bin
        bin=$(find_venv_bin mypy)
        [ -z "$bin" ] && return 0
        out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME} "$bin" --no-error-summary "$@" 2>&1) || ec=$?
        report_check_result "mypy ($label)" "$ec" "$out" ": error:" "type errors"
    fi
}
run_python_typecheck() {
    for_each_changed_python_project _typecheck_project
}

# import-linter contracts, only when the project defines some. The contract
# names in the config are the fix instruction ("features must not import each
# other's internals"), so keep them descriptive.
_import_linter_project() {
    local label="$1"
    { [ -f .importlinter ] || { [ -f pyproject.toml ] && grep -q '\[tool\.importlinter\]' pyproject.toml; } \
        || { [ -f setup.cfg ] && grep -q '\[importlinter\]' setup.cfg; }; } || return 0
    local bin out ec=0
    bin=$(find_venv_bin lint-imports)
    if [ -z "$bin" ]; then add_warning "import-linter configured but not installed ($label)"; return 0; fi
    out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD 120} "$bin" --no-cache 2>&1) || ec=$?
    report_check_result "import-linter ($label)" "$ec" "$out" "BROKEN" "broken contracts" "BROKEN|->|imports"
}
run_import_linter() {
    for_each_changed_python_project _import_linter_project
}

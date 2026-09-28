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

# ── CDK ──────────────────────────────────────────────────────────────────────

run_cdk_tests() {
    [ -f cdk.json ] || return 0
    command -v cdk &> /dev/null || { add_warning "cdk not installed - skipping synth"; return 0; }
    local out ec=0
    if [ -f "app.py" ]; then
        out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME} cdk synth --quiet 2>&1) || ec=$?
    elif grep -q "typescript" package.json 2>/dev/null; then
        out=$({ npm run build && cdk synth --quiet; } 2>&1) || ec=$?
    else
        return 0
    fi
    [ "$ec" -ne 0 ] && add_critical_issue "cdk synth: FAILED"$'\n'"$(printf '%s\n' "$out" | tail -10)"$'\n'"Fix: resolve the synth error; check for cyclic stack dependencies and update snapshot tests."
    return 0
}

# ── Flutter / Dart ───────────────────────────────────────────────────────────

# flutter test on the tests the changed files reach: changed *_test.dart files
# plus test/<path>_test.dart mirroring each changed lib/<path>.dart.
run_flutter_tests() {
    command -v flutter &> /dev/null || { add_warning "flutter not installed - skipping Flutter tests"; return 0; }
    [ -d test ] || return 0
    local -a targets=()
    local f rel cand
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        rel="${f#"$PWD"/}"
        case "$rel" in
            *_test.dart) targets+=("$rel") ;;
            lib/*.dart)
                cand="test/${rel#lib/}"; cand="${cand%.dart}_test.dart"
                [ -f "$cand" ] && targets+=("$cand") ;;
        esac
    done < <(changed_matching '*.dart')
    [ "${CHECKPOINT_MODE:-0}" = "1" ] && targets=(test)
    if [ ${#targets[@]} -eq 0 ]; then
        add_warning "Flutter tests: no impacted tests for changed files"
        return 0
    fi
    local out ec=0
    out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME} flutter test "${targets[@]}" 2>&1) || ec=$?
    [ "$ec" -ne 0 ] && report_test_failure "Flutter tests" "$ec" "$out"
    return 0
}

# dart analyze over the project (it has no multi-file mode), keeping only the
# diagnostics in changed files. Severity follows analysis_options.yaml.
run_dart_analyze() {
    command -v dart &> /dev/null || { add_warning "dart not installed - skipping Dart analysis"; return 0; }
    [ -n "$(changed_matching '*.dart')" ] || return 0
    local out ec=0 mine="" f rel
    out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME} dart analyze . 2>&1) || ec=$?
    [ "$ec" -eq 0 ] && return 0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        rel="${f#"$PWD"/}"
        mine+=$(printf '%s\n' "$out" | grep -F " $rel:" || true)
        [ -n "$mine" ] && mine+=$'\n'
    done < <(changed_matching '*.dart')
    [ -z "$mine" ] && return 0
    report_check_result "dart analyze" 1 "$mine" "^[[:space:]]*(info|warning|error) " "issues in changed files"
}

# ── Go ───────────────────────────────────────────────────────────────────────

# Directories of changed Go packages, relative to their module root, grouped as
# "<module_root>\t<./pkg/dir>" lines.
_changed_go_packages() {
    local f dir mod
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        dir=$(dirname "$f")
        mod="$dir"
        while [ "$mod" != "/" ] && [ ! -f "$mod/go.mod" ]; do mod=$(dirname "$mod"); done
        [ -f "$mod/go.mod" ] || continue
        if [ "$dir" = "$mod" ]; then
            printf '%s\t.\n' "$mod"
        else
            printf '%s\t./%s\n' "$mod" "${dir#"$mod"/}"
        fi
    done < <(changed_matching '*.go') | sort -u
}

# golangci-lint (the project's .golangci.yml: dupl, gocyclo, funlen, depguard…)
# or go vet when it isn't installed, on the changed packages; then go test
# over each changed module. Go's test cache replays packages whose code and
# dependencies are unchanged, so ./... costs the changed packages plus their
# dependents, which is exactly what can break. MACOLS_GO_TEST_SCOPE=changed
# tests only the changed packages (for modules with uncacheable tests).
run_go_checks() {
    command -v go &> /dev/null || { add_warning "go not installed - skipping Go checks"; return 0; }
    local pkgs
    pkgs=$(_changed_go_packages)
    [ -z "$pkgs" ] && return 0
    local mod
    for mod in $(printf '%s\n' "$pkgs" | cut -f1 | sort -u); do
        local -a dirs=()
        local d
        while IFS= read -r d; do [ -n "$d" ] && dirs+=("$d"); done < <(printf '%s\n' "$pkgs" | awk -F'\t' -v m="$mod" '$1 == m { print $2 }')
        local label="${mod##*/}" out ec=0
        if command -v golangci-lint &> /dev/null; then
            out=$(cd "$mod" && ${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME} golangci-lint run "${dirs[@]}" 2>&1) || ec=$?
            report_check_result "golangci-lint ($label)" "$ec" "$out" "^.+\.go:[0-9]+(:[0-9]+)?: " "issues"
        else
            out=$(cd "$mod" && go vet "${dirs[@]}" 2>&1) || ec=$?
            report_check_result "go vet ($label)" "$ec" "$out" "^.+\.go:[0-9]+(:[0-9]+)?: |^vet: " "issues"
        fi
        ec=0
        local -a race=()
        [ "${MACOLS_GO_RACE:-0}" = "1" ] && race=(-race)
        local -a test_targets=(./...)
        [ "${MACOLS_GO_TEST_SCOPE:-module}" = "changed" ] && [ "${CHECKPOINT_MODE:-0}" != "1" ] && test_targets=("${dirs[@]}")
        out=$(cd "$mod" && ${TIMEOUT_CMD:+$TIMEOUT_CMD $MAX_TEST_TIME} go test ${race[@]+"${race[@]}"} "${test_targets[@]}" 2>&1) || ec=$?
        [ "$ec" -ne 0 ] && report_test_failure "go test ($label)" "$ec" "$out"
    done
    return 0
}

# ── Shell ────────────────────────────────────────────────────────────────────

run_shellcheck() {
    command -v shellcheck &> /dev/null || return 0
    local -a files=()
    local f
    while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done < <(changed_matching '*.sh' '*.bash')
    [ ${#files[@]} -eq 0 ] && return 0
    local out ec=0
    out=$(shellcheck -f gcc "${files[@]}" 2>&1) || ec=$?
    report_check_result "shellcheck" "$ec" "$out" "^.+:[0-9]+:[0-9]+: " "issues"
}

# ── Structure: duplication and file length ───────────────────────────────────

# jscpd over the repo, keeping only clones that touch a changed file (jscpd
# can't compare "changed vs the rest" natively). A project .jscpd.json wins;
# otherwise tests, generated code and vendored dirs are ignored and a clone
# must be at least MACOLS_DUP_MIN_LINES (default 10) lines.
run_duplication_check() {
    [ "${MACOLS_DUPLICATION:-on}" = "off" ] && return 0
    local bin
    bin=$(_node_bin jscpd)
    [ -z "$bin" ] && return 0
    [ -n "$(changed_code_files)" ] || return 0
    local tmp out ec=0
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/jscpd.XXXXXX") || return 0
    local -a args=(--silent --reporters json --output "$tmp" --gitignore)
    if [ ! -f .jscpd.json ]; then
        args+=(--min-lines "${MACOLS_DUP_MIN_LINES:-10}"
            --format "python,javascript,typescript,jsx,tsx,go,dart"
            --ignore "**/node_modules/**,**/.venv/**,**/venv/**,**/vendor/**,**/dist/**,**/build/**,**/test/**,**/tests/**,**/__tests__/**,**/testdata/**,**/*_test.go,**/*.test.*,**/*.spec.*,**/test_*.py,**/*.g.dart,**/*.freezed.dart,**/*.pb.go,**/*_pb2.py")
    fi
    out=$(${TIMEOUT_CMD:+$TIMEOUT_CMD 120} "$bin" "${args[@]}" . 2>&1) || ec=$?
    if [ "$ec" -eq 124 ]; then
        add_warning "jscpd timed out; set MACOLS_DUPLICATION=off for this repo or add a .jscpd.json"
        rm -rf "$tmp"; return 0
    fi
    [ -f "$tmp/jscpd-report.json" ] || { rm -rf "$tmp"; return 0; }
    local clones
    clones=$(CHANGED="$(changed_code_files)" ROOT="$PWD" REPORT="$tmp/jscpd-report.json" node -e '
const fs = require("fs"), path = require("path");
const changed = new Set(process.env.CHANGED.split("\n").filter(Boolean).map(f => path.resolve(f)));
const r = JSON.parse(fs.readFileSync(process.env.REPORT, "utf8"));
const abs = f => path.resolve(process.env.ROOT, f);
for (const d of r.duplicates || []) {
  const a = d.firstFile, b = d.secondFile;
  if (!changed.has(abs(a.name)) && !changed.has(abs(b.name))) continue;
  console.log(`${a.name}:${a.start}-${a.end} duplicates ${b.name}:${b.start}-${b.end} (${d.lines} lines)`);
}' 2>/dev/null || true)
    rm -rf "$tmp"
    [ -z "$clones" ] && return 0
    report_check_result "jscpd duplication" 1 "$clones" " duplicates " "clones touching changed files"
}

run_file_length_check() {
    local out
    out=$(changed_code_files | check_file_lengths)
    [ -z "$out" ] && return 0
    report_check_result "file length" 1 "$out" "file too long" "files over the limit"
}

# ── Security (opt-in locally; CI's job by default) ───────────────────────────

# semgrep over changed files. Off by default: rule loading alone costs 6-16s a
# turn and ~100s when the registry is unreachable, and ruff's S rules catch the
# cheap cases locally. MACOLS_SEMGREP=1 turns it back on. A scan that fails to
# run is a warning, never a silent pass.
run_semgrep_scan() {
    [ "${MACOLS_SEMGREP:-0}" = "1" ] || return 0
    command -v semgrep &> /dev/null || return 0
    local project_info has_python has_node has_cdk has_flutter has_go
    project_info=$(detect_project_type)
    IFS=':' read -r has_python has_node has_cdk has_flutter has_go <<< "$project_info" || true

    local -a configs=(--config p/secrets)
    [ "$has_python" = "true" ] && configs+=(--config p/python)
    [ "$has_node" = "true" ] && configs+=(--config p/javascript --config p/typescript)
    [ "$has_go" = "true" ] && configs+=(--config p/golang)

    local -a scan_targets=()
    local f
    while IFS= read -r f; do [ -n "$f" ] && scan_targets+=("$f"); done <<< "$(changed_code_files)"
    [ ${#scan_targets[@]} -eq 0 ] && scan_targets=(".")

    local out ec=0
    out=$(SEMGREP_ENABLE_VERSION_CHECK=0 ${TIMEOUT_CMD:+$TIMEOUT_CMD 120} semgrep scan "${configs[@]}" \
        --quiet --metrics=off --timeout 30 --severity ERROR --json \
        --exclude .venv --exclude venv --exclude node_modules --exclude dist --exclude build \
        "${scan_targets[@]}" 2>/dev/null) || ec=$?
    if ! printf '%s' "$out" | jq -e '.results' > /dev/null 2>&1; then
        add_warning "semgrep did not run (exit $ec; registry unreachable or timed out) - CI covers SAST"
        return 0
    fi
    local n detail
    n=$(printf '%s' "$out" | jq -r '.results | length')
    [ "${n:-0}" -eq 0 ] && return 0
    detail=$(printf '%s' "$out" | jq -r '.results[] | "  \(.path):\(.start.line) \(.check_id)"' | head -15)
    add_critical_issue "semgrep: $n ERROR-severity finding(s)"$'\n'"$detail"$'\n'"Fix: remove the unsafe pattern (validate input, parameterise queries, avoid shell=True); do not add a nosemgrep comment."
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

#!/bin/bash
#
# lang_checks.sh — the remaining per-language batteries: cdk synth, Flutter
# (scoped flutter test + dart analyze), Go (golangci-lint/go vet + go test),
# and shellcheck for scripts.
#
# Sourced by post_task.sh AFTER common.sh and its helpers (add_critical_issue,
# report_check_result, report_test_failure, changed_matching). Not meant to be
# executed directly.
#
# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script must be sourced, not executed directly." >&2
    exit 1
fi

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

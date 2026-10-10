#!/bin/bash
#
# structure_checks.sh — repo-shape checks: jscpd duplication touching changed
# files, the file-length limit, and the opt-in local semgrep scan.
#
# Sourced by post_task.sh AFTER node_checks.sh (run_duplication_check resolves
# jscpd through _node_bin) and common.sh's helpers. Not meant to be executed
# directly.
#
# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script must be sourced, not executed directly." >&2
    exit 1
fi

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
    # shellcheck disable=SC2016  # the node script is meant to stay unexpanded
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
    # has_cdk/has_flutter belong to the orchestrator in post_task.sh; semgrep
    # reads the python/node/go slots of the same tuple.
    # shellcheck disable=SC2034
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

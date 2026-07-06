#!/bin/bash
#
# spec_drift_gate.sh — check the repo's ast-grep spec anchors.
#
# Anchors bind living-spec sections (openspec/specs/*/spec.md, marked with
# <!-- anchor: <id> -->) to the code that implements them, via ast-grep rules
# in specs/anchors/*.yml (map keyed by id: { language, rule, files }). See
# openspec/specs/spec-anchoring/spec.md and
# https://coles.codes/posts/anchoring-specs-to-code-with-ast-grep/
#
# Runs against the git repo containing the current working directory.
#
# Modes:
#   --check              Hygiene: every rule resolves to exactly one site.
#                        Exits 1 on any dangling (0 matches) or loose (>1) rule.
#   [--base <ref>]       Drift gate vs the merge-base with <ref> (default
#                        origin/main, falling back to main). Warns per rule:
#                          DANGLING — matched at the base, matches nothing now
#                                     (usually a rename nobody re-pointed)
#                          DRIFT    — match overlaps this branch's changed lines
#                                     while neither the spec section's prose nor
#                                     its rule was touched
#                        Advisory by design: always exits 0.
#   --github             With drift mode: also emit ::warning:: annotations and
#                        a $GITHUB_STEP_SUMMARY table.
#
# Rules for languages the installed ast-grep cannot parse belong in
# specs/anchors/quarantine/ — one unloadable rule would abort a whole scan.
#
# Requires: git, jq, ast-grep, yq (either flavor: mikefarah Go yq or the
# kislyuk jq wrapper). Bash 3.2 compatible (macOS default shell).

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
TAB=$(printf '\t')

MODE="drift"
BASE_REF=""
GITHUB_OUT=false

usage() { sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; }

die() { printf "${RED}%s${NC}\n" "$*" >&2; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --check)  MODE="check" ;;
        --base)   shift; [ $# -gt 0 ] || die "--base needs a ref"; BASE_REF="$1" ;;
        --github) GITHUB_OUT=true ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1 (see --help)" ;;
    esac
    shift
done

for tool in git jq ast-grep yq; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool not found — the drift gate needs git, jq, ast-grep and yq"
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$ROOT" || die "cannot cd to $ROOT"

# No anchors → nothing to do (repos opt in by having specs/anchors/*.yml).
ls specs/anchors/*.yml >/dev/null 2>&1 || { printf "${YELLOW}No specs/anchors/*.yml — spec anchors not in use here.${NC}\n"; exit 0; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/spec_drift.XXXXXX")" || die "mktemp failed"
BASE_TREE="$WORK/base"
cleanup() {
    if [ -d "$BASE_TREE" ]; then git worktree remove --force "$BASE_TREE" >/dev/null 2>&1 || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

# yaml2json <file> — normalise either yq flavor to JSON on stdout.
# mikefarah (Go) yq wants `-o=json .`; kislyuk (python) yq is a jq wrapper
# where plain `.` already emits JSON. Probe once, remember the flavor.
YQ_FLAVOR=""
yaml2json() {
    if [ -z "$YQ_FLAVOR" ]; then
        if printf 'probe: 1\n' | yq -o=json '.' - >/dev/null 2>&1; then YQ_FLAVOR="mikefarah"
        elif printf 'probe: 1\n' | yq '.' >/dev/null 2>&1; then YQ_FLAVOR="kislyuk"
        else die "yq found but neither flavor probe worked — cannot parse anchor YAML"
        fi
    fi
    if [ "$YQ_FLAVOR" = "mikefarah" ]; then yq -o=json '.' "$1"; else yq '.' "$1"; fi
}

# Compile every anchor entry into a native single-rule ast-grep file under
# $WORK/rules/<n>.yml (emitted as JSON — valid YAML — so no YAML writer is
# needed) and record "<n>\t<id>\t<source-yml>" lines in $WORK/ids.tsv.
compile_rules() {
    mkdir -p "$WORK/rules"
    : > "$WORK/ids.tsv"
    local yml n=0 entry id
    for yml in specs/anchors/*.yml; do
        yaml2json "$yml" > "$WORK/anchors.json" || die "unparseable YAML: $yml"
        while IFS= read -r entry; do
            id=$(printf '%s' "$entry" | jq -r '.key')
            printf '%s' "$entry" | jq '{id: .key, language: .value.language, severity: "hint",
                                        message: ("spec anchor " + .key), files: .value.files, rule: .value.rule}' \
                > "$WORK/rules/$n.yml"
            jq -e '.language and .files and .rule' "$WORK/rules/$n.yml" >/dev/null \
                || die "anchor '$id' in $yml needs language, rule and files keys"
            printf '%s\t%s\t%s\n' "$n" "$id" "$yml" >> "$WORK/ids.tsv"
            n=$((n + 1))
        done < <(jq -c 'to_entries[]' "$WORK/anchors.json")
    done
    [ -s "$WORK/ids.tsv" ] || die "specs/anchors/*.yml contain no anchor entries"
}

# scan_rule <tree-root> <rule-file> <out-file>
# Writes one "file\tstart\tend" line per match (1-based lines; ast-grep JSON
# is 0-based). Writes the ERROR sentinel when ast-grep cannot run the rule.
scan_rule() {
    local tree="$1" rule="$2" out="$3" json
    if ! json=$(cd "$tree" && ast-grep scan --rule "$rule" --json=compact . 2>/dev/null); then
        printf 'ERROR\n' > "$out"; return 1
    fi
    printf '%s' "$json" | jq -r '.[] | [.file, (.range.start.line + 1), (.range.end.line + 1)] | @tsv' > "$out"
}

# spec_section <id> — locate the spec section that carries <!-- anchor: id -->.
# Prints "file\tstart\tend" (the enclosing ###-section, scenarios included) or
# nothing when the comment is missing from every spec.
spec_section() {
    local id="$1" hit file line
    hit=$(grep -rn -F "<!-- anchor: $id -->" openspec/specs 2>/dev/null | head -1) || true
    [ -n "$hit" ] || return 1
    file=${hit%%:*}
    line=$(printf '%s' "$hit" | cut -d: -f2)
    awk -v n="$line" -v f="$file" '
        NR <= n && /^### / { s = NR }
        NR > n && (/^### / || /^## / || /^# /) { e = NR - 1; exit }
        END { if (!s) s = 1; if (!e) e = NR; printf "%s\t%d\t%d\n", f, s, e }' "$file"
}

# ranges_overlap <file> <start> <end> <ranges-tsv> — true when [start,end] of
# <file> intersects any changed range recorded in the tsv.
ranges_overlap() {
    local file="$1" s="$2" e="$3" tsv="$4" cf cs ce
    while IFS="$TAB" read -r cf cs ce; do
        [ "$cf" = "$file" ] || continue
        [ "$cs" -le "$e" ] && [ "$ce" -ge "$s" ] && return 0
    done < "$tsv"
    return 1
}

# section_touched <id> <source-yml> — the diff also moved the spec: either the
# section's prose changed, or the anchor's own rule lines did.
section_touched() {
    local id="$1" yml="$2" sec file s e
    if sec=$(spec_section "$id"); then
        file=$(printf '%s' "$sec" | cut -f1)
        s=$(printf '%s' "$sec" | cut -f2)
        e=$(printf '%s' "$sec" | cut -f3)
        ranges_overlap "$file" "$s" "$e" "$WORK/changed.tsv" && return 0
    fi
    git diff -U0 "$MBASE" HEAD -- "$yml" 2>/dev/null | grep -E '^[-+][^-+]' | grep -qF "$id:" && return 0
    return 1
}

warn_line() { # <id> <status> <file> <line> <message>
    printf "${YELLOW}⚠ %-9s %s — %s${NC}\n" "$2" "$1" "$5"
    if [ "$GITHUB_OUT" = true ]; then
        printf '::warning file=%s,line=%s::[spec-drift] %s %s: %s\n' "$3" "$4" "$2" "$1" "$5"
        printf '| `%s` | %s | %s:%s | %s |\n' "$1" "$2" "$3" "$4" "$5" >> "$WORK/summary.md"
    fi
}

# check_hygiene — every rule must resolve to exactly one site right now.
check_hygiene() {
    local fails=0 n id yml count
    while IFS="$TAB" read -r n id yml; do
        scan_rule "$ROOT" "$WORK/rules/$n.yml" "$WORK/head.$n" || true
        if grep -q '^ERROR$' "$WORK/head.$n"; then
            printf "${RED}✗ unloadable %s (%s) — fix the rule or quarantine it${NC}\n" "$id" "$yml"; fails=1; continue
        fi
        count=$(grep -c . "$WORK/head.$n" || true)
        if [ "$count" -eq 0 ]; then
            printf "${RED}✗ dangling  %s — no match (re-point the rule in %s)${NC}\n" "$id" "$yml"; fails=1
        elif [ "$count" -gt 1 ]; then
            printf "${RED}✗ loose     %s — %s matches (tighten with inside/files):${NC}\n" "$id" "$count"; fails=1
            sed 's/^/    /' "$WORK/head.$n"
        else
            printf "${GREEN}✓ %s → %s${NC}\n" "$id" "$(awk -F'\t' '{print $1 ":" $2}' "$WORK/head.$n")"
        fi
    done < "$WORK/ids.tsv"
    return "$fails"
}

# classify_rule <n> <id> <yml> — drift-mode verdict for one rule:
# DANGLING (matched at merge-base, nothing now), DRIFT (match overlaps the
# branch's changed lines and the spec did not move), otherwise quiet.
classify_rule() {
    local n="$1" id="$2" yml="$3" head_count base_count file s e
    scan_rule "$ROOT" "$WORK/rules/$n.yml" "$WORK/head.$n" || true
    if grep -q '^ERROR$' "$WORK/head.$n"; then
        warn_line "$id" "ERROR" "$yml" 1 "rule failed to load — fix or quarantine it"
        return
    fi
    head_count=$(grep -c . "$WORK/head.$n" || true)
    if [ "$head_count" -eq 0 ]; then
        scan_rule "$BASE_TREE" "$WORK/rules/$n.yml" "$WORK/base.$n" || true
        base_count=$(grep -c . "$WORK/base.$n" 2>/dev/null || true)
        if [ "${base_count:-0}" -gt 0 ]; then
            warn_line "$id" "DANGLING" "$yml" 1 "matched at the merge-base but matches nothing now (rename? re-point the rule)"
        else
            warn_line "$id" "DANGLING" "$yml" 1 "matches nothing on either side (fix the rule)"
        fi
        return
    fi
    while IFS="$TAB" read -r file s e; do
        if ranges_overlap "$file" "$s" "$e" "$WORK/changed.tsv" && ! section_touched "$id" "$yml"; then
            warn_line "$id" "DRIFT" "$file" "$s" "anchored code changed but its spec section did not — spec update (or explicit no-change call) missing"
        fi
    done < "$WORK/head.$n"
}

run_drift() {
    if [ -z "$BASE_REF" ]; then
        if git rev-parse --verify -q origin/main >/dev/null; then BASE_REF="origin/main"; else BASE_REF="main"; fi
    fi
    MBASE=$(git merge-base HEAD "$BASE_REF" 2>/dev/null) || die "cannot find merge-base with '$BASE_REF' (pass --base, and fetch enough history: fetch-depth 0 in CI)"
    git worktree add --detach "$BASE_TREE" "$MBASE" >/dev/null 2>&1 || die "git worktree add failed"

    # New-side line ranges per changed file (deletions recorded as the line
    # they landed on, so edits adjacent to a match still intersect).
    git diff -U0 -M "$MBASE" HEAD | awk '
        /^\+\+\+ / { path = ($2 == "/dev/null") ? "" : substr($2, 3); next }
        /^@@/ {
            if (path == "") next
            if (match($0, /\+[0-9]+(,[0-9]+)?/)) {
                spec = substr($0, RSTART + 1, RLENGTH - 1)
                n = split(spec, a, ","); start = a[1]; len = (n > 1) ? a[2] : 1
                if (len == 0) { if (start == 0) start = 1; end = start } else end = start + len - 1
                printf "%s\t%d\t%d\n", path, start, end
            }
        }' > "$WORK/changed.tsv"

    if [ "$GITHUB_OUT" = true ]; then
        printf '| anchor | status | site | note |\n|---|---|---|---|\n' > "$WORK/summary.md"
    fi

    printf "${BLUE}Spec drift gate — HEAD vs merge-base %s (%s)${NC}\n" "$BASE_REF" "$(git rev-parse --short "$MBASE")"
    local n id yml
    while IFS="$TAB" read -r n id yml; do
        classify_rule "$n" "$id" "$yml"
    done < "$WORK/ids.tsv"

    if [ "$GITHUB_OUT" = true ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        if [ "$(grep -c . "$WORK/summary.md")" -gt 2 ]; then
            { printf '## Spec drift gate\n\n'; cat "$WORK/summary.md"; } >> "$GITHUB_STEP_SUMMARY"
        else
            printf '## Spec drift gate\n\nNo drift — all anchors quiet. ✅\n' >> "$GITHUB_STEP_SUMMARY"
        fi
    fi
    printf "${GREEN}Done (advisory — never blocks).${NC}\n"
    return 0
}

compile_rules

if [ "$MODE" = "check" ]; then
    printf "${BLUE}Spec anchor hygiene — every rule must resolve exactly once${NC}\n"
    if check_hygiene; then
        printf "${GREEN}✓ All anchors healthy${NC}\n"; exit 0
    else
        printf "${RED}Anchor hygiene failed — dangling/loose rules are spec drift; fix them in this change.${NC}\n"; exit 1
    fi
else
    run_drift
fi

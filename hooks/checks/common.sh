#!/bin/bash
#
# Shared Check Helpers — single source of truth for the bits that the per-edit
# (post_code.sh) and turn-end (post_task.sh) batteries both need.
#
# Sourced, never executed. Holds only environment/discovery helpers and the
# change gate; the actual checks live in the two battery files that source this.
#
# Provides:
#   setup_timeout_cmd    — sets TIMEOUT_CMD for macOS/Linux compatibility
#   code_changed         — turn-end gate: did this turn touch code?
#   changed_code_files   — absolute paths of changed code files (cached)
#   changes_since_last_check / record_check_fingerprint
#                        — skip the turn-end battery when nothing changed since
#                          it last ran (Q&A turns after an edit)
#   detect_project_type  — echoes "has_python:has_node:has_cdk:has_flutter:has_go" (cached)
#   fix_hint <output>    — fix instructions for the rule ids found in tool output
#   check_file_lengths   — flag changed files that grew past MACOLS_MAX_FILE_LINES
#   find_venv_bin <tool> — resolve a tool from a virtualenv, walking to repo root
#   find_python_projects — discover testable Python sub-projects (cached)
#
# The two discovery functions memoize their result for the life of the process,
# so callers that invoke them repeatedly (tests + ruff + mypy) don't re-walk the
# tree each time. Caches are per-process, so parallel subshells recompute once.
#

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script must be sourced, not executed directly." >&2
    exit 1
fi

# Ensure Node.js is in PATH (sources NVM/fnm if needed). Cheap no-op when node
# is already resolvable, so safe to source from every hook.
_CHECKS_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ensure_node.sh
if [ -f "$_CHECKS_COMMON_DIR/ensure_node.sh" ]; then
    source "$_CHECKS_COMMON_DIR/ensure_node.sh"
fi

# macOS compatibility: use gtimeout (brew install coreutils) or fall back.
# shellcheck disable=SC2034  # TIMEOUT_CMD is consumed by the battery files that source this
setup_timeout_cmd() {
    if command -v gtimeout &> /dev/null; then
        TIMEOUT_CMD="gtimeout"
    elif command -v timeout &> /dev/null; then
        TIMEOUT_CMD="timeout"
    else
        TIMEOUT_CMD=""
    fi
}

# Gate: has any code been changed in the working tree?
#
# Returns 0 (run the checks) when the git working tree contains added/modified/
# untracked files with a code extension, OR when we can't tell (no git, not a
# repo) — we never silently suppress checks. Returns 1 (skip) when the tree is
# clean of code changes, e.g. a Q&A or docs-only turn. This keeps the full
# test/lint/typecheck battery from running on every turn that didn't touch code.
code_changed() {
    command -v git &> /dev/null || return 0
    git rev-parse --is-inside-work-tree &> /dev/null || return 0

    local changed
    changed=$(git status --porcelain 2>/dev/null | sed 's/^...//;s/.* -> //')
    [ -z "$changed" ] && return 1

    if echo "$changed" | grep -qiE '\.(py|ts|tsx|js|jsx|mjs|cjs|dart|go|rs|java|rb|kt|swift|c|cc|cpp|h|hpp|cs|php|scala|sql|sh|bash)$'; then
        return 0
    fi
    return 1
}

# Echo the absolute paths of changed (added/modified/untracked) code files, one
# per line — memoized for the life of the process.
#
# Lets the turn-end battery scope its linters to just the files this turn
# touched instead of re-linting the whole repo. Returns an EMPTY list when git
# is unavailable / not a repo, which callers treat as "fall back to a full scan"
# (we never silently lint nothing). Note: empty is ambiguous with "a repo whose
# only changes are non-code files", but the turn-end battery only runs after
# code_changed() already returned true, so in practice a reachable empty result
# means git is unavailable.
changed_code_files() {
    if [ -n "${_CHANGED_FILES_CACHE+x}" ]; then
        printf '%s' "$_CHANGED_FILES_CACHE"
        return 0
    fi

    local files=""
    if command -v git &> /dev/null && git rev-parse --is-inside-work-tree &> /dev/null; then
        local root f
        root=$(git rev-parse --show-toplevel 2>/dev/null)
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            # Skip paths that no longer exist (deletions, the old side of a
            # rename) so linters aren't handed missing files.
            [ -f "$root/$f" ] || continue
            case "$f" in
                *.py|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.dart|*.go|*.rs|*.java|*.rb|*.kt|*.swift|*.c|*.cc|*.cpp|*.h|*.hpp|*.cs|*.php|*.scala|*.sql|*.sh|*.bash)
                    files+="$root/$f"$'\n' ;;
            esac
        done < <(git status --porcelain 2>/dev/null | sed 's/^...//;s/.* -> //')
    fi

    _CHANGED_FILES_CACHE="$files"
    printf '%s' "$_CHANGED_FILES_CACHE"
}

# Detect project type — memoized for the life of the process.
detect_project_type() {
    if [ -n "${_PROJECT_TYPE_CACHE:-}" ]; then
        echo "$_PROJECT_TYPE_CACHE"
        return 0
    fi

    local has_python=false
    local has_node=false
    local has_cdk=false
    local has_flutter=false
    local has_go=false

    if [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] || [ -f "setup.py" ]; then
        has_python=true
    fi
    # Also detect monorepo sub-projects with their own pyproject.toml
    if [ "$has_python" = "false" ]; then
        if find . -maxdepth 3 -name "pyproject.toml" -not -path "*/.venv/*" -not -path "*/node_modules/*" 2>/dev/null | grep -q .; then
            has_python=true
        fi
    fi

    if [ -f "package.json" ]; then
        has_node=true
    fi

    if [ -f "cdk.json" ]; then
        has_cdk=true
    fi

    if [ -f "pubspec.yaml" ]; then
        has_flutter=true
    fi

    if [ -f "go.mod" ] || [ -f "go.work" ] \
        || find . -maxdepth 3 -name "go.mod" -not -path "*/vendor/*" -not -path "*/node_modules/*" 2>/dev/null | grep -q .; then
        has_go=true
    fi

    _PROJECT_TYPE_CACHE="${has_python}:${has_node}:${has_cdk}:${has_flutter}:${has_go}"
    echo "$_PROJECT_TYPE_CACHE"
}

# ── Project trust ────────────────────────────────────────────────────────────
# Tests, cdk synth, and anything resolved from the repo (.venv/bin,
# node_modules/.bin) or configured in executable config (eslint.config.js,
# .dependency-cruiser.cjs, mypy plugins, analyzer/linter plugins) run code the
# repository controls. A cloned or reviewed repo must not get that just
# because the agent edited a file in it, so those checks only run in trusted
# projects. Untrusted projects still get the checks that only read files:
# ruff and pyright from PATH, shellcheck, gofmt, jscpd and the file-length
# limit.
#
# Trust a project by adding its root (or a glob such as ~/code/*) to
# MACOLS_TRUST_FILE, one per line; `bin/macols-trust` does it for the current
# repo. MACOLS_TRUST_ALL=1 trusts everything.
MACOLS_TRUST_FILE="${MACOLS_TRUST_FILE:-$HOME/.config/macols/trusted-projects}"

project_root() {
    git rev-parse --show-toplevel 2>/dev/null || pwd -P
}

project_trusted() {
    if [ -n "${_PROJECT_TRUSTED_CACHE:-}" ]; then
        [ "$_PROJECT_TRUSTED_CACHE" = yes ]; return
    fi
    _PROJECT_TRUSTED_CACHE=no
    if [ "${MACOLS_TRUST_ALL:-0}" = "1" ]; then
        _PROJECT_TRUSTED_CACHE=yes
    elif [ -f "$MACOLS_TRUST_FILE" ]; then
        local root line
        root=$(project_root)
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%%#*}"
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [ -z "$line" ] && continue
            line="${line/#\~/$HOME}"
            # shellcheck disable=SC2053  # the entry is a glob on purpose
            if [[ "$root" == $line ]]; then _PROJECT_TRUSTED_CACHE=yes; break; fi
        done < "$MACOLS_TRUST_FILE"
    fi
    [ "$_PROJECT_TRUSTED_CACHE" = yes ]
}

# Find a tool binary from a virtualenv, walking up to repo root. In an
# untrusted project only PATH is searched: a repo-shipped .venv/bin/<tool> is
# repo code.
# Usage: find_venv_bin <tool_name>  e.g. find_venv_bin pytest
find_venv_bin() {
    local tool="$1"
    if ! project_trusted; then
        command -v "$tool" &> /dev/null && echo "$tool" || echo ""
        return 0
    fi
    # Check cwd first
    for venv_dir in .venv venv env; do
        if [ -f "$venv_dir/bin/$tool" ]; then
            echo "$(pwd)/$venv_dir/bin/$tool"
            return 0
        fi
    done
    # Walk up to repo root looking for a shared venv
    local search_dir="$PWD"
    while [ "$search_dir" != "/" ]; do
        for venv_dir in .venv venv env; do
            if [ -f "$search_dir/$venv_dir/bin/$tool" ]; then
                echo "$search_dir/$venv_dir/bin/$tool"
                return 0
            fi
        done
        search_dir="$(dirname "$search_dir")"
    done
    # Fall back to PATH
    if command -v "$tool" &> /dev/null; then
        echo "$tool"
        return 0
    fi
    echo ""
}


# Discover Python sub-projects — memoized for the life of the process.
# Returns directories containing pyproject.toml that also have a test/ or tests/
# directory (i.e. testable sub-projects). Falls back to "." if no sub-projects
# are found.
find_python_projects() {
    if [ -n "${_PYTHON_PROJECTS_CACHE:-}" ]; then
        echo "$_PYTHON_PROJECTS_CACHE"
        return 0
    fi

    local -a projects=()

    # Find sub-projects by pyproject.toml that have test directories
    while IFS= read -r toml; do
        local dir
        dir="$(dirname "$toml")"
        # Skip root-level pyproject.toml (handled as fallback)
        [ "$dir" = "." ] && continue
        if [ -d "$dir/test" ] || [ -d "$dir/tests" ]; then
            projects+=("$dir")
        fi
    done < <(find . -maxdepth 4 -name "pyproject.toml" -not -path "*/.venv/*" -not -path "*/node_modules/*" 2>/dev/null | sort)

    # If no sub-projects found, fall back to root
    if [ ${#projects[@]} -eq 0 ]; then
        projects=(".")
    fi

    _PYTHON_PROJECTS_CACHE="${projects[*]}"
    echo "$_PYTHON_PROJECTS_CACHE"
}


# ── Change fingerprint ───────────────────────────────────────────────────────
# The turn-end battery used to run whenever the tree was dirty, so every Q&A
# turn after an edit re-ran everything until the next commit. The fingerprint
# covers tracked diffs plus untracked file contents; when it matches the one
# recorded by the last run, nothing changed and the battery is skipped. This
# also stops a Stop hook from looping: if the agent was told about findings and
# changed nothing, the next stop is allowed through.
_check_fingerprint() {
    command -v git &> /dev/null || return 1
    git rev-parse --is-inside-work-tree &> /dev/null || return 1
    {
        git rev-parse HEAD 2>/dev/null || true
        git diff HEAD --no-ext-diff --binary 2>/dev/null || git diff --no-ext-diff --binary 2>/dev/null || true
        git ls-files --others --exclude-standard -z 2>/dev/null \
            | xargs -0 git hash-object -- 2>/dev/null || true
    } | git hash-object --stdin 2>/dev/null
}

_check_fingerprint_file() {
    local gitdir
    gitdir=$(git rev-parse --git-dir 2>/dev/null) || return 1
    printf '%s/macols-last-check' "$gitdir"
}

# Returns 0 when the tree changed since the last recorded run (or when we
# can't tell), 1 when it is identical.
changes_since_last_check() {
    local fp file
    fp=$(_check_fingerprint) || return 0
    file=$(_check_fingerprint_file) || return 0
    [ -f "$file" ] && [ "$(cat "$file" 2>/dev/null)" = "$fp" ] && return 1
    return 0
}

record_check_fingerprint() {
    local fp file
    fp=$(_check_fingerprint) || return 0
    file=$(_check_fingerprint_file) || return 0
    printf '%s' "$fp" > "$file" 2>/dev/null || true
}

# ── Fix hints ────────────────────────────────────────────────────────────────
# Every gate failure should tell the agent what to do, not just what broke.
# fix_hint scans a tool's output for known rule ids and prints one instruction
# per matched rule family. Project configs can carry their own messages
# (import-linter contract names, dependency-cruiser comments); these cover the
# stock linters whose messages can't be customised.
fix_hint() {
    local out="$1" hints=""
    if printf '%s' "$out" | grep -qE 'C901|[( ]complexity([) ]|$)|gocyclo|cyclop|gocognit'; then
        hints+="Fix: reduce complexity by extracting branches into small named helpers or using early returns. Do not raise the limit or add a suppression."$'\n'
    fi
    if printf '%s' "$out" | grep -qE 'PLR0913|PLR0917|max-params|argument-limit'; then
        hints+="Fix: too many parameters. Group related arguments into a dataclass/typed object, or split the function by responsibility."$'\n'
    fi
    if printf '%s' "$out" | grep -qE 'PLR0915|PLR0912|PLR0911|max-lines-per-function|max-statements|funlen'; then
        hints+="Fix: function too long. Split it into smaller functions that each do one thing."$'\n'
    fi
    if printf '%s' "$out" | grep -qE 'max-lines([^-]|$)|file too long'; then
        hints+="Fix: file too long. Split it by feature into smaller modules behind a small public interface."$'\n'
    fi
    if printf '%s' "$out" | grep -qE 'jscpd|[( ]dupl([) ]|$)|[Dd]uplicat|[Cc]lone'; then
        hints+="Fix: duplicated code. Extract the shared logic into one function in the owning feature module (or a shared core module if two features need it) and call it from both places."$'\n'
    fi
    if printf '%s' "$out" | grep -qE 'import-linter|lint-imports|dependency-cruiser|depcruise|depguard|Contract .* BROKEN'; then
        hints+="Fix: layer rule broken. Depend on the other feature's public interface, or move the shared code down a layer. Do not import another feature's internals."$'\n'
    fi
    if printf '%s' "$out" | grep -qE '[: ]S[0-9]{3} |gosec|G[0-9]{3}:'; then
        hints+="Fix: security rule. Remove the unsafe pattern (pass argv lists instead of shell=True, parameterise queries, validate input). Do not suppress it."$'\n'
    fi
    if printf '%s' "$out" | grep -qE ': error:|error TS[0-9]+|reportGeneralTypeIssues|- error:'; then
        hints+="Fix: correct the types. Do not add ignores, casts to Any/any, or loosen the type-checker config."$'\n'
    fi
    printf '%s' "$hints"
}

# ── File length ──────────────────────────────────────────────────────────────
# Language-agnostic file-length limit. Only flags files that are over the limit
# AND longer than they were at HEAD, so touching an already-long file for a
# one-line fix doesn't turn into a forced refactor. Tests and generated files
# are exempt. Echoes one finding per file.
check_file_lengths() {
    local max="${MACOLS_MAX_FILE_LINES:-500}" f lines before rel root
    [ "$max" = "0" ] && return 0
    root=$(git rev-parse --show-toplevel 2>/dev/null) || root=""
    while IFS= read -r f; do
        [ -z "$f" ] || [ ! -f "$f" ] && continue
        case "$(basename "$f")" in
            test_*|*_test.*|*.test.*|*.spec.*|*.g.dart|*.freezed.dart|*.pb.go|*_pb2.py|*.min.js|*.d.ts) continue ;;
        esac
        case "$f" in */tests/*|*/test/*|*/__tests__/*|*/testdata/*|*/generated/*|*/vendor/*|*/node_modules/*) continue ;;
            *.py|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.dart|*.go|*.sh) ;;
            *) continue ;;
        esac
        lines=$(wc -l < "$f" | tr -d ' ')
        [ "$lines" -le "$max" ] && continue
        before=0
        if [ -n "$root" ]; then
            rel="${f#"$root"/}"
            before=$(git show "HEAD:$rel" 2>/dev/null | wc -l | tr -d ' ')
        fi
        [ "$lines" -le "${before:-0}" ] && continue
        printf '%s: file too long (%s lines, limit %s, was %s)\n' "$f" "$lines" "$max" "${before:-0}"
    done
}

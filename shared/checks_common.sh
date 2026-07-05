#!/bin/bash
#
# Shared Check Helpers — single source of truth for the bits that the per-edit
# (post_code_checks.sh) and turn-end (post_task_checks.sh) batteries both need.
#
# Sourced, never executed. Holds only environment/discovery helpers and the
# change gate; the actual checks live in the two battery files that source this.
#
# Provides:
#   setup_timeout_cmd    — sets TIMEOUT_CMD for macOS/Linux compatibility
#   code_changed         — turn-end gate: did this turn touch code?
#   detect_project_type  — echoes "has_python:has_node:has_cdk:has_flutter" (cached)
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

    if echo "$changed" | grep -qiE '\.(py|ts|tsx|js|jsx|mjs|cjs|dart|go|rs|java|rb|kt|swift|c|cc|cpp|h|hpp|cs|php|scala|sql)$'; then
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
                *.py|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.dart|*.go|*.rs|*.java|*.rb|*.kt|*.swift|*.c|*.cc|*.cpp|*.h|*.hpp|*.cs|*.php|*.scala|*.sql)
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

    _PROJECT_TYPE_CACHE="${has_python}:${has_node}:${has_cdk}:${has_flutter}"
    echo "$_PROJECT_TYPE_CACHE"
}

# Find a tool binary from a virtualenv, walking up to repo root.
# Usage: find_venv_bin <tool_name>  e.g. find_venv_bin pytest
find_venv_bin() {
    local tool="$1"
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

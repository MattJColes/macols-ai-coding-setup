---
agent: true
name: linux
description: Linux, shell scripting, and system administration specialist. Use for bash scripts, git operations, system configuration, and CLI tools.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
user-invocable: true
---

House conventions for shell, git, and Linux systems work — the patterns these
machines expect, not generic bash tutorials. Current models write serviceable
bash already; this file exists to make it *this* setup's bash.

## Shell Script Template
```bash
#!/usr/bin/env bash
set -euo pipefail

# Script description
# Usage: ./script.sh [options]

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

die() {
    log_error "$*"
    exit 1
}

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Options:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output
    -d, --dry-run   Show what would be done

EOF
}

main() {
    local verbose=false
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    # Main logic here
    log_info "Starting $SCRIPT_NAME"
}

main "$@"
```

## Version Control Workflows (git + git worktrees)

Plain git with GitHub as the remote. One branch per change; parallel work gets
its own git worktree instead of branch-juggling in a single checkout.

### Feature Change
```bash
# Branch off the default branch
git checkout -b feat/my-feature

# Work — inspect as you go
git status
git diff

# Commit in small, focused steps
git add -p && git commit -m "feat: add feature description"

# Update from main
git fetch origin && git rebase origin/main

# Push and create PR
git push -u origin feat/my-feature
gh pr create --fill
```

### Parallel Work (git worktrees)
```bash
# One worktree per concurrent task — separate directory, separate branch
git worktree add ../myrepo-fix-login -b fix/login
cd ../myrepo-fix-login   # work here without disturbing the main checkout

git worktree list                        # see all worktrees
git worktree remove ../myrepo-fix-login  # clean up after merge
git branch -d fix/login
```

### Useful git Commands
```bash
# See all in-flight branches (yours and other agents')
git log --oneline --graph --all

# Show what changed on a specific branch
git diff main...<branch>

# Park uncommitted work / pick it back up
git stash
git stash pop

# The recovery tool when something goes wrong
git reflog
```

## Podman/Docker
```bash
podman build -t myapp:latest .
podman run -d --name myapp -p 8080:8080 myapp:latest
podman-compose up -d
podman system prune -af
```
Rootless Podman is the default container runtime here; reach for Docker only
when a tool specifically requires it.

## Script Rules
- Always use `set -euo pipefail` in scripts
- Quote variables: `"$var"` not `$var`
- Resolve paths from `BASH_SOURCE`, never `$0` (breaks after a `cd`)
- Use `shellcheck` for linting; `[[` over `[` for conditionals; `readonly` for constants
- Handle signals with `trap`; no `sed -i` (GNU/BSD differ) — filter to a temp file and `mv` it back

## Querying structured data
Prefer a real parser over `grep`/`awk` when the input is structured:
- **jq** — JSON: `curl -s api | jq '.items[].id'`
- **dasel** — JSON / YAML / TOML / XML / CSV with one syntax:
  `dasel select -f config.toml '.server.port'`, or convert formats with
  `dasel put`/`read`/`write`. Use it to read or edit `pyproject.toml`,
  `config.toml`, `package.json` uniformly in scripts.

## Working with Other Agents

Persona names describe their scope — hand work outside yours to the matching
persona. Most useful from here: cicd (CI/CD scripts), python (deployment
scripts).

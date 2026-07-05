#!/usr/bin/env bash
#
# Top-level orchestrator for macols-configs.
#
# Installs the agentic CLIs and their configuration. By default it configures
# all four tools (Claude Code, Codex, OpenCode, Oh My Pi — tool keyword `pi`);
# pass tool names to scope it. Each per-tool installer is self-contained (it
# ensures Homebrew + the CLI binary + jj, then installs configs from the single
# sources of truth under shared/).
#
# Examples:
#   ./install.sh                 # all four tools
#   ./install.sh claudecode pi   # just Claude Code and Pi
#   ./install.sh --env           # run the Terminal dev-environment setup first
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat << EOF
Usage: $0 [--env] [TOOL ...]

TOOL is one or more of: claudecode codex opencode pi  (default: all four).
(`pi` installs Oh My Pi — the `omp` binary.)

Options:
    -h, --help    Show this help message
    --env         Run the Terminal dev-environment setup first
                  (Homebrew/apt, Python, Node, Podman, etc.) for this OS
EOF
}

RUN_ENV=false
TOOLS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --env) RUN_ENV=true ;;
        claudecode|codex|opencode|pi) TOOLS+=("$1") ;;
        *) printf "${RED}Unknown argument: %s${NC}\n" "$1"; usage; exit 1 ;;
    esac
    shift
done
[ ${#TOOLS[@]} -eq 0 ] && TOOLS=(claudecode codex opencode pi)

banner "macols-configs Installer"

if [ "$RUN_ENV" = true ]; then
    case "$(detect_os)" in
        macos) printf "${BLUE}Running Terminal/install_macos.sh...${NC}\n"; "$SCRIPT_DIR/Terminal/install_macos.sh" ;;
        linux) printf "${BLUE}Running Terminal/install_ubuntu26.sh...${NC}\n"; "$SCRIPT_DIR/Terminal/install_ubuntu26.sh" ;;
        *) printf "${YELLOW}Unknown OS — skipping Terminal env setup${NC}\n" ;;
    esac
    echo ""
fi

for tool in "${TOOLS[@]}"; do
    printf "${CYAN}=== Installing %s ===${NC}\n" "$tool"
    "$SCRIPT_DIR/install_${tool}.sh"
    echo ""
done

done_banner
echo "Configured tools: ${TOOLS[*]}"
echo ""

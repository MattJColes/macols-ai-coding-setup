#!/usr/bin/env bash
#
# Top-level orchestrator for macols-ai-coding-setup.
#
# Installs the agentic CLIs and their configuration. By default it configures
# all five tools (Claude Code, Codex, OpenCode, Oh My Pi — tool keyword `pi`,
# which also installs the plain `pi` agent — and ZCode); pass tool names to
# scope it. Each per-tool installer is self-contained (it ensures Homebrew +
# the CLI binary, then installs configs from the single sources of truth
# under shared/).
#
# Examples:
#   ./install.sh                 # all five tools
#   ./install.sh claudecode pi   # just Claude Code and the Pi agents
#   ./install.sh --env           # run the machine setup first
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat << 'EOF'
Usage: ./install.sh [--env] [TOOL ...]

TOOL is one or more of: claudecode codex opencode pi zcode  (default: all five).
(`pi` installs both Pi agents — plain `pi` and Oh My Pi (`omp`). `zcode`
installs ZCode's configs; the app itself is a desktop install.)

Options:
    -h, --help    Show this help message
    --env         Run the machine setup first
                  (Homebrew/apt, Python, Node, Podman, etc.) for this OS

Examples:
    ./install.sh                     Install and configure all five tools
    ./install.sh codex               Install and configure only Codex
    ./install.sh claudecode pi       Install Claude Code and the Pi agents
    ./install.sh --env               Set up the workstation and all five tools

To install selected components instead of a tool's full setup, call its
installer directly. For example:
    ./install_codex.sh --skills-only --no-cli
    ./install_claudecode.sh --mcps-only --hooks-only --no-cli

Run ./install_<tool>.sh --help for that tool's complete option list.
EOF
}

RUN_ENV=false
TOOLS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --env) RUN_ENV=true ;;
        claudecode|codex|opencode|pi|zcode) TOOLS+=("$1") ;;
        *) printf "${RED}Unknown argument: %s${NC}\n" "$1"; usage; exit 1 ;;
    esac
    shift
done
[ ${#TOOLS[@]} -eq 0 ] && TOOLS=(claudecode codex opencode pi zcode)

banner "macols-ai-coding-setup Installer"

if [ "$RUN_ENV" = true ]; then
    case "$(detect_os)" in
        macos) printf "${BLUE}Running machine-setup/install_macos.sh...${NC}\n"; "$SCRIPT_DIR/machine-setup/install_macos.sh" ;;
        linux) printf "${BLUE}Running machine-setup/install_ubuntu26.sh...${NC}\n"; "$SCRIPT_DIR/machine-setup/install_ubuntu26.sh" ;;
        *) printf "${YELLOW}Unknown OS — skipping machine setup${NC}\n" ;;
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

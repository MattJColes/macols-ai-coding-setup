#!/usr/bin/env bash
#
# The single entry point for macols-ai-coding-setup.
#
# Installs the agentic CLIs and their configuration. By default it configures
# all five tools (Claude Code, Codex, OpenCode, the Pi agents — tool keyword
# `pi`, which installs both plain `pi` and Oh My Pi — and ZCode); pass tool
# names to scope it. Any other option is passed through to each selected
# tool's installer in installers/<tool>.sh, which ensures the CLI and then
# installs configs from config/ and hooks/.
#
# Examples:
#   ./install.sh                          # all five tools
#   ./install.sh claudecode pi            # just Claude Code and the Pi agents
#   ./install.sh codex --skills-only      # one component of one tool
#   ./install.sh --machine                # workstation setup first, then all tools
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

TOOL_NAMES=(claudecode codex opencode pi zcode)

usage() {
    cat << 'EOF'
Usage: ./install.sh [--machine] [TOOL ...] [TOOL OPTIONS ...]

TOOL is one or more of: claudecode codex opencode pi zcode  (default: all five).
(`pi` installs both Pi agents — plain `pi` and Oh My Pi (`omp`). `zcode`
installs ZCode's configs; the app itself is a desktop install.)

Options:
    -h, --help    Show this help; with a TOOL, show that tool's options
    --machine     Run the workstation setup in machine/ first
                  (Homebrew, languages, terminal and editor). Alias: --env
    --aws-mcp     Also register the AWS MCP servers for every tool
                  (remembered; or MACOLS_AWS_MCP=1). Off unless asked.
    --no-aws-mcp  Remove the AWS MCP servers and stop asking

Every other option is passed to each selected tool's installer, e.g.
--no-cli, --skills-only, --mcps-only, --hooks-only, --project.

Examples:
    ./install.sh                                  Install and configure all five tools
    ./install.sh codex                            Only Codex
    ./install.sh claudecode pi                    Claude Code and the Pi agents
    ./install.sh codex --skills-only --no-cli     Codex skills only, keep the CLI
    ./install.sh claudecode --help                Claude Code's full option list
    ./install.sh --machine                        Set up the workstation, then all tools
EOF
}

RUN_MACHINE=false
SHOW_HELP=false
TOOLS=()
PASSTHROUGH=()
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) SHOW_HELP=true ;;
        --aws-mcp)    export MACOLS_AWS_MCP=1 ;;
        --no-aws-mcp) export MACOLS_AWS_MCP=0 ;;
        --machine|--env) RUN_MACHINE=true ;;
        claudecode|codex|opencode|pi|zcode) TOOLS+=("$1") ;;
        -*) PASSTHROUGH+=("$1") ;;
        *)
            # A value for the previous passthrough option (e.g. --tool-arg value).
            if [ ${#PASSTHROUGH[@]} -gt 0 ]; then
                PASSTHROUGH+=("$1")
            else
                printf "${RED}Unknown argument: %s${NC}\n" "$1"; usage; exit 1
            fi ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    if [ ${#TOOLS[@]} -eq 1 ]; then
        "$SCRIPT_DIR/installers/${TOOLS[0]}.sh" --help
    else
        usage
    fi
    exit 0
fi
[ ${#TOOLS[@]} -eq 0 ] && TOOLS=("${TOOL_NAMES[@]}")

banner "macols-ai-coding-setup Installer"

if [ "$RUN_MACHINE" = true ]; then
    case "$(detect_os)" in
        macos) printf "${BLUE}Running machine/install_macos.sh...${NC}\n"; MACOLS_FROM_INSTALL=1 "$SCRIPT_DIR/machine/install_macos.sh" ;;
        linux) printf "${BLUE}Running machine/install_ubuntu26.sh...${NC}\n"; MACOLS_FROM_INSTALL=1 "$SCRIPT_DIR/machine/install_ubuntu26.sh" ;;
        *) printf "${YELLOW}Unknown OS — skipping machine setup${NC}\n" ;;
    esac
    echo ""
fi

for tool in "${TOOLS[@]}"; do
    printf "${CYAN}=== Installing %s ===${NC}\n" "$tool"
    "$SCRIPT_DIR/installers/${tool}.sh" ${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"}
    echo ""
done

done_banner
echo "Configured tools: ${TOOLS[*]}"
echo ""
reload_shell_if_needed

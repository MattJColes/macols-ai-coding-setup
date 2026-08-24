#!/usr/bin/env bash
#
# Self-contained installer for ZCode (Z.ai's GLM coding harness).
#
# ZCode is a desktop app, not a package-managed CLI: the installer verifies
# the app is present (a non-fatal warning when it isn't — nothing is
# downloaded) and writes its configuration — Agent Skills, slash commands,
# the system AGENTS.md, MCP servers and lifecycle hooks — from the single
# sources of truth under shared/. ZCode has no user-defined subagents, so
# personas render as skills and slash commands only.
#
# ZCode reads user-scope config from ~/.zcode: skills in ~/.zcode/skills,
# slash commands in ~/.zcode/commands, instructions in ~/.zcode/AGENTS.md,
# and MCP servers + hooks in ~/.zcode/cli/config.json.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ZCODE_DIR="$HOME/.zcode"
SKILLS_DIR="$ZCODE_DIR/skills"
COMMANDS_DIR="$ZCODE_DIR/commands"
AGENTS_FILE="$ZCODE_DIR/AGENTS.md"
CONFIG_JSON="$ZCODE_DIR/cli/config.json"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Installs Agent Skills, slash commands, the system AGENTS.md, MCP servers and
lifecycle hooks for ZCode from shared/ (and verifies the ZCode app is
installed unless --no-cli is given).

Options:
    -h, --help          Show this help message
    --skills-only       Install only Agent Skills (~/.zcode/skills)
    --commands-only     Install only slash commands (~/.zcode/commands/*.md)
    --instructions-only Install only the system AGENTS.md
    --mcps-only         Install only MCP servers
    --hooks-only        Install only lifecycle hooks
    --no-cli            Skip the ZCode app check
    -p, --project       Install skills/commands to ./.zcode and AGENTS.md to ./AGENTS.md (implies --no-cli)
    --list              List available personas and exit
EOF
}

install_skills() {
    local target="$1"
    [ -d "$PERSONAS_DIR" ] || { printf "${RED}personas dir not found: %s${NC}\n" "$PERSONAS_DIR"; return 1; }
    [ -d "$target" ] && { printf "${YELLOW}Clearing existing skills in: %s${NC}\n" "$target"; rm -rf "$target"; }
    mkdir -p "$target"
    printf "${BLUE}Installing skills to: %s${NC}\n" "$target"
    generate_personas zcode skill "$target" || return 1
    printf "${GREEN}✓ Installed %s skills${NC}\n" "$PERSONA_COUNT"
}

install_commands() {
    local target="$1"
    [ -d "$PERSONAS_DIR" ] || { printf "${RED}personas dir not found: %s${NC}\n" "$PERSONAS_DIR"; return 1; }
    [ -d "$target" ] && { printf "${YELLOW}Clearing existing commands in: %s${NC}\n" "$target"; rm -rf "$target"; }
    mkdir -p "$target"
    printf "${BLUE}Installing commands to: %s${NC}\n" "$target"
    generate_personas zcode command "$target" || return 1
    printf "${GREEN}✓ Installed %s commands${NC}\n" "$PERSONA_COUNT"
}

DO_SKILLS=true; DO_COMMANDS=true; DO_INSTRUCTIONS=true; DO_MCPS=true; DO_HOOKS=true
DO_CLI=true; PROJECT_INSTALL=false; SUBSET=false
set_subset() { if [ "$SUBSET" = false ]; then DO_SKILLS=false; DO_COMMANDS=false; DO_INSTRUCTIONS=false; DO_MCPS=false; DO_HOOKS=false; SUBSET=true; fi; }

while [ $# -gt 0 ]; do
    handle_common_install_flag "$1" && { shift; continue; }
    case "$1" in
        --list) list_personas zcode; exit 0 ;;
        --skills-only)       set_subset; DO_SKILLS=true ;;
        --commands-only)     set_subset; DO_COMMANDS=true ;;
        --instructions-only) set_subset; DO_INSTRUCTIONS=true ;;
        --mcps-only)         set_subset; DO_MCPS=true ;;
        --hooks-only)        set_subset; DO_HOOKS=true ;;
        *) printf "${RED}Unknown option: %s${NC}\n" "$1"; usage; exit 1 ;;
    esac
    shift
done

banner "ZCode Installer"

if [ "$DO_CLI" = true ]; then
    ensure_brew; ensure_cli zcode
    ensure_openspec || printf "${YELLOW}⚠ openspec install skipped/failed${NC}\n"
    ensure_ast_grep || printf "${YELLOW}⚠ ast-grep install skipped/failed${NC}\n"
    ensure_yq || printf "${YELLOW}⚠ yq install skipped/failed${NC}\n"
    ensure_node_on_noninteractive_path || printf "${YELLOW}⚠ node PATH linking skipped/failed${NC}\n"
    echo ""
fi
if [ "$DO_SKILLS" = true ]; then
    if [ "$PROJECT_INSTALL" = true ]; then install_skills "./.zcode/skills"; else install_skills "$SKILLS_DIR"; fi; echo ""
fi
if [ "$DO_COMMANDS" = true ]; then
    if [ "$PROJECT_INSTALL" = true ]; then install_commands "./.zcode/commands"; else install_commands "$COMMANDS_DIR"; fi; echo ""
fi
if [ "$DO_INSTRUCTIONS" = true ]; then
    if [ "$PROJECT_INSTALL" = true ]; then
        assemble_steering zcode "./AGENTS.md"; append_ponytail_ruleset "./AGENTS.md"
    else
        assemble_steering zcode "$AGENTS_FILE"; append_ponytail_ruleset "$AGENTS_FILE"
    fi; echo ""
fi
if [ "$DO_MCPS" = true ] && [ "$PROJECT_INSTALL" = false ]; then register_mcps_zcode || printf "${YELLOW}⚠ MCP registration skipped/failed${NC}\n"; echo ""; fi
if [ "$DO_HOOKS" = true ] && [ "$PROJECT_INSTALL" = false ]; then
    write_zcode_hooks "$CONFIG_JSON"
    echo ""
fi

done_banner
echo "Next steps:"
echo "  • Restart ZCode to load the new configuration"
echo "  • Skills load automatically when their description matches the work"
echo "  • Commands are available as slash commands (e.g. /development-build-python-backends, /quality-review-code)"
echo "  • MCP servers and hooks live in $CONFIG_JSON (aws-* MCPs need ~/.aws/credentials)"
echo ""

#!/usr/bin/env bash
#
# Self-contained installer for OpenCode.
#
# Ensures Homebrew + the `opencode` CLI, then installs agents, skills, the
# system AGENTS.md, MCP servers (into opencode.json) and the post-code plugin —
# all from the single sources of truth under shared/. With no options it
# installs everything. (LM Studio / GLM setup lives in Terminal/configure_lmstudio.sh.)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

CONFIG_DIR="$HOME/.config/opencode"
AGENTS_DIR="$CONFIG_DIR/agents"
SKILLS_DIR="$CONFIG_DIR/skills"
PLUGINS_DIR="$CONFIG_DIR/plugins"
AGENTS_MD="$CONFIG_DIR/AGENTS.md"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Installs (and, unless told otherwise, the OpenCode CLI itself) agents, skills,
the system AGENTS.md, MCP servers and the post-code plugin from shared/.

Options:
    -h, --help        Show this help message
    --agents-only     Install only agents (and system AGENTS.md)
    --skills-only     Install only skills
    --mcps-only       Install only MCP servers
    --hooks-only      Install only the post-code plugin
    --no-cli          Skip installing Homebrew / the opencode CLI
    -p, --project     Install agents & skills to ./.opencode (implies --no-cli)
    --list            List available personas and exit
EOF
}

install_agents() {
    local target="$1"
    [ -d "$PERSONAS_DIR" ] || { printf "${RED}personas dir not found: %s${NC}\n" "$PERSONAS_DIR"; return 1; }
    [ -d "$target" ] && { printf "${YELLOW}Clearing existing agents in: %s${NC}\n" "$target"; rm -rf "$target"; }
    mkdir -p "$target"
    printf "${BLUE}Installing agents to: %s${NC}\n" "$target"
    generate_personas opencode agent "$target" || return 1
    printf "${GREEN}✓ Installed %s agents${NC}\n" "$PERSONA_COUNT"
    if [ "$target" = "$AGENTS_DIR" ]; then assemble_steering opencode "$AGENTS_MD"; append_ponytail_ruleset "$AGENTS_MD"; fi
}

install_skills() {
    local target="$1"
    [ -d "$target" ] && { printf "${YELLOW}Clearing existing skills in: %s${NC}\n" "$target"; rm -rf "$target"; }
    mkdir -p "$target"
    printf "${BLUE}Installing skills to: %s${NC}\n" "$target"
    generate_personas opencode skill "$target" || return 1
    printf "${GREEN}✓ Installed %s skills${NC}\n" "$PERSONA_COUNT"
}

DO_AGENTS=true; DO_SKILLS=true; DO_MCPS=true; DO_HOOKS=true
DO_CLI=true; PROJECT_INSTALL=false; SUBSET=false
set_subset() { if [ "$SUBSET" = false ]; then DO_AGENTS=false; DO_SKILLS=false; DO_MCPS=false; DO_HOOKS=false; SUBSET=true; fi; }

while [ $# -gt 0 ]; do
    handle_common_install_flag "$1" && { shift; continue; }
    case "$1" in
        --list) list_personas opencode; exit 0 ;;
        --agents-only) set_subset; DO_AGENTS=true ;;
        --skills-only) set_subset; DO_SKILLS=true ;;
        --mcps-only)   set_subset; DO_MCPS=true ;;
        --hooks-only)  set_subset; DO_HOOKS=true ;;
        *) printf "${RED}Unknown option: %s${NC}\n" "$1"; usage; exit 1 ;;
    esac
    shift
done

banner "OpenCode Installer"

if [ "$DO_CLI" = true ]; then
    ensure_brew; ensure_cli opencode
    ensure_openspec || printf "${YELLOW}⚠ openspec install skipped/failed${NC}\n"
    ensure_ast_grep || printf "${YELLOW}⚠ ast-grep install skipped/failed${NC}\n"
    ensure_yq || printf "${YELLOW}⚠ yq install skipped/failed${NC}\n"
    ensure_node_on_noninteractive_path || printf "${YELLOW}⚠ node PATH linking skipped/failed${NC}\n"
    echo ""
fi
if [ "$DO_AGENTS" = true ]; then
    if [ "$PROJECT_INSTALL" = true ]; then install_agents "./.opencode/agents"; else install_agents "$AGENTS_DIR"; fi; echo ""
fi
if [ "$DO_SKILLS" = true ]; then
    if [ "$PROJECT_INSTALL" = true ]; then install_skills "./.opencode/skills"; else install_skills "$SKILLS_DIR"; fi; echo ""
fi
if [ "$DO_MCPS" = true ] && [ "$PROJECT_INSTALL" = false ]; then register_mcps_opencode || printf "${YELLOW}⚠ MCP write skipped/failed${NC}\n"; echo ""; fi
if [ "$DO_HOOKS" = true ] && [ "$PROJECT_INSTALL" = false ]; then
    install_opencode_plugin "$PLUGINS_DIR"
    # The plugin's session.idle runs the advisory lgtmaybe review; install the
    # CLI and ask (interactively) which provider/model to use. Never blocking.
    { ensure_lgtmaybe && configure_lgtmaybe; } || printf "${YELLOW}⚠ lgtmaybe install/config skipped — advisory review disabled until installed${NC}\n"
    echo ""
fi

done_banner
echo "Next steps:"
echo "  • Restart OpenCode to load agents, skills, MCPs and the plugin"
echo "  • Skills load on-demand via the skill tool; agents via the Task tool"
[ "$DO_MCPS" = true ] && echo "  • Ensure AWS credentials are configured (~/.aws/credentials)"
echo "  • Run Terminal/configure_lmstudio.sh to set up a local model via LM Studio"
echo ""

#!/usr/bin/env bash
#
# Self-contained installer for the OpenAI Codex CLI.
#
# Ensures Homebrew + the `codex` CLI, then installs custom prompts (slash
# commands), the system AGENTS.md, MCP servers and lifecycle hooks — all from
# the single sources of truth under shared/. With no options it installs
# everything.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

CODEX_DIR="$HOME/.codex"
PROMPTS_DIR="$CODEX_DIR/prompts"
AGENTS_FILE="$CODEX_DIR/AGENTS.md"
HOOKS_JSON="$CODEX_DIR/hooks.json"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Installs (and, unless told otherwise, the Codex CLI itself) custom prompts,
the system AGENTS.md, MCP servers and lifecycle hooks from shared/.

Options:
    -h, --help          Show this help message
    --prompts-only      Install only custom prompts (slash commands)
    --instructions-only Install only the system AGENTS.md
    --mcps-only         Install only MCP servers
    --hooks-only        Install only lifecycle hooks
    --no-cli            Skip installing Homebrew / the codex CLI
    -p, --project       Install prompts to ./.codex/prompts and AGENTS.md to ./AGENTS.md (implies --no-cli)
    --list              List available personas and exit
EOF
}

install_prompts() {
    local target="$1"
    [ -d "$PERSONAS_DIR" ] || { printf "${RED}personas dir not found: %s${NC}\n" "$PERSONAS_DIR"; return 1; }
    [ -d "$target" ] && { printf "${YELLOW}Clearing existing prompts in: %s${NC}\n" "$target"; rm -rf "$target"; }
    mkdir -p "$target"
    printf "${BLUE}Installing prompts to: %s${NC}\n" "$target"
    generate_personas codex skill "$target" || return 1
    printf "${GREEN}✓ Installed %s prompts${NC}\n" "$PERSONA_COUNT"
}

DO_PROMPTS=true; DO_INSTRUCTIONS=true; DO_MCPS=true; DO_HOOKS=true
DO_CLI=true; PROJECT_INSTALL=false; SUBSET=false
set_subset() { if [ "$SUBSET" = false ]; then DO_PROMPTS=false; DO_INSTRUCTIONS=false; DO_MCPS=false; DO_HOOKS=false; SUBSET=true; fi; }

while [ $# -gt 0 ]; do
    handle_common_install_flag "$1" && { shift; continue; }
    case "$1" in
        --list) list_personas codex; exit 0 ;;
        --prompts-only)      set_subset; DO_PROMPTS=true ;;
        --instructions-only) set_subset; DO_INSTRUCTIONS=true ;;
        --mcps-only)         set_subset; DO_MCPS=true ;;
        --hooks-only)        set_subset; DO_HOOKS=true ;;
        *) printf "${RED}Unknown option: %s${NC}\n" "$1"; usage; exit 1 ;;
    esac
    shift
done

banner "Codex CLI Installer"

if [ "$DO_CLI" = true ]; then
    ensure_brew; ensure_cli codex
    ensure_openspec || printf "${YELLOW}⚠ openspec install skipped/failed${NC}\n"
    ensure_ast_grep || printf "${YELLOW}⚠ ast-grep install skipped/failed${NC}\n"
    ensure_node_on_noninteractive_path || printf "${YELLOW}⚠ node PATH linking skipped/failed${NC}\n"
    echo ""
fi
if [ "$DO_PROMPTS" = true ]; then
    if [ "$PROJECT_INSTALL" = true ]; then install_prompts "./.codex/prompts"; else install_prompts "$PROMPTS_DIR"; fi; echo ""
fi
if [ "$DO_INSTRUCTIONS" = true ]; then
    if [ "$PROJECT_INSTALL" = true ]; then
        assemble_steering codex "./AGENTS.md"; append_ponytail_ruleset "./AGENTS.md"
    else
        assemble_steering codex "$AGENTS_FILE"; append_ponytail_ruleset "$AGENTS_FILE"
    fi; echo ""
fi
if [ "$DO_MCPS" = true ] && [ "$PROJECT_INSTALL" = false ]; then register_mcps_codex || printf "${YELLOW}⚠ MCP registration skipped/failed${NC}\n"; echo ""; fi
if [ "$DO_HOOKS" = true ] && [ "$PROJECT_INSTALL" = false ]; then write_codex_hooks "$HOOKS_JSON"; echo ""; fi

done_banner
echo "Next steps:"
echo "  • Restart Codex to load the new configuration"
echo "  • Prompts are available as slash commands (e.g. /python-backend, /code-reviewer)"
echo "  • Run 'codex mcp list' to inspect registered MCP servers"
[ "$DO_MCPS" = true ] && echo "  • Configure AWS credentials (~/.aws/credentials) for the aws-* MCPs"
echo ""

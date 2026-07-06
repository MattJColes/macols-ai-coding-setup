#!/usr/bin/env bash
#
# Self-contained installer for the Oh My Pi coding agent (@oh-my-pi/pi-coding-agent).
#
# Oh My Pi (`omp`) replaces the plain Pi agent — the tool keyword and this
# file's name stay `pi` so existing invocations keep working. Ensures the
# `omp` CLI, then installs Agent Skills, the system AGENTS.md, the pi-checks
# extension and omp's pluggable packages — all from the single sources of
# truth under shared/.
#
# omp differs from the other CLIs: skills are invoked as /skill:<name>, hooks
# are TypeScript extensions (not a settings hook array), and there is NO MCP —
# omp exposes external capabilities through CLI tools, Agent Skills and packages.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# omp keeps pi's PI_CODING_AGENT_DIR override but defaults to ~/.omp/agent.
PI_DIR="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}"
SKILLS_DIR="$PI_DIR/skills"
EXTENSIONS_DIR="$PI_DIR/extensions"
AGENTS_FILE="$PI_DIR/AGENTS.md"

# omp packages, installed via `omp install <source>`. The npm-published ones
# need the explicit `npm:` source prefix — a bare name (e.g. `omp install
# pi-agent-web-access`) is treated as a local filesystem PATH and fails with
# "Path does not exist". Git-hosted packages use the `git:` prefix.
#
# The other legacy pi packages (context-mode, pi-subagents, pi-ask-user,
# pi-markdown-preview, pi-btw) fail omp's extension validation — omp ships
# those capabilities natively (bundled task agents, ask-user, markdown
# rendering, context management) — so they are deliberately not installed.
#
# pi-agent-web-access is also deliberately skipped: it deep-imports linkedom's
# internal canvas.cjs, which assigns module.exports inside a try/catch. omp's
# Bun loader detects default exports via static analysis (cjs-module-lexer),
# which ignores try blocks, so it reports "Missing 'default' export" and the
# install rolls back — it never installs. Re-add if fixed upstream.
#   • ponytail             — lazy/YAGNI mode extension (github.com/DietrichGebert/ponytail;
#                            also published as npm:@dietrichgebert/ponytail if git fetch is blocked)
OMP_PACKAGES="git:github.com/$PONYTAIL_REPO"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Installs (and, unless told otherwise, the omp CLI itself) Agent Skills, the
system AGENTS.md, the pi-checks extension and omp packages from shared/.

Options:
    -h, --help        Show this help message
    --skills-only     Install only Agent Skills (/skill:<name>)
    --context-only    Install only the system AGENTS.md
    --hooks-only      Install only the pi-checks extension
    --packages-only   Install only the omp packages
    --mcps-only       (omp has no MCP — prints guidance and exits)
    --no-pi           Skip installing/upgrading the omp binary
    --no-packages     Skip installing omp packages
    -p, --project     Install skills to ./.omp/skills and AGENTS.md to ./AGENTS.md (implies --no-pi)
    --list            List available personas and exit
EOF
}

install_skills() {
    local target="$1"
    [ -d "$PERSONAS_DIR" ] || { printf "${RED}personas dir not found: %s${NC}\n" "$PERSONAS_DIR"; return 1; }
    [ -d "$target" ] && { printf "${YELLOW}Clearing existing skills in: %s${NC}\n" "$target"; rm -rf "$target"; }
    mkdir -p "$target"
    printf "${BLUE}Installing skills to: %s${NC}\n" "$target"
    generate_personas pi skill "$target" || return 1
    printf "${GREEN}✓ Installed %s skills${NC}\n" "$PERSONA_COUNT"
}

install_packages() {
    command -v omp &> /dev/null || { printf "${RED}omp not found — install omp first (drop --no-pi)${NC}\n"; return 1; }
    printf "${BLUE}Installing omp packages...${NC}\n"
    local pkg
    for pkg in $OMP_PACKAGES; do
        printf "${BLUE}  → omp install %s${NC}\n" "$pkg"
        if omp install "$pkg"; then printf "${GREEN}  ✓ %s${NC}\n" "$pkg"; else printf "${YELLOW}  ⚠ Failed to install %s (continuing)${NC}\n" "$pkg"; fi
    done
}

print_mcp_guidance() {
    printf "${YELLOW}omp has no built-in MCP support.${NC}\n"
    cat << EOF
omp deliberately omits MCP — it exposes capabilities as CLI tools (with READMEs)
and Agent Skills instead. To give omp an external capability, install a CLI tool
and document it, add a skill under $SKILLS_DIR, or install a package via
'omp install <pkg>'. Nothing to register here.
EOF
}

DO_SKILLS=true; DO_CONTEXT=true; DO_HOOKS=true; DO_PI=true; DO_PACKAGES=true
PROJECT_INSTALL=false; SUBSET=false
set_subset() { if [ "$SUBSET" = false ]; then DO_SKILLS=false; DO_CONTEXT=false; DO_HOOKS=false; DO_PI=false; DO_PACKAGES=false; SUBSET=true; fi; }

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --list) list_personas pi; exit 0 ;;
        --skills-only)   set_subset; DO_SKILLS=true ;;
        --context-only)  set_subset; DO_CONTEXT=true ;;
        --hooks-only)    set_subset; DO_HOOKS=true ;;
        --packages-only) set_subset; DO_PACKAGES=true ;;
        --mcps-only)     print_mcp_guidance; exit 0 ;;
        --no-pi)         DO_PI=false ;;
        --no-packages)   DO_PACKAGES=false ;;
        -p|--project)    PROJECT_INSTALL=true; DO_PI=false ;;
        *) printf "${RED}Unknown option: %s${NC}\n" "$1"; usage; exit 1 ;;
    esac
    shift
done

banner "Oh My Pi Coding Agent Installer"

if [ "$DO_PI" = true ] && [ "$PROJECT_INSTALL" = false ]; then
    ensure_cli pi
    ensure_openspec || printf "${YELLOW}⚠ openspec install skipped/failed${NC}\n"
    ensure_ast_grep || printf "${YELLOW}⚠ ast-grep install skipped/failed${NC}\n"
    ensure_node_on_noninteractive_path || printf "${YELLOW}⚠ node PATH linking skipped/failed${NC}\n"
    echo ""
fi
if [ "$DO_PACKAGES" = true ] && [ "$PROJECT_INSTALL" = false ]; then install_packages; echo ""; fi
if [ "$DO_SKILLS" = true ]; then
    if [ "$PROJECT_INSTALL" = true ]; then install_skills "./.omp/skills"; else install_skills "$SKILLS_DIR"; fi; echo ""
fi
if [ "$DO_CONTEXT" = true ]; then
    if [ "$PROJECT_INSTALL" = true ]; then
        assemble_steering pi "./AGENTS.md"; append_ponytail_ruleset "./AGENTS.md"
    else
        assemble_steering pi "$AGENTS_FILE"; append_ponytail_ruleset "$AGENTS_FILE"
    fi; echo ""
fi
if [ "$DO_HOOKS" = true ] && [ "$PROJECT_INSTALL" = false ]; then install_pi_extension "$EXTENSIONS_DIR"; echo ""; fi

done_banner
echo "Next steps:"
echo "  • Run 'omp' to start the agent (or '/reload' inside omp to pick up the extension)"
echo "  • Skills are available as /skill:<name> (e.g. /skill:python-backend)"
echo "  • The pi-checks extension runs tests/lint/security advisories after edits and turns"
echo "  • omp has no MCP — expose external capabilities as CLI tools + skills + packages"
echo ""

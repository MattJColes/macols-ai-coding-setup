#!/usr/bin/env bash
#
# Self-contained installer for the Pi coding agents: the plain `pi` CLI
# (@earendil-works/pi-coding-agent) and Oh My Pi `omp`
# (@oh-my-pi/pi-coding-agent). The tool keyword and this file's name stay
# `pi` so existing invocations keep working.
#
# The two agents share no config directories — `pi` reads ~/.pi/agent and
# `omp` reads ~/.omp/agent — so every shared resource is provisioned twice:
# Agent Skills, the system AGENTS.md and the pi-checks extension land in both
# agent dirs. MCP servers are omp-only (plain pi has no MCP support) and are
# written to ~/.omp/agent/mcp.json. Packages are installed per agent through
# each binary's own installer.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# PI_CODING_AGENT_DIR still overrides the omp agent dir for back-compat. Note
# that an exported PI_CODING_AGENT_DIR also redirects the `pi` binary itself
# at runtime; this script applies it to the omp side only.
PI_AGENT_DIR="$HOME/.pi/agent"
OMP_DIR="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}"

# Packages per agent. omp installs with `omp install <source>` (an alias of
# `omp plugin install`): bare names resolve as npm packages and git-hosted
# packages use the `github:user/repo` form (the old pi-style
# `git:github.com/...` prefix is no longer accepted). pi installs with
# `pi install <source>` using explicit `npm:`/`git:github.com/user/repo`
# sources.
#
# pi-subagents is installed for plain pi because the steering delegates
# parallel/chained work to it — omp bundles that capability natively. The
# other legacy pi packages (context-mode, pi-ask-user, pi-markdown-preview,
# pi-btw) are skipped: omp ships those capabilities natively and plain pi
# does not need them to follow this repo's steering.
#
# pi-agent-web-access is also deliberately skipped: it deep-imports linkedom's
# internal canvas.cjs, which assigns module.exports inside a try/catch. omp's
# Bun loader detects default exports via static analysis (cjs-module-lexer),
# which ignores try blocks, so it reports "Missing 'default' export" and the
# install rolls back — it never installs. Re-add if fixed upstream.
#   • ponytail — lazy/YAGNI mode extension (github.com/DietrichGebert/ponytail)
PI_PACKAGES="npm:pi-subagents git:github.com/$PONYTAIL_REPO"
OMP_PACKAGES="github:$PONYTAIL_REPO"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Installs (and, unless told otherwise, both agent binaries) Agent Skills, the
system AGENTS.md, MCP servers (omp only), omp's default/planning models, the
pi-checks extension and each agent's packages from shared/. Registering MCP
servers also asks for a Brave Search API key (blank to skip); set
BRAVE_API_KEY in the environment to supply it non-interactively.

Model setup asks which model omp starts on (the 'default' role) and which it
plans with (the 'plan' role) — either a provider omp already knows (Claude,
GPT, GLM, Gemini, ...) or an OpenAI-compatible endpoint of your own (vLLM,
Ollama, LM Studio, LiteLLM). It only asks once; --models-only re-asks. To
configure it without questions, set OMP_DEFAULT_MODEL / OMP_PLAN_MODEL to
'<provider>/<model-id>' selectors and, for a custom endpoint,
OMP_MODELS_CONFIG to a models.yml-shaped file of providers.

Options:
    -h, --help        Show this help message
    --skills-only     Install only Agent Skills (/skill:<name>, both agents)
    --context-only    Install only the system AGENTS.md (both agents)
    --hooks-only      Install only the pi-checks extension (both agents)
    --packages-only   Install only the agent packages
    --mcps-only       Install only omp MCP servers (~/.omp/agent/mcp.json; asks for the Brave Search API key)
    --models-only     Only (re-)ask for omp's default and planning models
    --no-pi           Skip installing/upgrading the pi and omp binaries
    --no-packages     Skip installing agent packages
    --no-models       Skip omp model setup
    -p, --project     Install skills to ./.pi/skills and ./.omp/skills and AGENTS.md to ./AGENTS.md (implies --no-pi)
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
    local pkg
    if command -v pi &> /dev/null; then
        printf "${BLUE}Installing pi packages...${NC}\n"
        for pkg in $PI_PACKAGES; do
            printf "${BLUE}  → pi install %s${NC}\n" "$pkg"
            if pi install "$pkg"; then printf "${GREEN}  ✓ %s${NC}\n" "$pkg"; else printf "${YELLOW}  ⚠ Failed to install %s (continuing)${NC}\n" "$pkg"; fi
        done
    else
        printf "${YELLOW}⚠ pi not found — skipping pi packages (drop --no-pi)${NC}\n"
    fi
    if command -v omp &> /dev/null; then
        printf "${BLUE}Installing omp packages...${NC}\n"
        for pkg in $OMP_PACKAGES; do
            printf "${BLUE}  → omp install %s${NC}\n" "$pkg"
            if omp install "$pkg"; then printf "${GREEN}  ✓ %s${NC}\n" "$pkg"; else printf "${YELLOW}  ⚠ Failed to install %s (continuing)${NC}\n" "$pkg"; fi
        done
    else
        printf "${YELLOW}⚠ omp not found — skipping omp packages (drop --no-pi)${NC}\n"
    fi
}

DO_SKILLS=true; DO_CONTEXT=true; DO_HOOKS=true; DO_PI=true; DO_PACKAGES=true; DO_MCPS=true; DO_MODELS=true
PROJECT_INSTALL=false; SUBSET=false
set_subset() { if [ "$SUBSET" = false ]; then DO_SKILLS=false; DO_CONTEXT=false; DO_HOOKS=false; DO_PI=false; DO_PACKAGES=false; DO_MCPS=false; DO_MODELS=false; SUBSET=true; fi; }

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --list) list_personas pi; exit 0 ;;
        --skills-only)   set_subset; DO_SKILLS=true ;;
        --context-only)  set_subset; DO_CONTEXT=true ;;
        --hooks-only)    set_subset; DO_HOOKS=true ;;
        --packages-only) set_subset; DO_PACKAGES=true ;;
        --mcps-only)     set_subset; DO_MCPS=true ;;
        # An explicit --models-only is a request to change the models, so it
        # overrides the "already configured, do not re-ask" short-circuit.
        --models-only)   set_subset; DO_MODELS=true; OMP_RECONFIGURE_MODELS=true ;;
        --no-pi)         DO_PI=false ;;
        --no-packages)   DO_PACKAGES=false ;;
        --no-models)     DO_MODELS=false ;;
        -p|--project)    PROJECT_INSTALL=true; DO_PI=false ;;
        *) printf "${RED}Unknown option: %s${NC}\n" "$1"; usage; exit 1 ;;
    esac
    shift
done

banner "Pi Coding Agents Installer (pi + omp)"

if [ "$DO_PI" = true ] && [ "$PROJECT_INSTALL" = false ]; then
    ensure_cli pi   # installs both the `pi` and `omp` binaries
    ensure_openspec || printf "${YELLOW}⚠ openspec install skipped/failed${NC}\n"
    ensure_ast_grep || printf "${YELLOW}⚠ ast-grep install skipped/failed${NC}\n"
    ensure_yq || printf "${YELLOW}⚠ yq install skipped/failed${NC}\n"
    ensure_node_on_noninteractive_path || printf "${YELLOW}⚠ node PATH linking skipped/failed${NC}\n"
    echo ""
fi
if [ "$DO_PACKAGES" = true ] && [ "$PROJECT_INSTALL" = false ]; then install_packages; echo ""; fi
if [ "$DO_SKILLS" = true ]; then
    if [ "$PROJECT_INSTALL" = true ]; then
        install_skills "./.pi/skills"; install_skills "./.omp/skills"
    else
        install_skills "$PI_AGENT_DIR/skills"; install_skills "$OMP_DIR/skills"
    fi; echo ""
fi
if [ "$DO_CONTEXT" = true ]; then
    if [ "$PROJECT_INSTALL" = true ]; then
        assemble_steering pi "./AGENTS.md"; append_ponytail_ruleset "./AGENTS.md"
    else
        assemble_steering pi "$PI_AGENT_DIR/AGENTS.md"; append_ponytail_ruleset "$PI_AGENT_DIR/AGENTS.md"
        assemble_steering pi "$OMP_DIR/AGENTS.md"; append_ponytail_ruleset "$OMP_DIR/AGENTS.md"
    fi; echo ""
fi
if [ "$DO_MCPS" = true ] && [ "$PROJECT_INSTALL" = false ]; then
    # Plain pi has no MCP support — omp only, Brave Search included.
    ensure_brave_api_key || printf "${YELLOW}⚠ Brave Search not configured — brave-search MCP left out${NC}\n"
    register_mcps_pi "$OMP_DIR" || printf "${YELLOW}⚠ MCP registration skipped/failed${NC}\n"; echo ""
fi
if [ "$DO_MODELS" = true ] && [ "$PROJECT_INSTALL" = false ]; then
    # omp-only: plain pi has no provider/role config of its own.
    configure_omp_models "$OMP_DIR" || printf "${YELLOW}⚠ omp model setup skipped/failed${NC}\n"; echo ""
fi
if [ "$DO_HOOKS" = true ] && [ "$PROJECT_INSTALL" = false ]; then
    install_pi_extension "$PI_AGENT_DIR/extensions"
    install_pi_extension "$OMP_DIR/extensions"
    echo ""
fi

done_banner
echo "Next steps:"
echo "  • Run 'pi' or 'omp' to start either agent (or '/reload' inside either to pick up the extension)"
echo "  • Skills are available as /skill:<name> (e.g. /skill:python)"
echo "  • The pi-checks extension runs tests/lint/security advisories after edits and turns,"
echo "    and a cdk deploy/destroy confirmation guard"
echo "  • MCP servers are configured in $OMP_DIR/mcp.json (omp only; aws-* MCPs need ~/.aws/credentials)"
echo "  • omp providers live in $OMP_DIR/models.yml and model roles in $OMP_DIR/config.yml"
echo "      change them with './install_pi.sh --models-only', or from inside omp with /model"
if [ -s "$BRAVE_KEY_FILE" ]; then
    echo "  • omp web search runs through the brave-search MCP (key in $BRAVE_KEY_FILE); plain pi has no MCP support"
else
    echo "  • For omp web search, get a Brave key (https://brave.com/search/api/) then run:"
    echo "      BRAVE_API_KEY=<key> ./install_pi.sh --mcps-only"
fi
echo ""

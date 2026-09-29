#!/usr/bin/env bash
# shellcheck disable=SC2034  # layout/colour variables here are read by the lib/*.sh modules and installers
#
# Shared install library for the macols-ai-coding-setup installers.
#
# Sourced by install.sh and installers/<tool>.sh. Sets the colours, repo layout
# and pinned versions, then loads one module per job:
#   os.sh          OS detection, Homebrew/CLI bootstrap, prerequisite tools
#   personas.sh    persona rendering (config/personas)
#   steering.sh    steering assembly and the ponytail ruleset (config/steering)
#   mcp.sh         MCP registration and the Brave/AWS opt-ins (config/mcp)
#   omp-models.sh  Oh My Pi / pi model and provider setup
#   hooks.sh       hook wiring for every tool (hooks/)
#   plugins.sh     third-party agent plugins (Claude marketplace helper, revdiff)
#
# Not meant to be executed directly.

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Repo layout (single sources of truth) ────────────────────────────────────
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$LIB_DIR/.." && pwd)"
CONFIG_DIR="$REPO_ROOT/config"
PERSONAS_DIR="$CONFIG_DIR/personas"
STEERING_DIR="$CONFIG_DIR/steering"
# Shared response-format block: substituted into every tool's steering and
# appended to every rendered persona, so subagents get the same rules.
RESPONSE_FORMAT_FILE="$STEERING_DIR/response-format.md"
# Hooks run inside the agents and are referenced in place: entry scripts in
# hooks/, check batteries in hooks/checks/, per-tool adapters in hooks/adapters/.
HOOKS_DIR="$REPO_ROOT/hooks"
CHECKS_DIR="$HOOKS_DIR/checks"
ADAPTERS_DIR="$HOOKS_DIR/adapters"
MCP_DIR="$CONFIG_DIR/mcp"
MCP_CONFIG_FILE="$MCP_DIR/servers.json"
# Brave Search MCP — a second, opt-in MCP source merged in by the OpenCode and
# Pi-agent writers only, and only when the key file below holds a key. The
# server reads the key from the file (BRAVE_API_KEY_FILE takes precedence over
# BRAVE_API_KEY upstream), so no secret is ever written into a config file.
# Keep BRAVE_KEY_FILE in sync with the path in config/mcp/brave.json.
BRAVE_MCP_CONFIG_FILE="$MCP_DIR/brave.json"
BRAVE_KEY_FILE="$HOME/.config/macols/brave-api-key"
# AWS MCP servers (aws-mcp, aws-iac) — a third, opt-in source registered for
# every tool, but only when the user opts in (--aws-mcp or MACOLS_AWS_MCP=1).
# The answer is remembered in AWS_MCP_CHOICE_FILE ("on"/"off").
AWS_MCP_CONFIG_FILE="$MCP_DIR/aws.json"
AWS_MCP_CHOICE_FILE="$HOME/.config/macols/aws-mcp"

# ── Pinned versions ──────────────────────────────────────────────────────────
# Ponytail (https://github.com/DietrichGebert/ponytail) — installed for every
# agent via that agent's native mechanism (Claude Code plugin, omp package,
# AGENTS.md ruleset block). The marker comments delimit the AGENTS.md block so
# re-runs replace it instead of duplicating it.
PONYTAIL_REPO="DietrichGebert/ponytail"
PONYTAIL_MARKER_START="<!-- ponytail:ruleset:start (managed by macols-configs — do not edit between markers) -->"
PONYTAIL_MARKER_END="<!-- ponytail:ruleset:end -->"
# revdiff (https://revdiff.com) — TUI diff review. The brew formula provides the
# binary; the repo doubles as the Claude/Codex marketplace and the pi package.
REVDIFF_REPO="umputun/revdiff"
REVDIFF_FORMULA="umputun/apps/revdiff"

# Ensure Node.js is in PATH (sources NVM/fnm if needed). Node powers persona
# generation, steering assembly and the JSON config writers.
if [ -f "$CHECKS_DIR/ensure_node.sh" ]; then
    # shellcheck disable=SC1091
    source "$CHECKS_DIR/ensure_node.sh"
fi

# ── Banner helpers ───────────────────────────────────────────────────────────
banner() {
    printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${CYAN}%s${NC}\n" "$1"
    printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"
}

done_banner() {
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}Installation complete! 🎉${NC}\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"
}

# ── Modules ──────────────────────────────────────────────────────────────────
# One file per job; this file only holds what they all share (colours, repo
# layout, pinned versions, banners).
# shellcheck source=lib/os.sh
source "$LIB_DIR/os.sh"
# shellcheck source=lib/personas.sh
source "$LIB_DIR/personas.sh"
# shellcheck source=lib/steering.sh
source "$LIB_DIR/steering.sh"
# shellcheck source=lib/mcp.sh
source "$LIB_DIR/mcp.sh"
# shellcheck source=lib/omp-models.sh
source "$LIB_DIR/omp-models.sh"
# shellcheck source=lib/hooks.sh
source "$LIB_DIR/hooks.sh"
# shellcheck source=lib/plugins.sh
source "$LIB_DIR/plugins.sh"

#!/usr/bin/env bash
#
# lib/plugins.sh — third-party agent plugins: the Claude Code marketplace
# helper, and revdiff (the binary plus each harness's upstream plugin).
#
# Sourced by lib/common.sh, which sets the colours and pinned repos used here.
# Not meant to be executed directly.

# install_claude_plugin <marketplace> <owner/repo> <plugin> — add a GitHub
# marketplace and install one of its plugins for Claude Code,
# non-interactively. Prefers the `claude plugin` CLI (guarded by the list
# output, and re-add/re-install are no-ops anyway); if the CLI is missing or
# cannot fetch the repo, falls back to declaring the marketplace + plugin in
# user settings, which Claude Code resolves on next launch.
install_claude_plugin() {
    local market="$1" repo="$2" ref="$3@$1"
    printf "${BLUE}Installing %s plugin (Claude Code)...${NC}\n" "$3"
    if command -v claude &> /dev/null && claude plugin --help &> /dev/null; then
        if { claude plugin marketplace list 2>/dev/null | grep -qi "$repo" \
              || claude plugin marketplace add "$repo"; } \
           && { claude plugin list 2>/dev/null | grep -q "$ref" \
              || claude plugin install "$ref"; }; then
            printf "${GREEN}✓ %s plugin installed${NC}\n" "$ref"
            return 0
        fi
        printf "${YELLOW}⚠ claude plugin CLI could not fetch %s — declaring it in settings.json instead${NC}\n" "$repo"
    fi
    require_node || return 1
    mkdir -p "$HOME/.claude"
    SETTINGS_FILE="$HOME/.claude/settings.json" MARKET="$market" REPO="$repo" REF="$ref" node -e '
const fs = require("fs"), env = process.env;
let s = {};
if (fs.existsSync(env.SETTINGS_FILE)) { try { s = JSON.parse(fs.readFileSync(env.SETTINGS_FILE, "utf8")); } catch (e) {} }
s.extraKnownMarketplaces = s.extraKnownMarketplaces || {};
s.extraKnownMarketplaces[env.MARKET] = { source: { source: "github", repo: env.REPO } };
s.enabledPlugins = s.enabledPlugins || {};
s.enabledPlugins[env.REF] = true;
fs.writeFileSync(env.SETTINGS_FILE, JSON.stringify(s, null, 2) + "\n");
'
    printf "${GREEN}✓ %s marketplace + plugin declared in ~/.claude/settings.json (fetched on next launch)${NC}\n" "$market"
}

# ── revdiff ──────────────────────────────────────────────────────────────────
# revdiff (https://revdiff.com) is a TUI for annotating diffs, files and plans;
# each harness plugin opens it in a terminal overlay (tmux, herdr, kitty, …)
# and feeds the annotations back to the agent. Upstream ships a plugin for
# Claude Code, Codex, OpenCode and pi (which omp loads through its legacy-pi
# shim). ZCode has none. Only the diff-review plugin is installed; the
# separate auto-firing `revdiff-planning` plugin stays opt-in.

# ensure_revdiff — install the revdiff binary every plugin shells out to.
# Homebrew only: macOS always has it (ensure_brew) and the Ubuntu machine setup
# bootstraps linuxbrew. Upstream's `go install …/app/revdiff` path only exists
# on master, not at the latest tag, so it is not used as a fallback.
ensure_revdiff() {
    if command -v revdiff &> /dev/null; then
        printf "${GREEN}✓ revdiff already installed${NC}\n"
        return 0
    fi
    command -v brew &> /dev/null || { printf "${YELLOW}No Homebrew — install revdiff by hand: https://revdiff.com/#install${NC}\n"; return 1; }
    printf "${BLUE}Installing revdiff (TUI diff review for the agent plugins)...${NC}\n"
    brew install "$REVDIFF_FORMULA" || return 1
    printf "${GREEN}✓ revdiff installed: %s${NC}\n" "$(command -v revdiff)"
}

# install_codex_revdiff — upstream's Codex plugin. Both commands are no-ops
# when the marketplace and plugin are already present.
install_codex_revdiff() {
    local standalone="$HOME/.codex/packages/standalone/current"
    command -v codex &> /dev/null || export PATH="$standalone:$PATH"
    command -v codex &> /dev/null || { printf "${YELLOW}codex not found — skipping the revdiff plugin${NC}\n"; return 1; }
    printf "${BLUE}Installing revdiff plugin (Codex)...${NC}\n"
    { codex plugin marketplace add "$REVDIFF_REPO" && codex plugin add revdiff@revdiff; } || return 1
    printf "${GREEN}✓ revdiff@revdiff plugin installed${NC}\n"
}

# install_opencode_revdiff — OpenCode has no plugin registry, so run
# upstream's setup script from a cached clone. It copies the /revdiff command,
# tool and launcher into ~/.config/opencode and adds its plan-review plugin to
# opencode.json's "plugin" array (jq-guarded, so re-runs do not duplicate it).
install_opencode_revdiff() {
    local src="${XDG_CACHE_HOME:-$HOME/.cache}/macols/revdiff"
    ensure_mcp_prereqs || return 1   # setup.sh edits opencode.json with jq
    printf "${BLUE}Installing revdiff tool + command (OpenCode)...${NC}\n"
    if [ -d "$src/.git" ]; then
        git -C "$src" pull -q --ff-only || return 1
    else
        rm -rf "$src"; mkdir -p "$(dirname "$src")"
        git clone -q --depth 1 "https://github.com/$REVDIFF_REPO.git" "$src" || return 1
    fi
    bash "$src/plugins/opencode/setup.sh" > /dev/null || return 1
    printf "${GREEN}✓ revdiff installed into ~/.config/opencode${NC}\n"
}

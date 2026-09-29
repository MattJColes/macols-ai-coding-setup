#!/usr/bin/env bash
#
# lib/plugins.sh — third-party agent plugins: the Claude Code marketplace
# helper, and hunk (the binary plus its bundled hunk-review skill).
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

# ── hunk ─────────────────────────────────────────────────────────────────────
# hunk (https://hunk.dev) is a review-first terminal diff viewer. Its agent
# integration is one Agent Skill, hunk-review, bundled with the binary
# (`hunk skill path`): the user opens `hunk diff` in a terminal and the agent
# steers that live window with `hunk session ...` (navigate, comment,
# highlight). No per-harness plugin, so every agent, ZCode included, gets it
# the same way. It replaced revdiff; remove_revdiff_* clean up the revdiff
# plugins earlier versions of this repo installed.

# ensure_hunk — install the hunk binary. Homebrew first (machine/Brewfile
# carries the formula), then the hunkdiff npm package (Node 22+), which is the
# channel every installer already bootstraps.
ensure_hunk() {
    if command -v hunk &> /dev/null; then
        printf "${GREEN}✓ hunk already installed${NC}\n"
        return 0
    fi
    printf "${BLUE}Installing hunk (terminal diff review the agents steer)...${NC}\n"
    if command -v brew &> /dev/null; then
        brew install "$HUNK_FORMULA" || return 1
    elif command -v npm &> /dev/null; then
        npm install -g "$HUNK_NPM" || return 1
    else
        printf "${YELLOW}No Homebrew or npm — install hunk by hand: https://hunk.dev${NC}\n"
        return 1
    fi
    printf "${GREEN}✓ hunk installed: %s${NC}\n" "$(command -v hunk)"
}

# install_hunk_skill <skills_dir> — copy the hunk-review skill that ships with
# the installed binary into <skills_dir>/hunk-review/SKILL.md. A copy, not the
# symlink upstream suggests: several agents skip symlinked entries when they
# scan for skills, and a brew upgrade would leave the link dangling. Re-running
# the installer after `hunk update` refreshes it. Call it after the skills dir
# is regenerated (every installer wipes it first).
install_hunk_skill() {
    local src
    command -v hunk &> /dev/null || { printf "${YELLOW}hunk not found — skipping the hunk-review skill${NC}\n"; return 1; }
    src="$(hunk skill path hunk-review 2>/dev/null)" && [ -f "$src" ] || { printf "${YELLOW}hunk skill path failed — skipping the hunk-review skill${NC}\n"; return 1; }
    mkdir -p "$1/hunk-review"
    cp "$src" "$1/hunk-review/SKILL.md"
    printf "${GREEN}✓ hunk-review skill installed to %s${NC}\n" "$1/hunk-review"
}

# remove_revdiff_claude — uninstall the revdiff plugin and marketplace, or
# drop the settings.json declaration the offline fallback wrote.
remove_revdiff_claude() {
    local settings="$HOME/.claude/settings.json"
    if command -v claude &> /dev/null && claude plugin --help &> /dev/null; then
        claude plugin list 2>/dev/null | grep -q 'revdiff@revdiff' && claude plugin uninstall revdiff@revdiff > /dev/null 2>&1
        claude plugin marketplace list 2>/dev/null | grep -qi "$REVDIFF_REPO" && claude plugin marketplace remove revdiff > /dev/null 2>&1
    fi
    if grep -qs 'revdiff@revdiff' "$settings" && command -v jq &> /dev/null; then
        jq --arg repo "$REVDIFF_REPO" 'del(.enabledPlugins["revdiff@revdiff"])
            | if .extraKnownMarketplaces.revdiff.source.repo == $repo then del(.extraKnownMarketplaces.revdiff) else . end' \
            "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
    fi
    return 0
}

# remove_revdiff_codex — uninstall the revdiff plugin and its marketplace.
remove_revdiff_codex() {
    command -v codex &> /dev/null || return 0
    grep -qs 'revdiff' "$HOME/.codex/config.toml" || return 0
    codex plugin remove revdiff@revdiff > /dev/null 2>&1 || true
    codex plugin marketplace remove revdiff > /dev/null 2>&1 || true
    printf "${GREEN}✓ revdiff plugin removed (Codex)${NC}\n"
}

# remove_revdiff_opencode — delete the files upstream's setup.sh copied into
# ~/.config/opencode (including the auto-loaded plan-review plugin), its
# "plugin" entry in opencode.json, and the cached clone.
remove_revdiff_opencode() {
    local d="$HOME/.config/opencode" json="$HOME/.config/opencode/opencode.json" f found=0
    for f in tools/revdiff.ts tools/launch-revdiff.sh commands/revdiff.md plugins/revdiff-plan-review.ts plugins/launch-plan-review.sh; do
        [ -e "$d/$f" ] && { rm -f "$d/$f"; found=1; }
    done
    if grep -qs 'revdiff-plan-review' "$json" && command -v jq &> /dev/null; then
        jq '.plugin |= map(select(. != "./plugins/revdiff-plan-review.ts"))' "$json" > "$json.tmp" && mv "$json.tmp" "$json"
        found=1
    fi
    rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/macols/revdiff"
    [ "$found" = 1 ] && printf "${GREEN}✓ revdiff tool, command and plugin removed (OpenCode)${NC}\n"
    return 0
}

# remove_revdiff_pi — uninstall the revdiff package from pi and omp.
remove_revdiff_pi() {
    if command -v pi &> /dev/null && grep -qs "$REVDIFF_REPO" "$HOME/.pi/agent/settings.json"; then
        pi remove "git:github.com/$REVDIFF_REPO" > /dev/null 2>&1 && printf "${GREEN}✓ revdiff package removed (pi)${NC}\n"
    fi
    if command -v omp &> /dev/null && grep -qs 'revdiff-pi' "$HOME/.omp/plugins/package.json"; then
        omp plugin uninstall revdiff-pi > /dev/null 2>&1 && printf "${GREEN}✓ revdiff package removed (omp)${NC}\n"
    fi
    return 0
}

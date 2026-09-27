#!/usr/bin/env bash
#
# lib/steering.sh — Steering assembly (config/steering) and the ponytail ruleset block.
#
# Sourced by lib/common.sh, which sets the colours and repo layout variables
# used here. Not meant to be executed directly.
# shellcheck disable=SC2034  # variables here are read by other modules/installers

# ── Steering assembly (single source: config/steering/base.md + tools/<tool>.json)
# assemble_steering <claudecode|codex|opencode|pi> <dest_file>
assemble_steering() {
    require_node || return 1
    local tool="$1" dest="$2"
    local vars="$STEERING_DIR/tools/$tool.json"
    if [ ! -f "$STEERING_DIR/base.md" ] || [ ! -f "$vars" ]; then
        printf "${RED}Steering source missing (base.md or %s)${NC}\n" "$vars"; return 1
    fi
    if [ ! -f "$RESPONSE_FORMAT_FILE" ]; then
        printf "${RED}Steering source missing (%s)${NC}\n" "$RESPONSE_FORMAT_FILE"; return 1
    fi
    mkdir -p "$(dirname "$dest")"
    # RESPONSE_FORMAT is not a per-tool var — it comes from its own shared file so
    # the same block can also be appended to every rendered persona.
    BASE="$STEERING_DIR/base.md" VARS="$vars" DEST="$dest" RF="$RESPONSE_FORMAT_FILE" node -e '
const fs = require("fs");
let out = fs.readFileSync(process.env.BASE, "utf8");
const vars = JSON.parse(fs.readFileSync(process.env.VARS, "utf8"));
vars.RESPONSE_FORMAT = fs.readFileSync(process.env.RF, "utf8").trim();
for (const [k, v] of Object.entries(vars)) {
    const val = Array.isArray(v) ? v.join("\n") : String(v);
    out = out.split("{{" + k + "}}").join(val);
}
fs.writeFileSync(process.env.DEST, out);
'
    printf "${GREEN}✓ Wrote steering to %s${NC}\n" "$dest"
}

# ── Ponytail (github.com/DietrichGebert/ponytail) ────────────────────────────
# Every agent gets ponytail exactly once, via its native mechanism: Claude Code
# as a plugin, pi and omp as a package (see installers/pi.sh), and Codex,
# OpenCode and ZCode as a marker-delimited ruleset block appended to AGENTS.md.
# Project-mode AGENTS.md files keep the block, since other tools read them.

# append_ponytail_ruleset <agents_md> — merge ponytail's AGENTS.md ruleset
# (vendored from the upstream repo into config/steering/ponytail.AGENTS.md)
# into an AGENTS.md without clobbering existing content. Idempotent and
# self-healing: an existing marker block is removed before the current one is
# appended, so re-runs never duplicate it.
append_ponytail_ruleset() {
    local dest="$1" src="$STEERING_DIR/ponytail.AGENTS.md"
    [ -f "$src" ] || { printf "${RED}ponytail ruleset source not found: %s${NC}\n" "$src"; return 1; }
    mkdir -p "$(dirname "$dest")"
    [ -f "$dest" ] || : > "$dest"
    if grep -qF "$PONYTAIL_MARKER_START" "$dest"; then
        awk -v s="$PONYTAIL_MARKER_START" -v e="$PONYTAIL_MARKER_END" \
            'index($0, s) { skip = 1 } skip != 1 { print } index($0, e) { skip = 0 }' \
            "$dest" > "$dest.tmp" && mv "$dest.tmp" "$dest"
    fi
    {
        echo ""
        echo "$PONYTAIL_MARKER_START"
        cat "$src"
        echo "$PONYTAIL_MARKER_END"
    } >> "$dest"
    printf "${GREEN}✓ Ponytail ruleset merged into %s${NC}\n" "$dest"
}

# install_claude_ponytail — add the ponytail marketplace + plugin for Claude
# Code, non-interactively. Prefers the `claude plugin` CLI (idempotent: re-add
# and re-install are no-ops); if the CLI is missing or cannot fetch the repo,
# falls back to declaring the marketplace + plugin in user settings, which
# Claude Code resolves on next launch.
install_claude_ponytail() {
    printf "${BLUE}Installing ponytail plugin (Claude Code)...${NC}\n"
    if command -v claude &> /dev/null && claude plugin --help &> /dev/null; then
        if { claude plugin marketplace list 2>/dev/null | grep -qi ponytail \
              || claude plugin marketplace add "$PONYTAIL_REPO"; } \
           && { claude plugin list 2>/dev/null | grep -q "ponytail@ponytail" \
              || claude plugin install ponytail@ponytail; }; then
            printf "${GREEN}✓ ponytail plugin installed (ponytail@ponytail)${NC}\n"
            return 0
        fi
        printf "${YELLOW}⚠ claude plugin CLI could not fetch %s — declaring it in settings.json instead${NC}\n" "$PONYTAIL_REPO"
    fi
    require_node || return 1
    mkdir -p "$HOME/.claude"
    SETTINGS_FILE="$HOME/.claude/settings.json" PONYTAIL_REPO="$PONYTAIL_REPO" node -e '
const fs = require("fs"), env = process.env;
let s = {};
if (fs.existsSync(env.SETTINGS_FILE)) { try { s = JSON.parse(fs.readFileSync(env.SETTINGS_FILE, "utf8")); } catch (e) {} }
s.extraKnownMarketplaces = s.extraKnownMarketplaces || {};
s.extraKnownMarketplaces.ponytail = { source: { source: "github", repo: env.PONYTAIL_REPO } };
s.enabledPlugins = s.enabledPlugins || {};
s.enabledPlugins["ponytail@ponytail"] = true;
fs.writeFileSync(env.SETTINGS_FILE, JSON.stringify(s, null, 2) + "\n");
'
    printf "${GREEN}✓ ponytail marketplace + plugin declared in ~/.claude/settings.json (fetched on next launch)${NC}\n"
}

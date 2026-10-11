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
# and Codex as a plugin, OpenCode as an npm plugin in opencode.json, pi and omp
# as a package (see installers/pi.sh), and ZCode (which upstream no longer
# supports) as a marker-delimited ruleset block appended to AGENTS.md. Codex
# and OpenCode fall back to the block when their plugin is absent. Project-mode
# AGENTS.md files keep the block, since other tools read them.

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
# Code (install_claude_plugin in lib/plugins.sh; falls back to a settings.json
# declaration when offline).
install_claude_ponytail() {
    install_claude_plugin ponytail "$PONYTAIL_REPO" ponytail
}

# install_codex_ponytail — upstream's Codex plugin: lifecycle hooks that inject
# the ruleset, plus the ponytail-* skills. Both commands are no-ops on a re-run.
# Codex runs the hooks only once the user trusts them in /hooks.
install_codex_ponytail() {
    command -v codex &> /dev/null || export PATH="$HOME/.codex/packages/standalone/current:$PATH"
    command -v codex &> /dev/null || { printf "${YELLOW}codex not found — skipping the ponytail plugin${NC}\n"; return 1; }
    printf "${BLUE}Installing ponytail plugin (Codex)...${NC}\n"
    { codex plugin marketplace add "$PONYTAIL_REPO" && codex plugin add ponytail@ponytail; } > /dev/null || return 1
    printf "${GREEN}✓ ponytail@ponytail plugin installed${NC}\n"
    printf "${YELLOW}  Trust its two hooks in Codex's /hooks so the ruleset loads every session.${NC}\n"
}

# install_opencode_ponytail — add upstream's npm plugin to the "plugin" array
# of ~/.config/opencode/opencode.json (OpenCode 1 has no `plugin add`; it
# installs listed packages on launch). Merged: other entries survive, and a
# present entry (pinned or not) is left alone.
install_opencode_ponytail() {
    require_node || return 1
    local dest="$HOME/.config/opencode/opencode.json"
    mkdir -p "$(dirname "$dest")"
    DEST="$dest" PKG="$PONYTAIL_NPM" node -e '
const fs = require("fs"), e = process.env;
const cfg = fs.existsSync(e.DEST) ? JSON.parse(fs.readFileSync(e.DEST, "utf8")) : {};
const plugins = Array.isArray(cfg.plugin) ? cfg.plugin : [];
const name = p => String(Array.isArray(p) ? p[0] : p);
if (!plugins.some(p => name(p) === e.PKG || name(p).startsWith(e.PKG + "@"))) plugins.push(e.PKG);
cfg.plugin = plugins;
fs.writeFileSync(e.DEST, JSON.stringify(cfg, null, 2) + "\n");
' || return 1
    printf "${GREEN}✓ %s plugin listed in %s${NC}\n" "$PONYTAIL_NPM" "$dest"
}

# ponytail_plugin_present <codex|opencode> — true when that tool already loads
# ponytail as a plugin, so its user-level AGENTS.md needs no ruleset block.
ponytail_plugin_present() {
    case "$1" in
        codex)    grep -qsF 'plugins."ponytail@ponytail"' "$HOME/.codex/config.toml" ;;
        opencode) grep -qsF "\"$PONYTAIL_NPM" "$HOME/.config/opencode/opencode.json" ;;
        *) return 1 ;;
    esac
}

# ponytail_ruleset_unless_plugin <codex|opencode> <agents_md> — the ruleset
# block is the fallback for when the plugin is absent (CLI missing, offline,
# --no-cli); with the plugin present the freshly assembled AGENTS.md stays
# block-free, so the rules load once.
ponytail_ruleset_unless_plugin() {
    if ponytail_plugin_present "$1"; then
        printf "${GREEN}✓ Ponytail comes from the %s plugin — no ruleset block in %s${NC}\n" "$1" "$2"
    else
        append_ponytail_ruleset "$2"
    fi
}

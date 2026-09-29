#!/usr/bin/env bash
#
# lib/mcp.sh — MCP registration from config/mcp/*.json, plus the Brave and AWS opt-ins.
#
# Sourced by lib/common.sh, which sets the colours and repo layout variables
# used here. Not meant to be executed directly.
# shellcheck disable=SC2034  # variables here are read by other modules/installers

# ── Brave Search API key ─────────────────────────────────────────────────────

# ensure_brave_api_key — make sure a Brave Search API key is on disk so the
# brave-search MCP can be registered (OpenCode and the Pi agents only).
#
# Returns 0 when $BRAVE_KEY_FILE holds a key, 1 otherwise — callers treat 1 as
# non-fatal, the registration writers then simply leave brave-search out.
# Idempotent: an existing key file short-circuits, so re-runs never re-prompt.
# Non-interactive installs (CI, stdin not a tty) skip silently unless
# BRAVE_API_KEY is exported. The key is never echoed back and never written
# into a config file.
ensure_brave_api_key() {
    if [ -s "$BRAVE_KEY_FILE" ]; then
        printf "${GREEN}✓ Brave Search API key already configured (%s)${NC}\n" "$BRAVE_KEY_FILE"
        return 0
    fi

    local key="${BRAVE_API_KEY:-}"
    if [ -n "$key" ]; then
        printf "${BLUE}Using BRAVE_API_KEY from the environment${NC}\n"
    elif [ -t 0 ]; then
        printf "${BLUE}Brave Search MCP — get a key at https://brave.com/search/api/${NC}\n"
        read -rsp "$(printf "${YELLOW}Brave Search API key (blank to skip): ${NC}")" key
        echo ""
    else
        printf "${YELLOW}⚠ Non-interactive install — set BRAVE_API_KEY to enable Brave Search${NC}\n"
        return 1
    fi

    # Trim surrounding whitespace from a pasted key.
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    [ -n "$key" ] || return 1

    mkdir -p "$(dirname "$BRAVE_KEY_FILE")"
    (umask 077; printf '%s\n' "$key" > "$BRAVE_KEY_FILE")
    chmod 600 "$BRAVE_KEY_FILE"
    printf "${GREEN}✓ Brave Search API key saved to %s (mode 600)${NC}\n" "$BRAVE_KEY_FILE"
}

# ── AWS MCP opt-in ───────────────────────────────────────────────────────────

# ensure_aws_mcp_choice — decide whether the opt-in AWS MCP servers
# (config/mcp/aws.json) are registered, and remember the answer so the
# other installers (and re-runs) do not ask again.
#
# Order: MACOLS_AWS_MCP from the environment (the --aws-mcp / --no-aws-mcp
# flags set it), then the remembered choice in $AWS_MCP_CHOICE_FILE, then a
# y/N prompt when stdin is a tty. A non-interactive install with nothing set
# defaults to off without recording anything. Returns 0 when AWS is on (after
# making sure uv/uvx is available), 1 when off — callers treat 1 as non-fatal.
ensure_aws_mcp_choice() {
    local choice=""
    case "${MACOLS_AWS_MCP:-}" in
        1|y|Y|yes|true|on)  choice=on ;;
        0|n|N|no|false|off) choice=off ;;
    esac
    if [ -z "$choice" ] && [ -s "$AWS_MCP_CHOICE_FILE" ]; then
        choice="$(tr -d '[:space:]' < "$AWS_MCP_CHOICE_FILE")"
    elif [ -z "$choice" ] && [ -t 0 ]; then
        local ans=""
        read -rp "$(printf "${YELLOW}Register the AWS MCP servers (aws-mcp, aws-iac; need ~/.aws credentials)? [y/N] ${NC}")" ans
        case "$ans" in y|Y|yes|YES) choice=on ;; *) choice=off ;; esac
    fi
    if [ -n "$choice" ] && [ "$(cat "$AWS_MCP_CHOICE_FILE" 2>/dev/null)" != "$choice" ]; then
        mkdir -p "$(dirname "$AWS_MCP_CHOICE_FILE")"
        printf '%s\n' "$choice" > "$AWS_MCP_CHOICE_FILE"
    fi
    [ "$choice" = on ] || return 1
    if ! command -v uvx &> /dev/null; then
        printf "${YELLOW}uv not found. Installing (the AWS MCP servers run through uvx)...${NC}\n"
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
        command -v uvx &> /dev/null \
            || printf "${YELLOW}⚠ uv install failed — the aws-* MCPs are registered but need uvx on PATH to start${NC}\n"
    fi
    return 0
}

# aws_mcp_enabled — true when the AWS MCP servers should be registered. Reads
# the same inputs as ensure_aws_mcp_choice without prompting.
aws_mcp_enabled() {
    case "${MACOLS_AWS_MCP:-}" in
        1|y|Y|yes|true|on)  return 0 ;;
        0|n|N|no|false|off) return 1 ;;
    esac
    [ -s "$AWS_MCP_CHOICE_FILE" ] && [ "$(tr -d '[:space:]' < "$AWS_MCP_CHOICE_FILE")" = on ]
}

# ── MCP registration (sources: config/mcp/*.json) ──────────────────────

# mcp_resolve <tool> — print the servers this repo wants registered for <tool>
# as {"servers": {...}, "stale": {...}}, with $HOME expanded.
#
#   servers  the default list, plus the AWS servers when opted in, plus
#            brave-search for opencode/pi when a Brave key is configured. A
#            server whose `requires` binary is not on PATH (dart, gopls) is left
#            out; the `requires` key itself is dropped.
#   stale    names this repo owns that must not stay registered: servers left
#            out above, and retired ones. The value is null (remove outright) or
#            a package string the entry must still contain before it is removed,
#            so a user's own server of the same name survives.
#
# Every writer consumes this, so all five tools see the same list.
mcp_resolve() {
    require_node || return 1
    local tool="$1" brave=0 aws=0 brave_src=""
    [ -f "$MCP_CONFIG_FILE" ] || { printf "${RED}MCP config not found: %s${NC}\n" "$MCP_CONFIG_FILE" >&2; return 1; }
    aws_mcp_enabled && aws=1
    case "$tool" in
        opencode|pi) brave_src="$BRAVE_MCP_CONFIG_FILE"; [ -s "$BRAVE_KEY_FILE" ] && brave=1 ;;
    esac
    SRC="$MCP_CONFIG_FILE" SRC_AWS="$AWS_MCP_CONFIG_FILE" AWS_ON="$aws" \
    SRC_BRAVE="$brave_src" BRAVE_ON="$brave" HOME_DIR="$HOME" node -e '
const fs = require("fs"), path = require("path"), e = process.env;
const read = (p) => (p && fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, "utf8")).mcpServers || {} : {});
const onPath = (bin) => (e.PATH || "").split(path.delimiter).some((d) => {
    try { fs.accessSync(path.join(d, bin), fs.constants.X_OK); return true; } catch (err) { return false; }
});
const expand = (s) => String(s).split("$HOME").join(e.HOME_DIR);
const servers = {};
// Retired servers: removed only while the entry still runs the package this repo installed.
const stale = {
    filesystem: "@modelcontextprotocol/server-filesystem",
    puppeteer: "@modelcontextprotocol/server-puppeteer",
};
for (const [src, on] of [[e.SRC, true], [e.SRC_AWS, e.AWS_ON === "1"], [e.SRC_BRAVE, e.BRAVE_ON === "1"]]) {
    for (const [name, s] of Object.entries(read(src))) {
        if (!on || (s.requires && !onPath(s.requires))) { stale[name] = null; continue; }
        const entry = { command: expand(s.command), args: (s.args || []).map(expand) };
        if (s.env) entry.env = Object.fromEntries(Object.entries(s.env).map(([k, v]) => [k, expand(v)]));
        servers[name] = entry;
    }
}
process.stdout.write(JSON.stringify({ servers, stale }));
'
}

# mcp_remove_stale_cli <claude|codex> <resolved_json> — unregister the stale
# names from mcp_resolve through the tool's CLI, honouring the package check.
mcp_remove_stale_cli() {
    local cli="$1" resolved="$2" name marker
    while IFS=$'\t' read -r name marker; do
        [ -n "$name" ] || continue
        "$cli" mcp get "$name" > /dev/null 2>&1 || continue
        if [ -n "$marker" ] && ! "$cli" mcp get "$name" 2>/dev/null | grep -qF -- "$marker"; then
            continue
        fi
        "$cli" mcp remove "$name" > /dev/null 2>&1 && printf "  ${YELLOW}✓ removed stale %s${NC}\n" "$name"
    done < <(jq -r '.stale | to_entries[] | "\(.key)\t\(.value // "")"' <<< "$resolved")
}

# register_mcps_claude — register every server at user scope via the claude CLI.
register_mcps_claude() {
    printf "${BLUE}Registering MCP servers (Claude Code)...${NC}\n"
    command -v claude &> /dev/null || { printf "${RED}claude CLI not found${NC}\n"; return 1; }
    ensure_mcp_prereqs || return 1
    ensure_aws_mcp_choice || true
    local resolved name
    resolved="$(mcp_resolve claudecode)" || return 1

    for name in $(jq -r '.servers | keys[]' <<< "$resolved"); do
        printf "${BLUE}→ %s${NC}\n" "$name"
        claude mcp remove "$name" >/dev/null 2>&1 || true
        if claude mcp add-json -s user "$name" "$(jq -c --arg n "$name" '.servers[$n]' <<< "$resolved")" >/dev/null 2>&1; then
            printf "  ${GREEN}✓ registered${NC}\n"
        else
            printf "  ${RED}✗ failed to register${NC}\n"
        fi
    done
    mcp_remove_stale_cli claude "$resolved"
    printf "${GREEN}✓ MCP servers registered (run 'claude mcp list' to inspect)${NC}\n"
}

# register_mcps_codex — register every server at user scope via the codex CLI.
register_mcps_codex() {
    printf "${BLUE}Registering MCP servers (Codex)...${NC}\n"
    command -v codex &> /dev/null || { printf "${RED}codex CLI not found${NC}\n"; return 1; }
    ensure_mcp_prereqs || return 1
    ensure_aws_mcp_choice || true
    local resolved name command_bin
    resolved="$(mcp_resolve codex)" || return 1

    for name in $(jq -r '.servers | keys[]' <<< "$resolved"); do
        printf "${BLUE}→ %s${NC}\n" "$name"
        local env_flags=() args=()
        while IFS= read -r kv; do [ -z "$kv" ] && continue; env_flags+=(--env "$kv"); done < <(jq -r --arg n "$name" \
            '.servers[$n].env // {} | to_entries[] | "\(.key)=\(.value)"' <<< "$resolved")
        command_bin=$(jq -r --arg n "$name" '.servers[$n].command' <<< "$resolved")
        while IFS= read -r a; do args+=("$a"); done < <(jq -r --arg n "$name" '.servers[$n].args[]' <<< "$resolved")
        codex mcp remove "$name" >/dev/null 2>&1 || true
        if codex mcp add "$name" "${env_flags[@]+"${env_flags[@]}"}" -- "$command_bin" "${args[@]+"${args[@]}"}" >/dev/null 2>&1; then
            printf "  ${GREEN}✓ registered${NC}\n"
        else
            printf "  ${RED}✗ failed to register${NC}\n"
        fi
    done
    mcp_remove_stale_cli codex "$resolved"
    printf "${GREEN}✓ MCP servers registered (run 'codex mcp list' to inspect)${NC}\n"
}

# mcp_merge_json <opencode|pi|zcode> <dest> <resolved_json> — merge the resolved
# servers into a user-owned JSON config in that tool's shape. Entries this repo
# does not own survive; stale owned entries are deleted; every other key in the
# file is preserved. Idempotent. A file that does not parse is left untouched
# and the call fails, rather than overwriting the user's config.
mcp_merge_json() {
    require_node || return 1
    mkdir -p "$(dirname "$2")"
    SHAPE="$1" DEST="$2" RESOLVED="$3" node -e '
const fs = require("fs"), e = process.env;
const { servers, stale } = JSON.parse(e.RESOLVED);
let cfg = {};
if (fs.existsSync(e.DEST)) {
    try { cfg = JSON.parse(fs.readFileSync(e.DEST, "utf8")); }
    catch (err) { console.error(`${e.DEST} is not valid JSON (${err.message}) - left untouched`); process.exit(1); }
}
const shapes = {
    // OpenCode: {"mcp": {name: {type: "local", command: [cmd, ...args], environment, enabled}}}
    opencode: {
        map: (c) => { c["$schema"] = c["$schema"] || "https://opencode.ai/config.json"; return (c.mcp = c.mcp || {}); },
        entry: (s) => Object.assign({ type: "local", command: [s.command, ...s.args], enabled: true }, s.env ? { environment: s.env } : {}),
    },
    // Pi agents (omp mcp.json, the pi-mcp-adapter mcp-adapter.json):
    // {"mcpServers": {name: {command, args, env}}}, the Claude shape.
    pi: {
        map: (c) => (c.mcpServers = c.mcpServers || {}),
        entry: (s) => Object.assign({ command: s.command, args: s.args }, s.env ? { env: s.env } : {}),
    },
    // ZCode: {"mcp": {"servers": {...}}}. Its schema is strict - an unknown key
    // silently drops the whole server - so each entry carries only these keys.
    zcode: {
        map: (c) => { c.mcp = c.mcp || {}; return (c.mcp.servers = c.mcp.servers || {}); },
        entry: (s) => Object.assign({ type: "stdio", command: s.command, args: s.args, enabled: true }, s.env ? { env: s.env } : {}),
    },
};
const shape = shapes[e.SHAPE];
const map = shape.map(cfg);
for (const [name, marker] of Object.entries(stale)) {
    if (name in map && (marker === null || JSON.stringify(map[name]).includes(marker))) delete map[name];
}
for (const [name, s] of Object.entries(servers)) map[name] = shape.entry(s);
fs.writeFileSync(e.DEST, JSON.stringify(cfg, null, 2) + "\n");
'
}

# register_mcps_opencode — merge the servers into the "mcp" key of
# ~/.config/opencode/opencode.json (OpenCode reads MCP only from opencode.json;
# a standalone mcp.json is ignored). brave-search is included when a Brave API
# key is configured.
register_mcps_opencode() {
    printf "${BLUE}Writing MCP config into opencode.json...${NC}\n"
    ensure_aws_mcp_choice || true
    local resolved dest="$HOME/.config/opencode/opencode.json"
    resolved="$(mcp_resolve opencode)" || return 1
    mcp_merge_json opencode "$dest" "$resolved" || return 1
    printf "${GREEN}✓ MCP servers written to %s${NC}\n" "$dest"
}

# register_mcps_pi <config_json> — merge the servers into the "mcpServers" key
# of a Pi-agent MCP file. Both agents use the Claude shape:
#   ~/.omp/agent/mcp.json         Oh My Pi's native MCP config
#   ~/.pi/agent/mcp-adapter.json  plain pi, read by the pi-mcp-adapter package
#                                 (which never reads ~/.pi/agent/mcp.json)
# Other keys in the file (disabledServers, the adapter's settings) are
# preserved. brave-search is included when a Brave API key is configured.
register_mcps_pi() {
    printf "${BLUE}Writing MCP config into %s...${NC}\n" "$(basename "$1")"
    ensure_aws_mcp_choice || true
    local resolved
    resolved="$(mcp_resolve pi)" || return 1
    mcp_merge_json pi "$1" "$resolved" || return 1
    printf "${GREEN}✓ MCP servers written to %s${NC}\n" "$1"
}

# register_mcps_zcode — merge the servers into the "mcp.servers" key of
# ~/.zcode/cli/config.json, using ZCode's strict per-server schema. All other
# keys in an existing config (hooks, plugins, …) survive.
register_mcps_zcode() {
    printf "${BLUE}Writing MCP config into ZCode config.json...${NC}\n"
    ensure_aws_mcp_choice || true
    local resolved config_file="$HOME/.zcode/cli/config.json"
    resolved="$(mcp_resolve zcode)" || return 1
    mcp_merge_json zcode "$config_file" "$resolved" || return 1
    printf "${GREEN}✓ MCP servers written to %s${NC}\n" "$config_file"
}

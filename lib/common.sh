#!/usr/bin/env bash
#
# Shared install library for the macols-configs agentic-CLI installers.
#
# Sourced by install_claudecode.sh / install_codex.sh / install_opencode.sh /
# install_pi.sh. Holds everything those installers have in common: colours,
# Node bootstrap, Homebrew / CLI / jj bootstrap, persona generation, steering
# assembly, ponytail install, MCP registration and hook wiring — all driven
# from the single sources of truth under shared/.
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
SHARED_DIR="$REPO_ROOT/shared"
PERSONAS_DIR="$SHARED_DIR/personas"
STEERING_DIR="$SHARED_DIR/steering"
HOOKS_DIR="$SHARED_DIR/hooks"
MCP_CONFIG_FILE="$SHARED_DIR/mcp-config.json"

# ── Pinned versions ──────────────────────────────────────────────────────────
# Jujutsu (jj) — the single place the version is pinned. Bump here only.
JJ_VERSION="0.43.0"

# Ponytail (https://github.com/DietrichGebert/ponytail) — installed for every
# agent via that agent's native mechanism (Claude Code plugin, omp package,
# AGENTS.md ruleset block). The marker comments delimit the AGENTS.md block so
# re-runs replace it instead of duplicating it.
PONYTAIL_REPO="DietrichGebert/ponytail"
PONYTAIL_MARKER_START="<!-- ponytail:ruleset:start (managed by macols-configs — do not edit between markers) -->"
PONYTAIL_MARKER_END="<!-- ponytail:ruleset:end -->"

# Ensure Node.js is in PATH (sources NVM/fnm if needed). Node powers persona
# generation, steering assembly and the JSON config writers.
if [ -f "$SHARED_DIR/ensure_node.sh" ]; then
    # shellcheck disable=SC1091
    source "$SHARED_DIR/ensure_node.sh"
fi

# ── OS / toolchain bootstrap ─────────────────────────────────────────────────

detect_os() {
    case "$OSTYPE" in
        darwin*) echo "macos" ;;
        linux*)  echo "linux" ;;
        *)       echo "unknown" ;;
    esac
}

# Install Homebrew on macOS if missing. On Linux brew is non-standard, so we
# skip it and rely on the native installers (apt / npm / curl) instead.
ensure_brew() {
    if [ "$(detect_os)" != "macos" ]; then
        return 0
    fi
    if command -v brew &> /dev/null; then
        printf "${GREEN}✓ Homebrew already installed${NC}\n"
        return 0
    fi
    printf "${BLUE}Installing Homebrew...${NC}\n"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

require_node() {
    if ! command -v node &> /dev/null; then
        printf "${RED}Node.js is required but not found. Install Node 18+ and re-run.${NC}\n"
        return 1
    fi
}

# Install jq + uv, which the MCP registration needs.
ensure_mcp_prereqs() {
    if ! command -v jq &> /dev/null; then
        printf "${YELLOW}jq not found. Installing...${NC}\n"
        if [ "$(detect_os)" = "macos" ] && command -v brew &> /dev/null; then
            brew install jq
        elif [ "$(detect_os)" = "linux" ]; then
            sudo apt-get update -y && sudo apt-get install -y jq
        else
            printf "${RED}Please install jq manually: https://jqlang.github.io/jq/${NC}\n"
            return 1
        fi
    fi
    if ! command -v uv &> /dev/null; then
        printf "${YELLOW}uv not found. Installing (needed for uvx-based MCPs)...${NC}\n"
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    fi
}

# ensure_jj — install jujutsu (jj) at the pinned JJ_VERSION and configure it.
#
# Idempotent: skips the download when `jj --version` already reports the pinned
# version. Installs the official prebuilt release binary for this OS/arch into
# ~/.local/bin (no cargo fallback — nothing else here uses cargo). Configuration
# (identity from the git identity these scripts already set, plus
# ui.default-command) is applied on every run; `jj config set` overwrites in
# place, so re-runs are no-ops.
ensure_jj() {
    local os arch target tarball tmpdir bin_dir="$HOME/.local/bin"

    if command -v jj &> /dev/null && jj --version 2>/dev/null | grep -q "$JJ_VERSION"; then
        printf "${GREEN}✓ jj %s already installed${NC}\n" "$JJ_VERSION"
        configure_jj
        return 0
    fi

    case "$(detect_os)" in
        macos) os="apple-darwin" ;;
        linux) os="unknown-linux-musl" ;;
        *) printf "${RED}ensure_jj: unsupported OS for prebuilt jj binaries${NC}\n"; return 1 ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64)  arch="x86_64" ;;
        arm64|aarch64) arch="aarch64" ;;
        *) printf "${RED}ensure_jj: unsupported arch '%s'${NC}\n" "$(uname -m)"; return 1 ;;
    esac
    target="${arch}-${os}"
    tarball="jj-v${JJ_VERSION}-${target}.tar.gz"

    printf "${BLUE}Installing jj %s (%s)...${NC}\n" "$JJ_VERSION" "$target"
    tmpdir=$(mktemp -d)
    if ! curl -fsSL --retry 3 -o "$tmpdir/$tarball" \
        "https://github.com/jj-vcs/jj/releases/download/v${JJ_VERSION}/${tarball}"; then
        rm -rf "$tmpdir"
        printf "${RED}Failed to download jj %s — check network, or install manually: https://jj-vcs.github.io/jj/latest/install-and-setup/${NC}\n" "$JJ_VERSION"
        return 1
    fi
    tar -xzf "$tmpdir/$tarball" -C "$tmpdir"
    local jj_bin
    jj_bin=$(find "$tmpdir" -name jj -type f | head -n1)
    if [ -z "$jj_bin" ]; then
        rm -rf "$tmpdir"
        printf "${RED}jj binary not found inside %s${NC}\n" "$tarball"
        return 1
    fi
    mkdir -p "$bin_dir"
    install -m 0755 "$jj_bin" "$bin_dir/jj"
    rm -rf "$tmpdir"
    export PATH="$bin_dir:$PATH"

    # Persist ~/.local/bin on PATH for future shells (same grep-guarded rc
    # pattern the Terminal scripts use).
    local rc
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        if [ -f "$rc" ] && ! grep -q '\.local/bin' "$rc" 2>/dev/null; then
            # shellcheck disable=SC2016
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
        fi
    done

    printf "${GREEN}✓ Installed jj %s to %s/jj${NC}\n" "$JJ_VERSION" "$bin_dir"
    configure_jj
}

# configure_jj — user-level jj config: reuse the git identity these scripts
# already configure, and default `jj` (bare) to `jj log`. Colocated mode is a
# per-repo choice (`jj git init --colocate`), so nothing global is set for it.
configure_jj() {
    command -v jj &> /dev/null || return 0
    local git_name git_email
    git_name=$(git config --global user.name 2>/dev/null || true)
    git_email=$(git config --global user.email 2>/dev/null || true)
    [ -n "$git_name" ]  && jj config set --user user.name "$git_name"
    [ -n "$git_email" ] && jj config set --user user.email "$git_email"
    jj config set --user ui.default-command log
    printf "${GREEN}✓ jj configured (user.name/user.email from git, ui.default-command=log)${NC}\n"
}

# ensure_node_on_noninteractive_path — ponytail's hooks (and our JSON config
# writers) invoke node outside interactive shells, where NVM/fnm rc wiring
# never loads. Symlink the resolved node/npm/npx into ~/.local/bin, which is on
# PATH for login and agent-spawned shells. Idempotent: ln -sf re-points in place.
ensure_node_on_noninteractive_path() {
    require_node || return 1
    local bin_dir="$HOME/.local/bin" tool src
    mkdir -p "$bin_dir"
    for tool in node npm npx; do
        src=$(command -v "$tool" 2>/dev/null) || continue
        [ "$src" = "$bin_dir/$tool" ] && continue
        ln -sf "$src" "$bin_dir/$tool"
    done
    printf "${GREEN}✓ node/npm/npx linked into %s for non-interactive shells${NC}\n" "$bin_dir"
}

# ensure_cli <claudecode|codex|opencode|pi> — install the CLI binary if missing.
ensure_cli() {
    local tool="$1" os
    os="$(detect_os)"
    case "$tool" in
        claudecode)
            command -v claude &> /dev/null && { printf "${GREEN}✓ claude already installed${NC}\n"; return 0; }
            printf "${BLUE}Installing Claude Code...${NC}\n"
            curl -fsSL https://claude.ai/install.sh | bash
            ;;
        codex)
            command -v codex &> /dev/null && { printf "${GREEN}✓ codex already installed${NC}\n"; return 0; }
            printf "${BLUE}Installing Codex CLI...${NC}\n"
            if [ "$os" = "macos" ] && command -v brew &> /dev/null; then
                brew install --cask codex
            elif command -v npm &> /dev/null; then
                npm install -g @openai/codex
            else
                printf "${RED}Need Homebrew (macOS) or npm to install codex.${NC}\n"; return 1
            fi
            ;;
        opencode)
            command -v opencode &> /dev/null && { printf "${GREEN}✓ opencode already installed${NC}\n"; return 0; }
            printf "${BLUE}Installing OpenCode...${NC}\n"
            if [ "$os" = "macos" ] && command -v brew &> /dev/null; then
                brew install sst/tap/opencode
            elif command -v npm &> /dev/null; then
                npm install -g opencode-ai
            else
                curl -fsSL https://opencode.ai/install | bash
            fi
            ;;
        pi)
            # Oh My Pi (omp) replaces the plain pi agent — both are never
            # provisioned together. The old pi install is kept below,
            # commented out, for reference.
            #
            # command -v pi &> /dev/null && { printf "${GREEN}✓ pi already installed: %s${NC}\n" "$(command -v pi)"; return 0; }
            # printf "${BLUE}Installing pi coding agent...${NC}\n"
            # npm install -g --ignore-scripts @earendil-works/pi-coding-agent && return 0
            # curl -fsSL https://pi.dev/install.sh | sh && return 0
            command -v omp &> /dev/null && omp --version &> /dev/null && { printf "${GREEN}✓ omp already installed: %s${NC}\n" "$(command -v omp)"; return 0; }
            printf "${BLUE}Installing Oh My Pi (omp) coding agent...${NC}\n"
            command -v npm &> /dev/null || { printf "${RED}Need npm to install omp. Install Node.js/npm, then re-run.${NC}\n"; return 1; }
            # omp's npm bundle targets the Bun runtime (engines.bun >= 1.3.14),
            # so make sure a current bun is on PATH first.
            if ! command -v bun &> /dev/null; then
                printf "${BLUE}Installing bun (omp runtime)...${NC}\n"
                npm install -g bun || { printf "${RED}Could not install bun (required by omp).${NC}\n"; return 1; }
            fi
            npm install -g --ignore-scripts @oh-my-pi/pi-coding-agent || { printf "${RED}Could not install omp via npm.${NC}\n"; return 1; }
            if ! omp --version &> /dev/null; then
                # An older pre-existing bun can be too old for omp's bundle —
                # upgrade it and re-check before giving up.
                printf "${YELLOW}omp failed to run; upgrading bun and retrying...${NC}\n"
                npm install -g bun || true
                omp --version &> /dev/null || { printf "${RED}omp installed but does not run — check 'bun --version' (needs >= 1.3.14).${NC}\n"; return 1; }
            fi
            ;;
        *)
            printf "${RED}ensure_cli: unknown tool '%s'${NC}\n" "$tool"; return 1 ;;
    esac
}

# ── Persona generation (single source: shared/personas/<name>/SKILL.md) ───────
#
# One generator emits each tool's native format from the SAME persona body:
#   • skill mode  → Claude/OpenCode/Pi skill (<name>/SKILL.md) or Codex prompt (<name>.md)
#   • agent mode  → Claude/OpenCode agent (<name>.md), only when frontmatter has agent: true
read -r -d '' PERSONA_GEN_JS <<'PERSONA_EOF' || true
const fs = require("fs"), path = require("path");
const mode = process.env.MODE, tool = process.env.TOOL;
const pdir = process.env.PERSONAS_DIR, tdir = process.env.TARGET_DIR;
const DEFAULT_TOOLS = ["Read", "Write", "Edit", "Bash", "Grep", "Glob"];
const OC_MODEL = { opus: "anthropic/claude-opus-4-8", sonnet: "anthropic/claude-sonnet-4-6" };
const OC_AGENT_TOOLS = ["read", "write", "edit", "bash", "grep", "glob"];

function parse(text) {
  const m = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/);
  if (!m) return { data: {}, body: text };
  const data = {}; let cur = null;
  for (const line of m[1].split(/\r?\n/)) {
    const li = line.match(/^\s*-\s+(.*)$/);
    if (li && cur) { (data[cur] = data[cur] || []).push(li[1].trim()); continue; }
    const kv = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (kv) {
      const k = kv[1], v = kv[2];
      if (v === "") { data[k] = []; cur = k; }
      else { data[k] = v === "true" ? true : v === "false" ? false : v; cur = null; }
    }
  }
  return { data, body: m[2] };
}

function fmList(key, items) {
  let o = key + ":\n";
  for (const i of items) o += "  - " + i + "\n";
  return o;
}

function writeDir(dir, name, content) {
  const dest = path.join(dir, name);
  fs.mkdirSync(dest, { recursive: true });
  fs.writeFileSync(path.join(dest, "SKILL.md"), content);
}

let count = 0;
fs.mkdirSync(tdir, { recursive: true });
for (const name of fs.readdirSync(pdir).sort()) {
  const src = path.join(pdir, name, "SKILL.md");
  if (!fs.existsSync(src)) continue;
  const { data, body } = parse(fs.readFileSync(src, "utf8"));
  const pname = data.name || name;
  let label = name;

  if (mode === "skill") {
    let fm = "---\n";
    if (tool === "codex") {
      // Codex custom prompt (slash command): description + argument-hint, no name.
      if (data.description) fm += "description: " + data.description + "\n";
      fm += "argument-hint: \"[task or context]\"\n";
      fm += "---\n";
      fs.writeFileSync(path.join(tdir, name + ".md"), fm + body);
      label = "/" + name;
    } else if (tool === "opencode") {
      if (data.name) fm += "name: " + data.name + "\n";
      if (data.description) fm += "description: " + data.description + "\n";
      fm += "compatibility: opencode\n---\n";
      writeDir(tdir, name, fm + body);
    } else {
      // claudecode / pi Agent Skill.
      fm += "name: " + pname + "\n";
      if (data.description) fm += "description: " + data.description + "\n";
      if (data["allowed-tools"] && data["allowed-tools"].length) fm += fmList("allowed-tools", data["allowed-tools"]);
      if (tool === "claudecode" && data["user-invocable"] !== undefined) fm += "user-invocable: " + data["user-invocable"] + "\n";
      fm += "---\n";
      writeDir(tdir, name, fm + body);
      if (tool === "pi") label = "/skill:" + pname;
    }
    console.log("  ✓ " + label);
    count++;
  } else if (mode === "agent") {
    if (data.agent !== true) continue;
    let fm = "---\n";
    if (tool === "opencode") {
      const model = OC_MODEL[data.model] || OC_MODEL.sonnet;
      fm += "description: " + (data.description || "") + "\n";
      fm += "model: " + model + "\ntools:\n";
      for (const t of OC_AGENT_TOOLS) fm += "  " + t + ": true\n";
      fm += "---\n";
      fs.writeFileSync(path.join(tdir, name + ".md"), fm + body);
    } else {
      // claudecode agent.
      const tools = (data["allowed-tools"] && data["allowed-tools"].length) ? data["allowed-tools"] : DEFAULT_TOOLS;
      fm += "name: " + pname + "\n";
      fm += "description: " + data.description + "\n";
      fm += "tools: " + tools.join(", ") + "\n";
      fm += "model: " + (data.model || "sonnet") + "\n---\n";
      fs.writeFileSync(path.join(tdir, pname + ".md"), fm + body);
    }
    console.log("  ✓ " + pname);
    count++;
  }
}
console.log("__COUNT__" + count);
PERSONA_EOF

# generate_personas <tool> <skill|agent> <target_dir>
# Prints a per-item checklist; sets PERSONA_COUNT to the number generated.
generate_personas() {
    require_node || return 1
    local out
    out=$(TOOL="$1" MODE="$2" PERSONAS_DIR="$PERSONAS_DIR" TARGET_DIR="$3" node -e "$PERSONA_GEN_JS")
    # PERSONA_COUNT is read by the installers that source this file.
    # shellcheck disable=SC2034
    PERSONA_COUNT=$(printf "%s" "$out" | sed -n 's/^__COUNT__//p')
    printf "%s\n" "$out" | grep -v '^__COUNT__'
}

# list_personas <claudecode|codex|opencode|pi>
list_personas() {
    local tool="$1" persona_name description marker
    printf "${BLUE}Available Personas:${NC}\n\n"
    for persona_dir in "$PERSONAS_DIR"/*; do
        [ -d "$persona_dir" ] || continue
        persona_name=$(basename "$persona_dir")
        [ -f "$persona_dir/SKILL.md" ] || continue
        description=$(grep -m1 "^description:" "$persona_dir/SKILL.md" | sed 's/^description: //')
        case "$tool" in
            codex) printf "  ${GREEN}/%-24s${NC} %s\n" "$persona_name" "$description" ;;
            pi)    printf "  ${GREEN}/skill:%-18s${NC} %s\n" "$persona_name" "$description" ;;
            *)
                if grep -q "^agent:[[:space:]]*true" "$persona_dir/SKILL.md"; then marker="${CYAN}+agent${NC}"; else marker="      "; fi
                printf "  ${GREEN}%-25s${NC} %b  %s\n" "$persona_name" "$marker" "$description" ;;
        esac
    done
    echo ""
}

# ── Steering assembly (single source: shared/steering/base.md + tools/<tool>.json)
# assemble_steering <claudecode|codex|opencode|pi> <dest_file>
assemble_steering() {
    require_node || return 1
    local tool="$1" dest="$2"
    local vars="$STEERING_DIR/tools/$tool.json"
    if [ ! -f "$STEERING_DIR/base.md" ] || [ ! -f "$vars" ]; then
        printf "${RED}Steering source missing (base.md or %s)${NC}\n" "$vars"; return 1
    fi
    mkdir -p "$(dirname "$dest")"
    BASE="$STEERING_DIR/base.md" VARS="$vars" DEST="$dest" node -e '
const fs = require("fs");
let out = fs.readFileSync(process.env.BASE, "utf8");
const vars = JSON.parse(fs.readFileSync(process.env.VARS, "utf8"));
for (const [k, v] of Object.entries(vars)) {
    const val = Array.isArray(v) ? v.join("\n") : String(v);
    out = out.split("{{" + k + "}}").join(val);
}
fs.writeFileSync(process.env.DEST, out);
'
    printf "${GREEN}✓ Wrote steering to %s${NC}\n" "$dest"
}

# ── Ponytail (github.com/DietrichGebert/ponytail) ────────────────────────────
# Every agent gets ponytail via its native mechanism: Claude Code as a plugin,
# omp as a package (see install_pi.sh), and the AGENTS.md-driven tools (Codex,
# OpenCode, omp) as a marker-delimited ruleset block appended to AGENTS.md.

# append_ponytail_ruleset <agents_md> — merge ponytail's AGENTS.md ruleset
# (vendored from the upstream repo into shared/steering/ponytail.AGENTS.md)
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

# ── MCP registration (single source: shared/mcp-config.json) ──────────────────

# register_mcps_claude — register every server at user scope via the claude CLI.
register_mcps_claude() {
    printf "${BLUE}Registering MCP servers (Claude Code)...${NC}\n"
    command -v claude &> /dev/null || { printf "${RED}claude CLI not found${NC}\n"; return 1; }
    ensure_mcp_prereqs || return 1
    [ -f "$MCP_CONFIG_FILE" ] || { printf "${RED}MCP config not found: %s${NC}\n" "$MCP_CONFIG_FILE"; return 1; }

    local name server_json
    for name in $(jq -r '.mcpServers | keys[]' "$MCP_CONFIG_FILE"); do
        printf "${BLUE}→ %s${NC}\n" "$name"
        server_json=$(jq --arg name "$name" --arg home "$HOME" \
            '.mcpServers[$name] | walk(if type == "string" then gsub("\\$HOME"; $home) else . end)' \
            "$MCP_CONFIG_FILE")
        claude mcp remove "$name" >/dev/null 2>&1 || true
        if claude mcp add-json -s user "$name" "$server_json" >/dev/null 2>&1; then
            printf "  ${GREEN}✓ registered${NC}\n"
        else
            printf "  ${RED}✗ failed to register${NC}\n"
        fi
    done
    printf "${GREEN}✓ MCP servers registered (run 'claude mcp list' to inspect)${NC}\n"
}

# register_mcps_codex — register every server at user scope via the codex CLI.
register_mcps_codex() {
    printf "${BLUE}Registering MCP servers (Codex)...${NC}\n"
    command -v codex &> /dev/null || { printf "${RED}codex CLI not found${NC}\n"; return 1; }
    ensure_mcp_prereqs || return 1
    [ -f "$MCP_CONFIG_FILE" ] || { printf "${RED}MCP config not found: %s${NC}\n" "$MCP_CONFIG_FILE"; return 1; }

    local name command_bin
    for name in $(jq -r '.mcpServers | keys[]' "$MCP_CONFIG_FILE"); do
        printf "${BLUE}→ %s${NC}\n" "$name"
        local env_flags=() args=()
        while IFS= read -r kv; do [ -z "$kv" ] && continue; env_flags+=(--env "$kv"); done < <(jq -r --arg home "$HOME" --arg name "$name" \
            '.mcpServers[$name].env // {} | to_entries[] | "\(.key)=\(.value | gsub("\\$HOME"; $home))"' "$MCP_CONFIG_FILE")
        command_bin=$(jq -r --arg name "$name" '.mcpServers[$name].command' "$MCP_CONFIG_FILE")
        while IFS= read -r a; do args+=("$a"); done < <(jq -r --arg home "$HOME" --arg name "$name" \
            '.mcpServers[$name].args // [] | .[] | gsub("\\$HOME"; $home)' "$MCP_CONFIG_FILE")
        codex mcp remove "$name" >/dev/null 2>&1 || true
        if codex mcp add "$name" "${env_flags[@]+"${env_flags[@]}"}" -- "$command_bin" "${args[@]+"${args[@]}"}" >/dev/null 2>&1; then
            printf "  ${GREEN}✓ registered${NC}\n"
        else
            printf "  ${RED}✗ failed to register${NC}\n"
        fi
    done
    printf "${GREEN}✓ MCP servers registered (run 'codex mcp list' to inspect)${NC}\n"
}

# register_mcps_opencode — write the "mcp" key into ~/.config/opencode/opencode.json
# (OpenCode reads MCP only from opencode.json; a standalone mcp.json is ignored).
register_mcps_opencode() {
    printf "${BLUE}Writing MCP config into opencode.json...${NC}\n"
    require_node || return 1
    [ -f "$MCP_CONFIG_FILE" ] || { printf "${RED}MCP config not found: %s${NC}\n" "$MCP_CONFIG_FILE"; return 1; }
    local config_dir="$HOME/.config/opencode"
    mkdir -p "$config_dir"
    SRC="$MCP_CONFIG_FILE" OPENCODE_JSON="$config_dir/opencode.json" HOME_DIR="$HOME" node -e '
const fs = require("fs");
const src = JSON.parse(fs.readFileSync(process.env.SRC, "utf8")).mcpServers || {};
const dest = process.env.OPENCODE_JSON;
let cfg = {};
if (fs.existsSync(dest)) { try { cfg = JSON.parse(fs.readFileSync(dest, "utf8")); } catch (e) {} }
const expand = (s) => String(s).split("$HOME").join(process.env.HOME_DIR);
const mcp = {};
for (const [name, s] of Object.entries(src)) {
    const entry = { type: "local", command: [expand(s.command), ...(s.args || []).map(expand)], enabled: true };
    if (s.env) { entry.environment = {}; for (const [k, v] of Object.entries(s.env)) entry.environment[k] = expand(v); }
    mcp[name] = entry;
}
cfg["$schema"] = cfg["$schema"] || "https://opencode.ai/config.json";
cfg.mcp = mcp;
fs.writeFileSync(dest, JSON.stringify(cfg, null, 2) + "\n");
'
    printf "${GREEN}✓ MCP servers written to %s${NC}\n" "$config_dir/opencode.json"
}

# ── Hook wiring ──────────────────────────────────────────────────────────────
# Hooks are referenced in place from shared/hooks (not copied), so the shared
# check libraries resolve correctly via the wrappers' relative path.

CODE_HOOK="$HOOKS_DIR/post_code_hook.sh"
TASK_HOOK="$HOOKS_DIR/post_task_hook.sh"
PRE_DEPLOY_HOOK="$HOOKS_DIR/pre_deploy_hook.sh"
LGTMAYBE_HOOK="$HOOKS_DIR/lgtmaybe_review_hook.sh"

check_hook_sources() {
    local f
    for f in "$SHARED_DIR/checks_common.sh" "$SHARED_DIR/post_code_checks.sh" "$SHARED_DIR/post_task_checks.sh" "$@"; do
        [ -f "$f" ] || { printf "${RED}Required file not found: %s${NC}\n" "$f"; return 1; }
    done
    chmod +x "$@" 2>/dev/null || true
}

# write_claude_hooks <settings_file>
write_claude_hooks() {
    require_node || return 1
    check_hook_sources "$CODE_HOOK" "$TASK_HOOK" "$PRE_DEPLOY_HOOK" "$LGTMAYBE_HOOK" || return 1
    mkdir -p "$(dirname "$1")"
    SETTINGS_FILE="$1" HOOK_SCRIPT="$CODE_HOOK" TASK_HOOK_SCRIPT="$TASK_HOOK" PRE_DEPLOY_HOOK_SCRIPT="$PRE_DEPLOY_HOOK" LGTMAYBE_HOOK_SCRIPT="$LGTMAYBE_HOOK" node -e '
const fs = require("fs"), env = process.env;
let existing = {};
if (fs.existsSync(env.SETTINGS_FILE)) { try { existing = JSON.parse(fs.readFileSync(env.SETTINGS_FILE, "utf8")); } catch (e) {} }
existing.hooks = {
    PreToolUse: [{ matcher: "Bash", hooks: [{ type: "command", command: env.PRE_DEPLOY_HOOK_SCRIPT }] }],
    PostToolUse: [{ matcher: "Edit|Write|NotebookEdit", hooks: [{ type: "command", command: env.HOOK_SCRIPT }] }],
    // Stop runs the fast deterministic battery, then an advisory lgtmaybe LLM review.
    Stop: [{ hooks: [
        { type: "command", command: env.TASK_HOOK_SCRIPT },
        { type: "command", command: env.LGTMAYBE_HOOK_SCRIPT }
    ] }]
};
// Hard safety the model cannot talk itself out of: deny reads of AWS
// credentials. Bypass ("yolo") mode stays available.
existing.permissions = existing.permissions || {};
const deny = new Set(existing.permissions.deny || []);
deny.add("Read(~/.aws/**)"); deny.add("Read(./.aws/**)");
existing.permissions.deny = [...deny];
delete existing.disableBypassPermissionsMode;
fs.writeFileSync(env.SETTINGS_FILE, JSON.stringify(existing, null, 2) + "\n");
'
    printf "${GREEN}✓ Hooks, permissions and safety settings written to %s${NC}\n" "$1"
}

# install_claude_launcher <claude_dir> — install the root-safe launcher that lets
# --dangerously-skip-permissions work by dropping from root to a non-root user
# instead of running the agent as root (which Claude Code refuses).
install_claude_launcher() {
    local dir="$1/bin" src="$REPO_ROOT/bin/claude-launch.sh"
    [ -f "$src" ] || { printf "${RED}launcher source not found: %s${NC}\n" "$src"; return 1; }
    mkdir -p "$dir"
    install -m 0755 "$src" "$dir/claude-launch"
    printf "${GREEN}✓ Installed root-safe launcher to %s/claude-launch${NC}\n" "$dir"
}

# write_codex_hooks <hooks_json>
write_codex_hooks() {
    require_node || return 1
    check_hook_sources "$CODE_HOOK" "$TASK_HOOK" "$PRE_DEPLOY_HOOK" || return 1
    mkdir -p "$(dirname "$1")"
    HOOKS_JSON="$1" HOOK_SCRIPT="$CODE_HOOK" TASK_HOOK_SCRIPT="$TASK_HOOK" PRE_DEPLOY_HOOK_SCRIPT="$PRE_DEPLOY_HOOK" node -e '
const fs = require("fs"), env = process.env;
const config = {
    PreToolUse: [{ matcher: "Bash", hooks: [{ type: "command", command: env.PRE_DEPLOY_HOOK_SCRIPT, timeout: 30 }] }],
    PostToolUse: [{ matcher: "Edit|Write|NotebookEdit", hooks: [{ type: "command", command: env.HOOK_SCRIPT, timeout: 120 }] }],
    Stop: [{ hooks: [{ type: "command", command: env.TASK_HOOK_SCRIPT, timeout: 300 }] }]
};
fs.writeFileSync(env.HOOKS_JSON, JSON.stringify(config, null, 2) + "\n");
'
    printf "${GREEN}✓ Hooks written to %s${NC}\n" "$1"
}

# install_opencode_plugin <plugins_dir>
install_opencode_plugin() {
    check_hook_sources "$CODE_HOOK" "$TASK_HOOK" "$HOOKS_DIR/opencode_post_code_plugin.mjs" || return 1
    mkdir -p "$1"
    rm -f "$1/post_code_hook_plugin.mjs" "$1/post_code_hook_env.mjs"
    sed -e "s|__HOOK_SCRIPT_PATH__|${CODE_HOOK}|g" \
        -e "s|__TASK_HOOK_SCRIPT_PATH__|${TASK_HOOK}|g" \
        "$HOOKS_DIR/opencode_post_code_plugin.mjs" > "$1/post_code_hook_plugin.mjs"
    printf "${GREEN}✓ Plugin installed to %s${NC}\n" "$1/post_code_hook_plugin.mjs"
}

# install_pi_extension <extensions_dir> — bake the repo hooks dir into pi-checks.ts.
install_pi_extension() {
    check_hook_sources "$CODE_HOOK" "$TASK_HOOK" "$HOOKS_DIR/pi-checks.ts" || return 1
    mkdir -p "$1"
    sed "s#__PI_HOOKS_DIR__#$HOOKS_DIR#g" "$HOOKS_DIR/pi-checks.ts" > "$1/pi-checks.ts"
    printf "${GREEN}✓ Extension installed to %s${NC}\n" "$1/pi-checks.ts"
}

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

#!/usr/bin/env bash
#
# Shared install library for the macols-ai-coding-setup agentic-CLI installers.
#
# Sourced by install_claudecode.sh / install_codex.sh / install_opencode.sh /
# install_pi.sh / install_zcode.sh. Holds everything those installers have in
# common: colours, Node bootstrap, Homebrew / CLI bootstrap, persona
# generation, steering assembly, ponytail install, MCP registration and hook
# wiring — all driven from the single sources of truth under shared/.
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
# Shared response-format block: substituted into every tool's steering and
# appended to every rendered persona, so subagents get the same rules.
RESPONSE_FORMAT_FILE="$STEERING_DIR/response-format.md"
HOOKS_DIR="$SHARED_DIR/hooks"
MCP_CONFIG_FILE="$SHARED_DIR/mcp-config.json"
# Brave Search MCP — a second, opt-in MCP source merged in by the OpenCode and
# Oh My Pi writers only, and only when the key file below holds a key. The
# server reads the key from the file (BRAVE_API_KEY_FILE takes precedence over
# BRAVE_API_KEY upstream), so no secret is ever written into a config file.
# Keep BRAVE_KEY_FILE in sync with the path in mcp-config-brave.json.
BRAVE_MCP_CONFIG_FILE="$SHARED_DIR/mcp-config-brave.json"
BRAVE_KEY_FILE="$HOME/.config/macols/brave-api-key"

# ── Pinned versions ──────────────────────────────────────────────────────────
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

# persist_local_bin_path — keep ~/.local/bin on PATH now and for future shells
# (same grep-guarded rc pattern the machine setup scripts use). uv tool shims and
# other user-level binaries land there.
persist_local_bin_path() {
    export PATH="$HOME/.local/bin:$PATH"
    local rc
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        if [ -f "$rc" ] && ! grep -q '\.local/bin' "$rc" 2>/dev/null; then
            # shellcheck disable=SC2016
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
        fi
    done
}

# ensure_openspec — install the OpenSpec CLI (github.com/Fission-AI/openspec)
# used for spec-driven development across every agent. Idempotent: returns
# immediately when the CLI is on PATH. Global npm install (needs Node 20.19+;
# require_node's floor is lower, so a very old Node may still fail — npm will
# say so). Project setup stays manual/per-repo (`openspec init`) — the steering
# teaches agents to use the workflow only where an openspec/ directory exists.
ensure_openspec() {
    if command -v openspec &> /dev/null; then
        printf "${GREEN}✓ openspec already installed${NC}\n"
        return 0
    fi
    printf "${BLUE}Installing OpenSpec CLI (spec-driven development)...${NC}\n"
    command -v npm &> /dev/null || { printf "${RED}Need npm to install openspec. Install Node.js/npm, then re-run.${NC}\n"; return 1; }
    npm install -g @fission-ai/openspec@latest || { printf "${RED}Could not install openspec via npm.${NC}\n"; return 1; }
    if openspec --version &> /dev/null; then
        printf "${GREEN}✓ openspec installed: %s${NC}\n" "$(command -v openspec)"
    else
        printf "${RED}openspec installed but does not run — check 'node --version' (needs >= 20.19).${NC}\n"
        return 1
    fi
}

# ensure_ast_grep — install the ast-grep structural-search CLI used by the
# review persona and the Spec Anchors steering section. Idempotent:
# returns immediately when the CLI is on PATH. Global npm install (the
# @ast-grep/cli package ships both `ast-grep` and `sg` binaries) — npm is the
# one toolchain every installer already bootstraps, whereas brew is not
# guaranteed here (ensure_brew no-ops on Linux). Guard and verify on
# `ast-grep`, never `sg`: Linux ships an unrelated /usr/sbin/sg (setgroups)
# that would false-positive a `command -v sg` check and skip the install.
ensure_ast_grep() {
    if command -v ast-grep &> /dev/null; then
        printf "${GREEN}✓ ast-grep already installed${NC}\n"
        return 0
    fi
    printf "${BLUE}Installing ast-grep CLI (structural code search)...${NC}\n"
    command -v npm &> /dev/null || { printf "${RED}Need npm to install ast-grep. Install Node.js/npm, then re-run.${NC}\n"; return 1; }
    npm install -g @ast-grep/cli@latest || { printf "${RED}Could not install ast-grep via npm.${NC}\n"; return 1; }
    if ast-grep --version &> /dev/null; then
        printf "${GREEN}✓ ast-grep installed: %s${NC}\n" "$(command -v ast-grep)"
    else
        printf "${RED}ast-grep installed but does not run — check 'node --version'.${NC}\n"
        return 1
    fi
}

# ensure_yq — install a yq YAML CLI, used by the spec-anchor drift gate
# (scripts/spec_drift_gate.sh) to convert specs/anchors/*.yml to JSON.
# Idempotent: any flavor on PATH satisfies the guard — the gate's yaml2json
# shim handles both the mikefarah Go yq (brew, GitHub runners) and the
# kislyuk jq-wrapper yq (Ubuntu apt). Same install channels as jq in
# ensure_mcp_prereqs: brew on macOS, apt on Linux.
ensure_yq() {
    if command -v yq &> /dev/null; then
        printf "${GREEN}✓ yq already installed${NC}\n"
        return 0
    fi
    printf "${BLUE}Installing yq (YAML CLI for the spec-anchor drift gate)...${NC}\n"
    if [ "$(detect_os)" = "macos" ] && command -v brew &> /dev/null; then
        brew install yq
    elif [ "$(detect_os)" = "linux" ]; then
        sudo apt-get update -y && sudo apt-get install -y yq
    else
        printf "${RED}Please install yq manually: https://github.com/mikefarah/yq${NC}\n"
        return 1
    fi
    if yq --version &> /dev/null; then
        printf "${GREEN}✓ yq installed: %s${NC}\n" "$(command -v yq)"
    else
        printf "${RED}yq install failed — the spec-anchor drift gate needs it.${NC}\n"
        return 1
    fi
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

# ensure_cli <claudecode|codex|opencode|pi|zcode> — install the CLI binary if missing.
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
            local codex_standalone="$HOME/.codex/packages/standalone/current/codex"
            if [ -x "$codex_standalone" ]; then
                export PATH="$HOME/.codex/packages/standalone/current:$PATH"
                printf "${GREEN}✓ codex standalone already installed${NC}\n"
                return 0
            fi
            printf "${BLUE}Installing Codex CLI...${NC}\n"
            if curl -fsSL https://chatgpt.com/codex/install.sh | sh; then
                export PATH="$HOME/.codex/packages/standalone/current:$PATH"
            elif [ "$os" = "macos" ] && command -v brew &> /dev/null; then
                brew install --cask codex
            elif command -v npm &> /dev/null; then
                npm install -g @openai/codex
            else
                printf "${RED}Need the Codex standalone installer, Homebrew (macOS), or npm to install codex.${NC}\n"; return 1
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
            # Both Pi agents are installed: the plain `pi` CLI (reads
            # ~/.pi/agent) and Oh My Pi `omp` (reads ~/.omp/agent). They share
            # no config directories, so install_pi.sh provisions both layouts.
            command -v npm &> /dev/null || { printf "${RED}Need npm to install the pi agents. Install Node.js/npm, then re-run.${NC}\n"; return 1; }
            if command -v pi &> /dev/null; then
                printf "${GREEN}✓ pi already installed: %s${NC}\n" "$(command -v pi)"
            else
                printf "${BLUE}Installing the Pi coding agent (pi)...${NC}\n"
                npm install -g @earendil-works/pi-coding-agent || { printf "${RED}Could not install pi via npm.${NC}\n"; return 1; }
            fi
            if command -v omp &> /dev/null && omp --version &> /dev/null; then
                printf "${GREEN}✓ omp already installed: %s${NC}\n" "$(command -v omp)"
            else
                printf "${BLUE}Installing Oh My Pi (omp) coding agent...${NC}\n"
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
            fi
            ;;
        zcode)
            # ZCode is a desktop app (Z.ai's GLM harness), not a
            # package-managed CLI. Config-only: verify the app bundle exists
            # and warn non-fatally when it doesn't — nothing is downloaded.
            local app
            for app in "/Applications/ZCode.app" "$HOME/Applications/ZCode.app"; do
                if [ -d "$app" ]; then
                    printf "${GREEN}✓ ZCode app found: %s${NC}\n" "$app"
                    return 0
                fi
            done
            printf "${YELLOW}⚠ ZCode.app not found — its configs will be written, but install the ZCode app (https://z.ai) to use them${NC}\n"
            ;;
        *)
            printf "${RED}ensure_cli: unknown tool '%s'${NC}\n" "$tool"; return 1 ;;
    esac
}

# handle_common_install_flag — process flags shared by every install_<tool>.sh.
# Returns 0 when it consumed the flag (-h/--help, --no-cli, -p/--project), else 1
# so the caller's loop handles its tool-specific flags. Relies on the caller
# having defined `usage` and the DO_CLI / PROJECT_INSTALL vars before parsing.
# shellcheck disable=SC2034  # DO_CLI/PROJECT_INSTALL are consumed by the install scripts that source this
handle_common_install_flag() {
    case "$1" in
        -h|--help)     usage; exit 0 ;;
        --no-cli)      DO_CLI=false; return 0 ;;
        -p|--project)  PROJECT_INSTALL=true; DO_CLI=false; return 0 ;;
        *)             return 1 ;;
    esac
}

# ── Persona generation (single source: shared/personas/<name>/SKILL.md) ───────
#
# One generator emits each tool's native format from the SAME persona body:
#   • skill mode   → Claude/OpenCode/Pi/Codex/ZCode Agent Skill (<name>/SKILL.md)
#   • command mode → ZCode slash command (<name>.md, description + argument-hint)
#   • agent mode   → Claude/OpenCode agent (<name>.md) or Codex agent (<name>.toml),
#                    only when frontmatter has agent: true
# (Codex custom prompts were removed upstream in favour of Agent Skills, so
# there is no prompt mode any more; command mode is ZCode's own slash-command
# shape.)
#
# A persona body may reference shared partials with {{include: _shared/<file>.md}}
# (paths relative to shared/personas/). Partials are inlined before emission so
# every rendered form — skill, command or agent, any tool — is self-contained.
# Directories starting with "_" hold partials, not personas, and need no SKILL.md.
read -r -d '' PERSONA_GEN_JS <<'PERSONA_EOF' || true
const fs = require("fs"), path = require("path");
const mode = process.env.MODE, tool = process.env.TOOL;
const pdir = process.env.PERSONAS_DIR, tdir = process.env.TARGET_DIR;
// Appended to every persona body so agents and skills carry the same response
// rules as the assembled steering. Source: shared/steering/response-format.md.
const RESPONSE_FORMAT = fs.readFileSync(process.env.RESPONSE_FORMAT_FILE, "utf8").trim();
const DEFAULT_TOOLS = ["Read", "Write", "Edit", "Bash", "Grep", "Glob"];

function applyIncludes(body) {
  return body.replace(/\{\{include:\s*([^}\s]+)\s*\}\}/g, (_, rel) => {
    const file = path.join(pdir, rel);
    if (!fs.existsSync(file)) throw new Error("include not found: " + rel);
    return fs.readFileSync(file, "utf8").trim();
  });
}

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
  const parsed = parse(fs.readFileSync(src, "utf8"));
  const data = parsed.data;
  const body = applyIncludes(parsed.body).trimEnd() + "\n\n" + RESPONSE_FORMAT + "\n";
  const pname = data.name || name;
  let label = name;

  if (mode === "command") {
    // ZCode slash command (~/.zcode/commands/<name>.md): the filename is the
    // command name; frontmatter carries description + argument-hint.
    let fm = "---\n";
    if (data.description) fm += "description: " + data.description + "\n";
    fm += "argument-hint: \"[task or context]\"\n";
    fm += "---\n";
    fs.writeFileSync(path.join(tdir, name + ".md"), fm + body);
    console.log("  ✓ /" + name);
    count++;
  } else if (mode === "skill") {
    let fm = "---\n";
    if (tool === "codex") {
      // Codex Agent Skill (~/.codex/skills/<name>/SKILL.md): name + description
      // only — Codex ignores Claude-specific keys like allowed-tools.
      fm += "name: " + pname + "\n";
      if (data.description) fm += "description: " + data.description + "\n";
      fm += "---\n";
      writeDir(tdir, name, fm + body);
    } else if (tool === "zcode") {
      // ZCode Agent Skill (~/.zcode/skills/<name>/SKILL.md): name +
      // description only — both are required or ZCode drops the skill, and
      // Claude-specific keys are best avoided.
      fm += "name: " + pname + "\n";
      if (data.description) fm += "description: " + data.description + "\n";
      fm += "---\n";
      writeDir(tdir, name, fm + body);
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
    if (tool === "codex") {
      // Codex custom agent (~/.codex/agents/<name>.toml). Required fields:
      // name, description, developer_instructions. As for all rendered
      // agents, model is omitted — personas are model-agnostic and agents
      // inherit the parent session's model. Instructions use a TOML
      // literal block (no escape processing); fall back to an escaped basic
      // string if the body ever contains the ''' delimiter.
      const b = body.endsWith("\n") ? body : body + "\n";
      let doc = "name = " + JSON.stringify(pname) + "\n";
      doc += "description = " + JSON.stringify(data.description || "") + "\n";
      if (b.includes("'''")) doc += "developer_instructions = " + JSON.stringify(b) + "\n";
      else doc += "developer_instructions = '''\n" + b + "'''\n";
      fs.writeFileSync(path.join(tdir, pname + ".toml"), doc);
    } else if (tool === "opencode") {
      // No model: (inherits the session's model) and no tools: map — the
      // boolean tool map is deprecated in OpenCode; the default toolset
      // applies, and per-tool restrictions belong in `permission` config.
      fm += "description: " + (data.description || "") + "\n---\n";
      fs.writeFileSync(path.join(tdir, name + ".md"), fm + body);
    } else {
      // claudecode agent.
      const tools = (data["allowed-tools"] && data["allowed-tools"].length) ? data["allowed-tools"] : DEFAULT_TOOLS;
      fm += "name: " + pname + "\n";
      fm += "description: " + data.description + "\n";
      fm += "tools: " + tools.join(", ") + "\n---\n";
      fs.writeFileSync(path.join(tdir, pname + ".md"), fm + body);
    }
    console.log("  ✓ " + pname);
    count++;
  }
}
console.log("__COUNT__" + count);
PERSONA_EOF

# generate_personas <tool> <skill|command|agent> <target_dir>
# Prints a per-item checklist; sets PERSONA_COUNT to the number generated.
generate_personas() {
    require_node || return 1
    local out
    [ -f "$RESPONSE_FORMAT_FILE" ] || {
        printf "${RED}Response-format source missing (%s)${NC}\n" "$RESPONSE_FORMAT_FILE"; return 1
    }
    out=$(TOOL="$1" MODE="$2" PERSONAS_DIR="$PERSONAS_DIR" TARGET_DIR="$3" \
        RESPONSE_FORMAT_FILE="$RESPONSE_FORMAT_FILE" node -e "$PERSONA_GEN_JS")
    # PERSONA_COUNT is read by the installers that source this file.
    # shellcheck disable=SC2034
    PERSONA_COUNT=$(printf "%s" "$out" | sed -n 's/^__COUNT__//p')
    printf "%s\n" "$out" | grep -v '^__COUNT__'
}

# list_personas <claudecode|codex|opencode|pi|zcode>
list_personas() {
    local tool="$1" persona_name description marker
    printf "${BLUE}Available Personas:${NC}\n\n"
    for persona_dir in "$PERSONAS_DIR"/*; do
        [ -d "$persona_dir" ] || continue
        persona_name=$(basename "$persona_dir")
        [ -f "$persona_dir/SKILL.md" ] || continue
        description=$(grep -m1 "^description:" "$persona_dir/SKILL.md" | sed 's/^description: //')
        case "$tool" in
            codex)
                if grep -q "^agent:[[:space:]]*true" "$persona_dir/SKILL.md"; then marker="${CYAN}+agent${NC}"; else marker="      "; fi
                printf "  ${GREEN}/%-24s${NC} %b  %s\n" "$persona_name" "$marker" "$description" ;;
            pi)    printf "  ${GREEN}/skill:%-18s${NC} %s\n" "$persona_name" "$description" ;;
            zcode) printf "  ${GREEN}/%-24s${NC} %s\n" "$persona_name" "$description" ;;
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

# ── Brave Search API key ─────────────────────────────────────────────────────

# ensure_brave_api_key — make sure a Brave Search API key is on disk so the
# brave-search MCP can be registered (OpenCode and omp only).
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

# brave_mcp_source — echo the Brave MCP config path when a key is configured,
# nothing otherwise. The OpenCode and omp writers pass the result through as
# SRC_EXTRA, so brave-search is registered only when it can actually work.
brave_mcp_source() {
    if [ -s "$BRAVE_KEY_FILE" ] && [ -f "$BRAVE_MCP_CONFIG_FILE" ]; then
        printf '%s' "$BRAVE_MCP_CONFIG_FILE"
    fi
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
# The optional brave-search server is merged in on top of the shared config
# when a Brave API key is configured (see brave_mcp_source).
register_mcps_opencode() {
    printf "${BLUE}Writing MCP config into opencode.json...${NC}\n"
    require_node || return 1
    [ -f "$MCP_CONFIG_FILE" ] || { printf "${RED}MCP config not found: %s${NC}\n" "$MCP_CONFIG_FILE"; return 1; }
    local config_dir="$HOME/.config/opencode"
    mkdir -p "$config_dir"
    SRC="$MCP_CONFIG_FILE" SRC_EXTRA="$(brave_mcp_source)" OPENCODE_JSON="$config_dir/opencode.json" HOME_DIR="$HOME" node -e '
const fs = require("fs");
const read = (p) => JSON.parse(fs.readFileSync(p, "utf8")).mcpServers || {};
const src = { ...read(process.env.SRC), ...(process.env.SRC_EXTRA ? read(process.env.SRC_EXTRA) : {}) };
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

# register_mcps_pi <agent_dir> — write the "mcpServers" key into <agent_dir>/mcp.json.
# Oh My Pi reads MCP config from ~/.omp/agent/mcp.json in the same
# {"mcpServers": {...}} shape as shared/mcp-config.json; other keys in the
# file (e.g. disabledServers) are preserved. The optional brave-search server
# is merged in when a Brave API key is configured (see brave_mcp_source).
register_mcps_pi() {
    printf "${BLUE}Writing MCP config into mcp.json...${NC}\n"
    require_node || return 1
    [ -f "$MCP_CONFIG_FILE" ] || { printf "${RED}MCP config not found: %s${NC}\n" "$MCP_CONFIG_FILE"; return 1; }
    mkdir -p "$1"
    SRC="$MCP_CONFIG_FILE" SRC_EXTRA="$(brave_mcp_source)" PI_MCP_JSON="$1/mcp.json" HOME_DIR="$HOME" node -e '
const fs = require("fs");
const read = (p) => JSON.parse(fs.readFileSync(p, "utf8")).mcpServers || {};
const src = { ...read(process.env.SRC), ...(process.env.SRC_EXTRA ? read(process.env.SRC_EXTRA) : {}) };
const dest = process.env.PI_MCP_JSON;
let cfg = {};
if (fs.existsSync(dest)) { try { cfg = JSON.parse(fs.readFileSync(dest, "utf8")); } catch (e) {} }
const expand = (s) => String(s).split("$HOME").join(process.env.HOME_DIR);
const servers = {};
for (const [name, s] of Object.entries(src)) {
    const entry = { command: expand(s.command), args: (s.args || []).map(expand) };
    if (s.env) { entry.env = {}; for (const [k, v] of Object.entries(s.env)) entry.env[k] = expand(v); }
    servers[name] = entry;
}
cfg.mcpServers = servers;
fs.writeFileSync(dest, JSON.stringify(cfg, null, 2) + "\n");
'
    printf "${GREEN}✓ MCP servers written to %s${NC}\n" "$1/mcp.json"
}

# register_mcps_zcode — merge the servers into the "mcp.servers" key of
# ~/.zcode/cli/config.json. ZCode's per-server schema is strict (an unknown
# key silently drops the whole server), so each entry carries only
# type/command/args/env/enabled. All other keys in an existing config
# (hooks, plugins, …) survive.
register_mcps_zcode() {
    printf "${BLUE}Writing MCP config into ZCode config.json...${NC}\n"
    require_node || return 1
    [ -f "$MCP_CONFIG_FILE" ] || { printf "${RED}MCP config not found: %s${NC}\n" "$MCP_CONFIG_FILE"; return 1; }
    local config_file="$HOME/.zcode/cli/config.json"
    mkdir -p "$(dirname "$config_file")"
    SRC="$MCP_CONFIG_FILE" ZCODE_JSON="$config_file" HOME_DIR="$HOME" node -e '
const fs = require("fs");
const src = JSON.parse(fs.readFileSync(process.env.SRC, "utf8")).mcpServers || {};
const dest = process.env.ZCODE_JSON;
let cfg = {};
if (fs.existsSync(dest)) { try { cfg = JSON.parse(fs.readFileSync(dest, "utf8")); } catch (e) {} }
const expand = (s) => String(s).split("$HOME").join(process.env.HOME_DIR);
const servers = {};
for (const [name, s] of Object.entries(src)) {
    const entry = { type: "stdio", command: expand(s.command), args: (s.args || []).map(expand), enabled: true };
    if (s.env) { entry.env = {}; for (const [k, v] of Object.entries(s.env)) entry.env[k] = expand(v); }
    servers[name] = entry;
}
cfg.mcp = cfg.mcp || {};
cfg.mcp.servers = Object.assign({}, cfg.mcp.servers, servers);
fs.writeFileSync(dest, JSON.stringify(cfg, null, 2) + "\n");
'
    printf "${GREEN}✓ MCP servers written to %s${NC}\n" "$config_file"
}

# ── Oh My Pi model + provider setup ──────────────────────────────────────────
#
# omp resolves which model runs from two user-owned YAML files in its agent
# dir (plain pi has no equivalent, so this is omp-only):
#
#   models.yml  {"providers": {"<name>": {baseUrl, api, apiKey, models: [...]}}}
#   config.yml  {"modelRoles": {"default": "<provider>/<model-id>", ...}}
#
# `modelRoles.default` is the model omp starts a session on; `modelRoles.plan`
# is the one it plans with. Both take a `<provider>/<model-id>` selector, and
# the provider is either one omp already ships (anthropic, openai, zai, …) or
# one described in models.yml — an OpenAI-compatible endpoint such as vLLM,
# Ollama, LM Studio or LiteLLM.
#
# Both files are user-owned, so every write here merges: other providers,
# other roles and every unrelated setting survive. YAML comments do not — the
# files are re-serialised, which is also what omp itself does when it saves
# settings.
#
# Secrets never land in the config. An API key is written to a mode-600 file
# under $OMP_KEY_DIR and referenced from models.yml as `!cat '<path>'`, which
# omp resolves by running the command (a bare value is also read as an
# environment variable name before falling back to a literal).
OMP_KEY_DIR="$HOME/.config/macols"

# Bundled providers worth suggesting. Not a closed list — any provider id omp
# knows, or any name already in models.yml, is accepted at the prompt.
OMP_KNOWN_PROVIDERS="anthropic openai openai-codex zai google google-gemini-cli openrouter cerebras groq xai mistral deepseek moonshot github-copilot ollama"

# require_bun — the YAML readers/writers below run on Bun, which omp already
# needs as its runtime (ensure_cli pi installs it), so this adds no dependency.
require_bun() {
    if ! command -v bun &> /dev/null; then
        printf "${RED}bun is required for omp model setup but was not found.${NC}\n"
        return 1
    fi
}

# omp_model_role <agent_dir> <role> — print the model selector currently
# assigned to <role> in config.yml, or nothing when unset.
omp_model_role() {
    local f
    for f in "$1/config.yml" "$1/config.yaml"; do
        [ -f "$f" ] || continue
        OMP_FILE="$f" OMP_ROLE="$2" bun -e '
import { YAML } from "bun";
const doc = YAML.parse(await Bun.file(process.env.OMP_FILE).text()) || {};
const v = doc?.modelRoles?.[process.env.OMP_ROLE];
if (typeof v === "string" && v) process.stdout.write(v);
' 2>/dev/null
        return 0
    done
}

# omp_set_model_role <agent_dir> <role> <selector> — assign one model role in
# config.yml, leaving every other role and setting in place.
omp_set_model_role() {
    require_bun || return 1
    mkdir -p "$1"
    OMP_DIR="$1" OMP_ROLE="$2" OMP_SELECTOR="$3" bun -e '
import { YAML } from "bun";
import * as fs from "node:fs";
import * as path from "node:path";
const dir = process.env.OMP_DIR;
// omp reads config.yml first and falls back to config.yaml, so edit whichever
// one it would actually load.
const file = fs.existsSync(path.join(dir, "config.yml")) || !fs.existsSync(path.join(dir, "config.yaml"))
    ? path.join(dir, "config.yml")
    : path.join(dir, "config.yaml");
let doc = {};
if (fs.existsSync(file)) { try { doc = YAML.parse(fs.readFileSync(file, "utf8")) || {}; } catch (e) {} }
doc.modelRoles = { ...(doc.modelRoles ?? {}), [process.env.OMP_ROLE]: process.env.OMP_SELECTOR };
fs.writeFileSync(file, YAML.stringify(doc, null, 2) + "\n");
' || return 1
    printf "${GREEN}  ✓ modelRoles.%s = %s${NC}\n" "$2" "$3"
}

# omp_register_provider <agent_dir> — merge one provider into models.yml from
# the OMP_PROVIDER_* environment. Fields:
#   OMP_PROVIDER_NAME            provider id (required)
#   OMP_PROVIDER_BASE_URL        endpoint, required when a model is defined
#   OMP_PROVIDER_API             wire protocol, e.g. openai-completions
#   OMP_PROVIDER_KEY_REF         apiKey value (a `!cat …` command, an env var
#                                name or a literal); empty means `auth: none`
#   OMP_PROVIDER_MODEL_ID        model to add; empty registers the key alone,
#                                which is how a bundled provider is credentialed
#   OMP_PROVIDER_CONTEXT_WINDOW  optional context window in tokens
#   OMP_PROVIDER_REASONING       "true" to mark the model as a reasoning model
#   OMP_PROVIDER_FREE            "true" to record zero cost (self-hosted)
# An existing provider keeps its other models and settings; a model with the
# same id is replaced rather than duplicated, so re-runs converge.
omp_register_provider() {
    require_bun || return 1
    mkdir -p "$1"
    OMP_DIR="$1" bun -e '
import { YAML, JSONC } from "bun";
import * as fs from "node:fs";
import * as path from "node:path";
const env = process.env;
const dir = env.OMP_DIR;
const yml = path.join(dir, "models.yml");
const yaml = path.join(dir, "models.yaml");
const file = fs.existsSync(yml) || !fs.existsSync(yaml) ? yml : yaml;
let doc = {};
if (fs.existsSync(file)) {
    try { doc = YAML.parse(fs.readFileSync(file, "utf8")) || {}; } catch (e) {}
} else if (fs.existsSync(path.join(dir, "models.json"))) {
    // omp migrates a legacy models.json to models.yml on first load. Writing
    // models.yml here pre-empts that migration, so carry the old file over
    // instead of orphaning it.
    try { doc = JSONC.parse(fs.readFileSync(path.join(dir, "models.json"), "utf8")) || {}; } catch (e) {}
}
doc.providers ??= {};
const provider = (doc.providers[env.OMP_PROVIDER_NAME] ??= {});
if (env.OMP_PROVIDER_BASE_URL) provider.baseUrl = env.OMP_PROVIDER_BASE_URL;
if (env.OMP_PROVIDER_API) provider.api = env.OMP_PROVIDER_API;
if (env.OMP_PROVIDER_KEY_REF) {
    provider.apiKey = env.OMP_PROVIDER_KEY_REF;
    delete provider.auth;
} else if (env.OMP_PROVIDER_MODEL_ID && !provider.apiKey) {
    // Defining models without a key is only valid when auth is opted out of.
    provider.auth = "none";
}
if (env.OMP_PROVIDER_MODEL_ID) {
    const model = { id: env.OMP_PROVIDER_MODEL_ID };
    if (env.OMP_PROVIDER_REASONING === "true") model.reasoning = true;
    if (env.OMP_PROVIDER_CONTEXT_WINDOW) model.contextWindow = Number(env.OMP_PROVIDER_CONTEXT_WINDOW);
    if (env.OMP_PROVIDER_FREE === "true") model.cost = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
    provider.models = [...(provider.models ?? []).filter(m => m?.id !== model.id), model];
}
fs.writeFileSync(file, YAML.stringify(doc, null, 2) + "\n");
' || return 1
    printf "${GREEN}  ✓ provider %s written${NC}\n" "$OMP_PROVIDER_NAME"
}

# omp_merge_models_config <agent_dir> <file> — merge the providers from a
# models.yml-shaped YAML or JSON file. The unattended path: point
# OMP_MODELS_CONFIG at a file and no questions are asked.
omp_merge_models_config() {
    require_bun || return 1
    [ -f "$2" ] || { printf "${RED}models config not found: %s${NC}\n" "$2"; return 1; }
    mkdir -p "$1"
    OMP_DIR="$1" OMP_SRC="$2" bun -e '
import { YAML, JSONC } from "bun";
import * as fs from "node:fs";
import * as path from "node:path";
const parse = (p) => (p.endsWith(".json") || p.endsWith(".jsonc") ? JSONC : YAML).parse(fs.readFileSync(p, "utf8")) || {};
const dir = process.env.OMP_DIR;
const yml = path.join(dir, "models.yml");
const yaml = path.join(dir, "models.yaml");
const file = fs.existsSync(yml) || !fs.existsSync(yaml) ? yml : yaml;
let doc = {};
if (fs.existsSync(file)) { try { doc = YAML.parse(fs.readFileSync(file, "utf8")) || {}; } catch (e) {} }
const src = parse(process.env.OMP_SRC);
doc.providers = { ...(doc.providers ?? {}), ...(src.providers ?? {}) };
fs.writeFileSync(file, YAML.stringify(doc, null, 2) + "\n");
' || return 1
    printf "${GREEN}  ✓ providers from %s merged${NC}\n" "$2"
}

# ensure_omp_provider_key <provider> — ask for an API key and stash it in a
# mode-600 file, setting OMP_KEY_REF to the `!cat …` reference models.yml
# should carry. OMP_KEY_REF is left empty when the user skips (a provider that
# needs no key, or one already authenticated with `omp /login <provider>`).
# An existing key file short-circuits, so re-runs never re-prompt.
ensure_omp_provider_key() {
    OMP_KEY_REF=""
    local provider="$1" key_file="$OMP_KEY_DIR/omp-$1-api-key" key
    if [ -s "$key_file" ]; then
        printf "${GREEN}  ✓ API key already configured (%s)${NC}\n" "$key_file"
        OMP_KEY_REF="!cat '$key_file'"
        return 0
    fi
    read -rsp "$(printf "${YELLOW}  API key for %s (blank to skip — the endpoint needs none, or you use 'omp /login %s'): ${NC}" "$provider" "$provider")" key || true
    echo ""
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    [ -n "$key" ] || return 0
    mkdir -p "$OMP_KEY_DIR"
    (umask 077; printf '%s\n' "$key" > "$key_file")
    chmod 600 "$key_file"
    OMP_KEY_REF="!cat '$key_file'"
    printf "${GREEN}  ✓ key saved to %s (mode 600) and referenced, not inlined${NC}\n" "$key_file"
}

# omp_configure_role <agent_dir> <role> <label> — ask which model fills one
# role and write it. Three ways out: a provider omp already knows (or one
# configured earlier in this run), a new OpenAI-compatible endpoint, or skip.
# Every `read` ends in `|| true` because the installers run under `set -e`:
# EOF (Ctrl-D) at a prompt should fall through to that prompt's default —
# leaving the role as-is — not abort the install part-way through a provider.
omp_configure_role() {
    local dir="$1" role="$2" label="$3" current choice
    local provider model_id base_url api ctx reasoning
    current="$(omp_model_role "$dir" "$role")"

    printf "\n${CYAN}%s model (modelRoles.%s)${NC}\n" "$label" "$role"
    [ -n "$current" ] && printf "  currently: %s\n" "$current"
    printf "  1) A provider omp knows — %s\n" "$OMP_KNOWN_PROVIDERS"
    printf "  2) An OpenAI-compatible endpoint — vLLM, Ollama, LM Studio, LiteLLM, any gateway\n"
    printf "  3) Leave as-is (omp picks from its own priority list)\n"
    read -rp "$(printf "${YELLOW}  Choice [3]: ${NC}")" choice || true

    case "${choice:-3}" in
        1)
            read -rp "$(printf "${YELLOW}  Provider id: ${NC}")" provider || true
            [ -n "$provider" ] || { printf "${YELLOW}  ⚠ no provider given — %s left as-is${NC}\n" "$role"; return 0; }
            read -rp "$(printf "${YELLOW}  Model id (e.g. claude-opus-4-5, gpt-5.5, glm-5.2): ${NC}")" model_id || true
            [ -n "$model_id" ] || { printf "${YELLOW}  ⚠ no model given — %s left as-is${NC}\n" "$role"; return 0; }
            ensure_omp_provider_key "$provider"
            if [ -n "$OMP_KEY_REF" ]; then
                # Key only: the model itself comes from omp's bundled catalog,
                # so no baseUrl/models entry is needed (or wanted — it would
                # override the catalog's own definition).
                OMP_PROVIDER_NAME="$provider" OMP_PROVIDER_BASE_URL="" OMP_PROVIDER_API="" \
                OMP_PROVIDER_KEY_REF="$OMP_KEY_REF" OMP_PROVIDER_MODEL_ID="" \
                OMP_PROVIDER_CONTEXT_WINDOW="" OMP_PROVIDER_REASONING="" OMP_PROVIDER_FREE="" \
                    omp_register_provider "$dir" || return 1
            fi
            ;;
        2)
            read -rp "$(printf "${YELLOW}  Name for this provider (e.g. vllm-lan, ollama-local): ${NC}")" provider || true
            [ -n "$provider" ] || { printf "${YELLOW}  ⚠ no name given — %s left as-is${NC}\n" "$role"; return 0; }
            read -rp "$(printf "${YELLOW}  Base URL (vLLM http://host:8000/v1, Ollama http://localhost:11434/v1, LM Studio http://localhost:1234/v1): ${NC}")" base_url || true
            [ -n "$base_url" ] || { printf "${YELLOW}  ⚠ no base URL given — %s left as-is${NC}\n" "$role"; return 0; }
            read -rp "$(printf "${YELLOW}  Wire protocol [openai-completions]: ${NC}")" api || true
            read -rp "$(printf "${YELLOW}  Model id (as the endpoint reports it, e.g. unsloth/Qwen3.8-27B-NVFP4): ${NC}")" model_id || true
            [ -n "$model_id" ] || { printf "${YELLOW}  ⚠ no model given — %s left as-is${NC}\n" "$role"; return 0; }
            read -rp "$(printf "${YELLOW}  Context window in tokens (blank to leave to omp): ${NC}")" ctx || true
            read -rp "$(printf "${YELLOW}  Is it a reasoning model? [y/N]: ${NC}")" reasoning || true
            ensure_omp_provider_key "$provider"
            case "$reasoning" in [Yy]*) reasoning=true ;; *) reasoning=false ;; esac
            OMP_PROVIDER_NAME="$provider" OMP_PROVIDER_BASE_URL="$base_url" \
            OMP_PROVIDER_API="${api:-openai-completions}" OMP_PROVIDER_KEY_REF="$OMP_KEY_REF" \
            OMP_PROVIDER_MODEL_ID="$model_id" OMP_PROVIDER_CONTEXT_WINDOW="$ctx" \
            OMP_PROVIDER_REASONING="$reasoning" OMP_PROVIDER_FREE="true" \
                omp_register_provider "$dir" || return 1
            printf "${YELLOW}  ⚠ cost recorded as 0 — edit models.yml if this endpoint bills you${NC}\n"
            ;;
        *)
            printf "  left as-is\n"
            return 0
            ;;
    esac

    omp_set_model_role "$dir" "$role" "$provider/$model_id"
}

# configure_omp_models <agent_dir> — set omp's default and planning models.
#
# Interactive by default. Unattended callers get the same result without
# questions from OMP_MODELS_CONFIG (a models.yml-shaped YAML/JSON file of
# providers) plus OMP_DEFAULT_MODEL / OMP_PLAN_MODEL (`<provider>/<model-id>`
# selectors). Set OMP_RECONFIGURE_MODELS=true to re-ask once the roles are
# already assigned — that is what `--models-only` does.
configure_omp_models() {
    local dir="$1"
    require_bun || return 1

    if [ -n "${OMP_MODELS_CONFIG:-}" ]; then
        omp_merge_models_config "$dir" "$OMP_MODELS_CONFIG" || return 1
    fi
    if [ -n "${OMP_DEFAULT_MODEL:-}" ]; then
        omp_set_model_role "$dir" default "$OMP_DEFAULT_MODEL" || return 1
    fi
    if [ -n "${OMP_PLAN_MODEL:-}" ]; then
        omp_set_model_role "$dir" plan "$OMP_PLAN_MODEL" || return 1
    fi
    # Anything supplied by environment is the whole answer — don't then ask.
    if [ -n "${OMP_MODELS_CONFIG:-}${OMP_DEFAULT_MODEL:-}${OMP_PLAN_MODEL:-}" ]; then
        return 0
    fi

    if [ "${OMP_RECONFIGURE_MODELS:-false}" != true ] && [ -n "$(omp_model_role "$dir" default)" ]; then
        printf "${GREEN}✓ omp models already configured (%s/config.yml) — re-run with --models-only to change them${NC}\n" "$dir"
        return 0
    fi
    if [ ! -t 0 ]; then
        printf "${YELLOW}⚠ Non-interactive install — set OMP_DEFAULT_MODEL / OMP_PLAN_MODEL (and OMP_MODELS_CONFIG for a custom endpoint) to configure omp models${NC}\n"
        return 0
    fi

    printf "${BLUE}Oh My Pi model setup — which model omp runs on, and which it plans with.${NC}\n"
    printf "${BLUE}Both are stored in %s (providers) and %s (roles).${NC}\n" "$dir/models.yml" "$dir/config.yml"
    omp_configure_role "$dir" default "Default" || return 1
    omp_configure_role "$dir" plan "Planning" || return 1
}

# ── Hook wiring ──────────────────────────────────────────────────────────────
# Hooks are referenced in place from shared/hooks (not copied), so the shared
# check libraries resolve correctly via the wrappers' relative path.

CODE_HOOK="$HOOKS_DIR/post_code_hook.sh"
TASK_HOOK="$HOOKS_DIR/post_task_hook.sh"
PRE_DEPLOY_HOOK="$HOOKS_DIR/pre_deploy_hook.sh"
PRE_DEPLOY_CHECK="$HOOKS_DIR/pre_deploy_check.sh"

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
    check_hook_sources "$CODE_HOOK" "$TASK_HOOK" "$PRE_DEPLOY_HOOK" || return 1
    mkdir -p "$(dirname "$1")"
    SETTINGS_FILE="$1" HOOK_SCRIPT="$CODE_HOOK" TASK_HOOK_SCRIPT="$TASK_HOOK" PRE_DEPLOY_HOOK_SCRIPT="$PRE_DEPLOY_HOOK" node -e '
const fs = require("fs"), env = process.env;
let existing = {};
if (fs.existsSync(env.SETTINGS_FILE)) { try { existing = JSON.parse(fs.readFileSync(env.SETTINGS_FILE, "utf8")); } catch (e) {} }
existing.hooks = {
    PreToolUse: [{ matcher: "Bash", hooks: [{ type: "command", command: env.PRE_DEPLOY_HOOK_SCRIPT }] }],
    PostToolUse: [{ matcher: "Edit|Write|NotebookEdit", hooks: [{ type: "command", command: env.HOOK_SCRIPT }] }],
    Stop: [{ hooks: [
        { type: "command", command: env.TASK_HOOK_SCRIPT }
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
// Codex deserialises hooks.json into a struct with deny_unknown_fields that
// accepts only "description" and "hooks". The event map is nested under
// "hooks" — a Claude-style flat file fails with `unknown field PreToolUse`.
// Matchers: Codex maps its apply_patch tool onto the Write/Edit aliases, so
// the Claude-style matcher strings select the same edits.
const config = {
    description: "macols-ai-coding-setup advisory quality and safety hooks",
    hooks: {
        PreToolUse: [{ matcher: "Bash", hooks: [{ type: "command", command: env.PRE_DEPLOY_HOOK_SCRIPT, timeout: 30 }] }],
        PostToolUse: [{ matcher: "Edit|Write", hooks: [{ type: "command", command: env.HOOK_SCRIPT, timeout: 120 }] }],
        // Stop mirrors Claude: the deterministic post-task battery.
        Stop: [{ hooks: [
            { type: "command", command: env.TASK_HOOK_SCRIPT, timeout: 300 }
        ] }]
    }
};
fs.writeFileSync(env.HOOKS_JSON, JSON.stringify(config, null, 2) + "\n");
'
    printf "${GREEN}✓ Hooks written to %s${NC}\n" "$1"
}

# write_zcode_hooks <config_json> — merge the advisory hooks into ZCode's
# config.json under hooks.events. Config-file hooks only fire when
# hooks.enabled is true, and type "command" timeouts are seconds. Existing
# keys elsewhere in the config (mcp, plugins, …) survive.
write_zcode_hooks() {
    require_node || return 1
    check_hook_sources "$CODE_HOOK" "$TASK_HOOK" "$PRE_DEPLOY_HOOK" || return 1
    mkdir -p "$(dirname "$1")"
    HOOKS_JSON="$1" HOOK_SCRIPT="$CODE_HOOK" TASK_HOOK_SCRIPT="$TASK_HOOK" PRE_DEPLOY_HOOK_SCRIPT="$PRE_DEPLOY_HOOK" node -e '
const fs = require("fs"), env = process.env;
let cfg = {};
if (fs.existsSync(env.HOOKS_JSON)) { try { cfg = JSON.parse(fs.readFileSync(env.HOOKS_JSON, "utf8")); } catch (e) {} }
// Same events as the Claude settings hooks. Matchers are regexes over the
// tool name; Write/Edit alias the apply-patch tool, as in the Codex hooks.
cfg.hooks = {
    enabled: true,
    events: {
        PreToolUse: [{ matcher: "Bash", hooks: [{ type: "command", command: env.PRE_DEPLOY_HOOK_SCRIPT, timeout: 30, enabled: true }] }],
        PostToolUse: [{ matcher: "Edit|Write|NotebookEdit", hooks: [{ type: "command", command: env.HOOK_SCRIPT, timeout: 120, enabled: true }] }],
        Stop: [{ hooks: [{ type: "command", command: env.TASK_HOOK_SCRIPT, timeout: 300, enabled: true }] }]
    }
};
fs.writeFileSync(env.HOOKS_JSON, JSON.stringify(cfg, null, 2) + "\n");
'
    printf "${GREEN}✓ Hooks written to %s${NC}\n" "$1"
}

# install_opencode_plugin <plugins_dir>
# The installed file must be .js — OpenCode's plugin loader scans only
# *.ts and *.js, so a .mjs plugin is silently never loaded.
install_opencode_plugin() {
    check_hook_sources "$CODE_HOOK" "$TASK_HOOK" "$PRE_DEPLOY_CHECK" "$HOOKS_DIR/opencode_post_code_plugin.mjs" || return 1
    mkdir -p "$1"
    rm -f "$1/post_code_hook_plugin.mjs" "$1/post_code_hook_env.mjs"
    sed -e "s|__HOOK_SCRIPT_PATH__|${CODE_HOOK}|g" \
        -e "s|__TASK_HOOK_SCRIPT_PATH__|${TASK_HOOK}|g" \
        -e "s|__PRE_DEPLOY_CHECK_PATH__|${PRE_DEPLOY_CHECK}|g" \
        "$HOOKS_DIR/opencode_post_code_plugin.mjs" > "$1/post_code_hook_plugin.js"
    printf "${GREEN}✓ Plugin installed to %s${NC}\n" "$1/post_code_hook_plugin.js"
}

# install_pi_extension <extensions_dir> — bake the repo hooks dir into pi-checks.ts.
install_pi_extension() {
    check_hook_sources "$CODE_HOOK" "$TASK_HOOK" "$PRE_DEPLOY_CHECK" "$HOOKS_DIR/pi-checks.ts" || return 1
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

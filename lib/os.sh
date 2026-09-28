#!/usr/bin/env bash
#
# lib/os.sh — OS detection, Homebrew and CLI bootstrap, prerequisite tools and the flags every installer shares.
#
# Sourced by lib/common.sh, which sets the colours and repo layout variables
# used here. Not meant to be executed directly.
# shellcheck disable=SC2034  # variables here are read by other modules/installers

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

# Install jq, which the Claude Code / Codex MCP registration needs. uv (for the
# uvx-based AWS servers) is installed by ensure_aws_mcp_choice only on opt-in.
ensure_mcp_prereqs() {
    if ! command -v jq &> /dev/null; then
        printf "${YELLOW}jq not found. Installing...${NC}\n"
        if [ "$(detect_os)" = "macos" ] && command -v brew &> /dev/null; then
            brew install jq
        elif [ "$(detect_os)" = "linux" ]; then
            { sudo apt-get update -y || true; } && sudo apt-get install -y jq
        else
            printf "${RED}Please install jq manually: https://jqlang.github.io/jq/${NC}\n"
            return 1
        fi
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

# install_macols_commands — link this repo's user-facing commands
# (macols-trust, macols-check-stats, macols-openspec-adopt) into ~/.local/bin, which
# persist_local_bin_path keeps on PATH. The hooks and the OpenSpec apply step
# refer to them by name. Symlinks, so a git pull updates them.
install_macols_commands() {
    local cmd
    mkdir -p "$HOME/.local/bin"
    for cmd in macols-trust macols-check-stats macols-openspec-adopt; do
        [ -x "$REPO_ROOT/bin/$cmd" ] || continue
        ln -sf "$REPO_ROOT/bin/$cmd" "$HOME/.local/bin/$cmd"
    done
    persist_local_bin_path
    printf "${GREEN}✓ macols-trust, macols-check-stats and macols-openspec-adopt linked into ~/.local/bin${NC}\n"
}

# install_openspec_schema — make this repo's OpenSpec schema fork (`macols`:
# proposal with scope and constraints, plus an evidence artifact) available to
# every repo as a user-level schema, in OpenSpec's user schema dir
# (${XDG_DATA_HOME:-~/.local/share}/openspec/schemas). Repos still opt in:
# `schema: macols` in their openspec/config.yaml, or
# `openspec new change --schema macols`. Nothing is written into any repo.
# The directory is repo-owned, so it is replaced on each run.
install_openspec_schema() {
    local src="$REPO_ROOT/openspec/schemas/macols"
    local dest="${XDG_DATA_HOME:-$HOME/.local/share}/openspec/schemas/macols"
    [ -f "$src/schema.yaml" ] || { printf "${RED}OpenSpec schema source missing: %s${NC}\n" "$src"; return 1; }
    mkdir -p "$(dirname "$dest")"
    rm -rf "$dest"
    cp -R "$src" "$dest"
    printf "${GREEN}✓ OpenSpec schema 'macols' installed to %s${NC}\n" "$dest"
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
# audit persona and the anchors skill. Idempotent:
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
        { sudo apt-get update -y || true; } && sudo apt-get install -y yq
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

# ensure_quality_tools — the linters the hooks' quality gates call when a
# project has no local copy: shellcheck (shell scripts), jscpd (duplication)
# and, when Go is installed, golangci-lint. Project-level tools (ruff,
# pyright, eslint, tsc, dependency-cruiser, import-linter) come from each
# project's own dev dependencies. Each install is independent and non-fatal;
# a missing tool just means that gate is skipped.
ensure_quality_tools() {
    local failed=0
    if ! command -v shellcheck &> /dev/null; then
        printf "${BLUE}Installing shellcheck...${NC}\n"
        if command -v brew &> /dev/null; then brew install shellcheck || failed=1
        elif [ "$(detect_os)" = "linux" ]; then { { sudo apt-get update -y || true; } && sudo apt-get install -y shellcheck; } || failed=1
        else failed=1; fi
    fi
    if ! command -v jscpd &> /dev/null; then
        printf "${BLUE}Installing jscpd (duplication check)...${NC}\n"
        if command -v npm &> /dev/null; then npm install -g jscpd@4 || failed=1; else failed=1; fi
    fi
    if command -v go &> /dev/null && ! command -v golangci-lint &> /dev/null; then
        printf "${BLUE}Installing golangci-lint...${NC}\n"
        if command -v brew &> /dev/null; then brew install golangci-lint || failed=1
        else go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest || failed=1; fi
    fi
    if [ "$failed" -eq 0 ]; then
        printf "${GREEN}✓ Quality-gate tools available${NC}\n"
    else
        printf "${YELLOW}⚠ Some quality-gate tools could not be installed; those gates are skipped${NC}\n"
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
            # no config directories, so installers/pi.sh provisions both layouts.
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

# handle_common_install_flag — process flags shared by every installers/<tool>.sh.
# Returns 0 when it consumed the flag (-h/--help, --no-cli, -p/--project,
# --aws-mcp/--no-aws-mcp, which export MACOLS_AWS_MCP), else 1
# so the caller's loop handles its tool-specific flags. Relies on the caller
# having defined `usage` and the DO_CLI / PROJECT_INSTALL vars before parsing.
# shellcheck disable=SC2034  # DO_CLI/PROJECT_INSTALL are consumed by the install scripts that source this
handle_common_install_flag() {
    case "$1" in
        -h|--help)     usage; exit 0 ;;
        --no-cli)      DO_CLI=false; return 0 ;;
        -p|--project)  PROJECT_INSTALL=true; DO_CLI=false; return 0 ;;
        --aws-mcp)     export MACOLS_AWS_MCP=1; return 0 ;;
        --no-aws-mcp)  export MACOLS_AWS_MCP=0; return 0 ;;
        *)             return 1 ;;
    esac
}

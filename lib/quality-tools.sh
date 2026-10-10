#!/usr/bin/env bash
#
# lib/quality-tools.sh — the toolchains and linters the hook batteries
# (hooks/checks/post_code.sh, post_task.sh) call, per language, the language
# servers the Fresh editor starts for those languages, and Fresh itself.
#
# The checks prefer a project's own copy (.venv/bin, node_modules/.bin) and
# fall back to PATH, so these global installs are what runs when a project
# has none, and what makes Go and Dart checks possible at all. Every install
# is command -v guarded (re-runs are no-ops) and non-fatal: a missing tool only
# means that gate is skipped. Global CLIs land in ~/.local/bin, which is on
# PATH for login and agent-spawned shells (see ensure_node_on_noninteractive_path).
#
# Sourced by lib/common.sh, which sets the colours used here. Not meant to be
# executed directly.

LOCAL_BIN="$HOME/.local/bin"
# Toolchains without a package manager on Linux live here, linked into LOCAL_BIN.
LOCAL_SHARE="${XDG_DATA_HOME:-$HOME/.local/share}"

# ensure_quality_tools — every language's tools. Returns 1 when any of them
# could not be installed; callers treat that as non-fatal.
ensure_quality_tools() {
    local failed=0
    mkdir -p "$LOCAL_BIN"
    case ":$PATH:" in *":$LOCAL_BIN:"*) ;; *) export PATH="$LOCAL_BIN:$PATH" ;; esac
    ensure_shell_tools  || failed=1
    ensure_python_tools || failed=1
    ensure_node_tools   || failed=1
    ensure_go_tools     || failed=1
    ensure_flutter      || failed=1
    if [ "$failed" -eq 0 ]; then
        printf "${GREEN}✓ Quality-gate tools available (shell, Python, JS/TS, Go, Dart/Flutter)${NC}\n"
    else
        printf "${YELLOW}⚠ Some quality-gate tools could not be installed; those gates are skipped${NC}\n"
        return 1
    fi
}

# _apt_install <pkg...> — Linux only, non-interactive.
_apt_install() {
    [ "$(detect_os)" = "linux" ] && command -v apt-get &> /dev/null || return 1
    { sudo apt-get update -y || true; } && sudo apt-get install -y "$@"
}

# ensure_shell_tools — shellcheck, a hard review timeout and jscpd (duplication).
ensure_shell_tools() {
    local failed=0
    if ! command -v gtimeout &> /dev/null && ! command -v timeout &> /dev/null; then
        printf '%bInstalling coreutils (review timeout)...%b\n' "$BLUE" "$NC"
        if command -v brew &> /dev/null; then brew install coreutils || failed=1
        else _apt_install coreutils || failed=1; fi
    fi
    if ! command -v shellcheck &> /dev/null; then
        printf "${BLUE}Installing shellcheck...${NC}\n"
        if command -v brew &> /dev/null; then brew install shellcheck || failed=1
        else _apt_install shellcheck || failed=1; fi
    fi
    if ! command -v jscpd &> /dev/null; then
        printf "${BLUE}Installing jscpd (duplication check)...${NC}\n"
        if command -v npm &> /dev/null; then npm_global_install jscpd@4 || failed=1; else failed=1; fi
    fi
    return "$failed"
}

# ensure_python_tools — ruff, pyright, mypy, pytest and import-linter
# (lint-imports) as uv tools, each in its own isolated environment, plus pylsp
# (python-lsp-server), Fresh's Python language server. uv is installed first
# when missing (its installer puts it in ~/.local/bin).
ensure_python_tools() {
    local failed=0 pkg bin spec
    if ! command -v uv &> /dev/null; then
        printf "${BLUE}Installing uv (Python tool installer)...${NC}\n"
        curl -LsSf https://astral.sh/uv/install.sh | sh || return 1
        export PATH="$LOCAL_BIN:$HOME/.cargo/bin:$PATH"
        command -v uv &> /dev/null || return 1
    fi
    # <binary>:<package>
    for spec in ruff:ruff pyright:pyright mypy:mypy pytest:pytest lint-imports:import-linter pylsp:python-lsp-server; do
        bin="${spec%%:*}" pkg="${spec#*:}"
        command -v "$bin" &> /dev/null && continue
        printf "${BLUE}Installing %s (uv tool)...${NC}\n" "$pkg"
        uv tool install "$pkg" || failed=1
    done
    return "$failed"
}

# ensure_node_tools — tsc, eslint, dependency-cruiser and the vitest/jest
# runners, as global npm packages, plus Fresh's JS/TS language server and
# formatter (typescript-language-server, prettier). The checks still prefer a
# project's own node_modules/.bin, which is what matches its config.
ensure_node_tools() {
    command -v npm &> /dev/null || { printf "${YELLOW}npm not found — skipping JS/TS tools${NC}\n"; return 1; }
    local -a pkgs=()
    local spec
    # <binary>:<package>
    for spec in tsc:typescript eslint:eslint depcruise:dependency-cruiser vitest:vitest jest:jest \
                typescript-language-server:typescript-language-server prettier:prettier; do
        command -v "${spec%%:*}" &> /dev/null || pkgs+=("${spec#*:}")
    done
    [ ${#pkgs[@]} -eq 0 ] && return 0
    printf "${BLUE}Installing %s (npm -g)...${NC}\n" "${pkgs[*]}"
    npm_global_install "${pkgs[@]}"
}

# _go_arch — Go's name for this machine's CPU.
_go_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo amd64 ;;
        aarch64|arm64) echo arm64 ;;
        *) return 1 ;;
    esac
}

# ensure_go_tools — Go (go, gofmt, go vet, go test), golangci-lint and gopls
# (Fresh's Go language server, and the gopls MCP server in config/mcp).
# Homebrew when present; otherwise the official go.dev tarball in
# ~/.local/share/go (distro packages lag the Go versions golangci-lint v2
# builds with) and golangci-lint built into ~/.local/bin, which is on PATH
# where ~/go/bin often is not.
ensure_go_tools() {
    local failed=0
    if ! command -v go &> /dev/null; then
        printf "${BLUE}Installing Go...${NC}\n"
        if command -v brew &> /dev/null; then
            brew install go || return 1
        else
            local version arch os tmp
            os="$(detect_os)"; [ "$os" = macos ] && os=darwin
            arch="$(_go_arch)" || { printf "${YELLOW}Unsupported CPU for the Go tarball: %s${NC}\n" "$(uname -m)"; return 1; }
            version="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)" || return 1
            tmp="$(mktemp -d)"
            curl -fsSL "https://go.dev/dl/${version}.${os}-${arch}.tar.gz" | tar -xz -C "$tmp" || { rm -rf "$tmp"; return 1; }
            rm -rf "$LOCAL_SHARE/go"; mkdir -p "$LOCAL_SHARE"
            mv "$tmp/go" "$LOCAL_SHARE/go"; rm -rf "$tmp"
            ln -sf "$LOCAL_SHARE/go/bin/go" "$LOCAL_BIN/go"
            ln -sf "$LOCAL_SHARE/go/bin/gofmt" "$LOCAL_BIN/gofmt"
        fi
        command -v go &> /dev/null || return 1
        printf "${GREEN}✓ %s${NC}\n" "$(go version)"
    fi
    if ! command -v golangci-lint &> /dev/null; then
        printf "${BLUE}Installing golangci-lint...${NC}\n"
        if command -v brew &> /dev/null; then brew install golangci-lint || failed=1
        else GOBIN="$LOCAL_BIN" go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest || failed=1; fi
    fi
    if ! command -v gopls &> /dev/null; then
        printf "${BLUE}Installing gopls...${NC}\n"
        if command -v brew &> /dev/null; then brew install gopls || failed=1
        else GOBIN="$LOCAL_BIN" go install golang.org/x/tools/gopls@latest || failed=1; fi
    fi
    return "$failed"
}

# ensure_flutter — the Flutter SDK, which also provides `dart` (dart analyze,
# flutter test). macOS: the Homebrew cask. Linux: a shallow clone of the
# stable channel in ~/.local/share/flutter with flutter/dart linked into
# ~/.local/bin; the first `flutter --version` downloads the Dart SDK.
ensure_flutter() {
    command -v flutter &> /dev/null && command -v dart &> /dev/null && return 0
    printf "${BLUE}Installing Flutter (flutter test, dart analyze)...${NC}\n"
    if [ "$(detect_os)" = "macos" ]; then
        command -v brew &> /dev/null || return 1
        brew install --cask flutter || return 1
    else
        local root="$LOCAL_SHARE/flutter" tool
        for tool in git unzip xz zip; do
            command -v "$tool" &> /dev/null || { _apt_install git unzip xz-utils zip || return 1; break; }
        done
        if [ ! -x "$root/bin/flutter" ]; then
            rm -rf "$root"; mkdir -p "$LOCAL_SHARE"
            git clone -q --depth 1 -b stable https://github.com/flutter/flutter.git "$root" || return 1
        fi
        ln -sf "$root/bin/flutter" "$LOCAL_BIN/flutter"
        ln -sf "$root/bin/dart" "$LOCAL_BIN/dart"
    fi
    flutter --version > /dev/null 2>&1 || return 1
    command -v dart &> /dev/null || return 1
    printf "${GREEN}✓ %s${NC}\n" "$(flutter --version 2>/dev/null | head -1)"
}

# ensure_fresh — Fresh (https://github.com/sinelaw/fresh), the terminal IDE.
# Homebrew when present; otherwise upstream's installer, which unpacks a
# static binary under ~/.local and links ~/.local/bin/fresh without root (and
# can then update itself with `fresh --cmd update`). Its language servers for
# Python, JS/TS, Go and Dart come from the ensure_*_tools above.
ensure_fresh() {
    if command -v fresh &> /dev/null; then
        printf "${GREEN}✓ fresh already installed${NC}\n"
        return 0
    fi
    printf "${BLUE}Installing Fresh (terminal IDE)...${NC}\n"
    if command -v brew &> /dev/null; then
        brew install fresh-editor || return 1
    else
        curl -fsSL "$FRESH_INSTALLER" | sh || return 1
    fi
    command -v fresh &> /dev/null || return 1
    printf "${GREEN}✓ fresh installed: %s${NC}\n" "$(command -v fresh)"
}

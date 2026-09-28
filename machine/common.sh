#!/usr/bin/env bash
#
# machine/common.sh — steps shared by install_macos.sh and install_ubuntu26.sh.
#
# Sourced, never executed. Every step is idempotent: re-running a platform
# script upgrades what is there and never replaces user-owned config (Neovim,
# git identity, AWS credentials). Prompts only appear on an interactive
# terminal; set MACOLS_NONINTERACTIVE=1 (or run without a tty) to skip them.
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "machine/common.sh must be sourced, not executed." >&2
    exit 1
fi

MACHINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$MACHINE_DIR")"

is_macos() { [[ "$OSTYPE" == darwin* ]]; }

is_interactive() {
    [ -t 0 ] && [ -t 1 ] && [ "${MACOLS_NONINTERACTIVE:-0}" != "1" ] && [ -z "${CI:-}" ]
}

warn() { printf '⚠ %s\n' "$*" >&2; }

# apt_update — refresh package lists without aborting the whole setup when one
# third-party repo is broken or unreachable (an old PPA, a proxy): the
# official lists still refresh and installs from them keep working.
apt_update() {
    sudo apt-get update -y || warn "apt-get update reported errors (a broken third-party repo?); continuing"
}

# set_rc_block <file> <name> <body> — write a marker-delimited block into an
# rc file. An existing copy is replaced where it stands (same position, no new
# blank lines), so re-runs leave the file byte-for-byte unchanged; a new block
# is appended. Filters to a temp file and moves it back (no `sed -i`).
set_rc_block() {
    local file="$1" name="$2" body="$3"
    local start="# >>> macols: $name >>>" end="# <<< macols: $name <<<"
    touch "$file"
    if grep -qxF "$start" "$file"; then
        START="$start" END="$end" BODY="$body" awk '
            $0 == ENVIRON["START"] { print; print ENVIRON["BODY"]; skip = 1; next }
            $0 == ENVIRON["END"]   { skip = 0 }
            !skip { print }' "$file" > "$file.macols.tmp"
        if cmp -s "$file" "$file.macols.tmp"; then
            rm -f "$file.macols.tmp"
        else
            mv "$file.macols.tmp" "$file"
        fi
    else
        printf '\n%s\n%s\n%s\n' "$start" "$body" "$end" >> "$file"
    fi
}

# The rc files this user's shells read: zsh and bash on both platforms.
shell_rcs() { printf '%s\n' "$HOME/.zshrc" "$HOME/.bashrc"; }

# ── Homebrew ─────────────────────────────────────────────────────────────────

_brew_bin() {
    local b
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
        [ -x "$b" ] && { echo "$b"; return 0; }
    done
    command -v brew 2>/dev/null
}

# ensure_homebrew — install Homebrew if missing, load it into this shell and
# persist its shellenv in the login rc files (with the right prefix for this
# machine; the old code hard-coded the linuxbrew path everywhere).
ensure_homebrew() {
    local brew_bin
    brew_bin=$(_brew_bin || true)
    if [ -z "$brew_bin" ]; then
        echo "Installing Homebrew..."
        if ! is_macos; then
            apt_update
            sudo apt-get install -y build-essential procps curl file git
        fi
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            || warn "the Homebrew installer failed"
        brew_bin=$(_brew_bin || true)
    fi
    if [ -z "$brew_bin" ] || ! "$brew_bin" --version &>/dev/null; then
        warn "Homebrew is not usable; Brewfile packages are skipped. Fix it, then re-run."
        return 0
    fi
    eval "$("$brew_bin" shellenv)"
    local line="eval \"\$($brew_bin shellenv)\"" rc
    if is_macos; then
        set_rc_block "$HOME/.zprofile" homebrew "$line"
    fi
    while IFS= read -r rc; do
        set_rc_block "$rc" homebrew "$line"
    done < <(shell_rcs)
}

# brew_bundle — install everything in machine/Brewfile. Non-fatal per
# package: `brew bundle` keeps going and reports what failed.
brew_bundle() {
    command -v brew &>/dev/null || { warn "no Homebrew; skipping machine/Brewfile"; return 0; }
    echo "Installing packages from machine/Brewfile..."
    brew bundle --file="$MACHINE_DIR/Brewfile" || warn "some Brewfile entries failed; re-run 'brew bundle --file=$MACHINE_DIR/Brewfile' to see which"
}

# ── Languages ────────────────────────────────────────────────────────────────

# install_python — Python from uv (managed, per-user, never touches the system
# python3 that apt depends on), plus the dev tools the agent hooks call.
install_python() {
    command -v uv &>/dev/null || { warn "uv missing (brew bundle failed?); skipping Python"; return 0; }
    echo "Installing Python 3.14 with uv..."
    export PATH="$HOME/.local/bin:$PATH"
    uv python install 3.14
    # Also expose `python` / `python3` in ~/.local/bin. Older uv only honours
    # --default under --preview (and exits 0 without it), so check the result.
    [ -x "$HOME/.local/bin/python3" ] || uv python install --default 3.14 >/dev/null 2>&1 || true
    [ -x "$HOME/.local/bin/python3" ] || uv python install --preview --default 3.14 >/dev/null 2>&1 || true
    # Last resort: point the shims at the python3.14 uv did install.
    if [ ! -x "$HOME/.local/bin/python3" ] && [ -x "$HOME/.local/bin/python3.14" ]; then
        ln -sf python3.14 "$HOME/.local/bin/python3"
        ln -sf python3.14 "$HOME/.local/bin/python"
    fi
    [ -x "$HOME/.local/bin/python3" ] || warn "no ~/.local/bin/python3; use 'uv run python'"
    local rc
    # shellcheck disable=SC2016  # expanded at shell start, not now
    while IFS= read -r rc; do set_rc_block "$rc" local-bin 'export PATH="$HOME/.local/bin:$PATH"'; done < <(shell_rcs)

    echo "Installing Python dev tools..."
    local tool
    for tool in pytest ruff mypy pyright pip-audit semgrep commitizen; do
        uv tool install --upgrade "$tool" >/dev/null || warn "uv tool install $tool failed"
    done
}

# install_node — NVM, the latest Node, and the global CLIs.
install_node() {
    echo "Installing NVM..."
    export NVM_DIR="$HOME/.nvm"
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        local nvm_latest
        nvm_latest=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep -oE '"tag_name": *"[^"]+"' | cut -d'"' -f4 || true)
        nvm_latest="${nvm_latest:-v0.40.3}"
        PROFILE=/dev/null bash -c "$(curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_latest}/install.sh")"
    fi
    # nvm.sh is not safe under `set -u`; relax it while nvm runs.
    local had_u=0
    [[ $- == *u* ]] && had_u=1
    set +u
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"
    local rc
    # shellcheck disable=SC2016
    while IFS= read -r rc; do
        set_rc_block "$rc" nvm 'export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
    done < <(shell_rcs)

    echo "Installing the latest Node.js..."
    nvm install node
    nvm alias default node
    nvm use default >/dev/null
    [ "$had_u" = 1 ] && set -u

    echo "Installing TypeScript and AWS CDK..."
    npm install -g typescript@latest aws-cdk@latest
}

# ── Editor, prompt and git ───────────────────────────────────────────────────

# install_lazyvim — install the repo's LazyVim config (machine/Lazyvim) only
# when there is no Neovim config yet. An existing config is the user's and is
# left alone; machine/install_lazyvim_config.sh replaces it on request.
install_lazyvim() {
    if [ -e "$HOME/.config/nvim" ]; then
        echo "Neovim config exists; leaving it alone (install_lazyvim_config.sh replaces it)."
        return 0
    fi
    echo "Installing LazyVim config..."
    mkdir -p "$HOME/.config/nvim"
    cp -R "$MACHINE_DIR/Lazyvim/." "$HOME/.config/nvim/"
    rm -f "$HOME/.config/nvim/README.md" "$HOME/.config/nvim/LICENSE"
}

# setup_prompt — starship in zsh and bash. Retires Powerlevel10k from earlier
# installs: theme cleared, instant-prompt and ~/.p10k.zsh lines removed.
setup_prompt() {
    command -v starship &>/dev/null || { warn "starship missing (brew bundle failed?); prompt unchanged"; return 0; }
    local zshrc="$HOME/.zshrc"
    if [ -f "$zshrc" ] && grep -q 'p10k\|powerlevel10k' "$zshrc"; then
        echo "Removing Powerlevel10k from $zshrc..."
        awk '
            /^# Enable Powerlevel10k instant prompt/ { skip = 1 }
            skip && /^fi$/ { skip = 0; next }
            skip { next }
            /p10k/ { next }
            /^ZSH_THEME=/ { print "ZSH_THEME=\"\""; next }
            { print }' "$zshrc" > "$zshrc.macols.tmp" && mv "$zshrc.macols.tmp" "$zshrc"
    fi
    set_rc_block "$HOME/.zshrc" starship 'eval "$(starship init zsh)"'
    set_rc_block "$HOME/.bashrc" starship 'eval "$(starship init bash)"'
}

# configure_git_identity — ask for name/email only when unset and interactive.
configure_git_identity() {
    local name email
    name=$(git config --global user.name || true)
    email=$(git config --global user.email || true)
    if [ -n "$name" ] && [ -n "$email" ]; then
        echo "Git identity: $name <$email>"
        return 0
    fi
    is_interactive || { warn "git user.name/user.email unset; set them with git config --global"; return 0; }
    [ -z "$name" ] && read -rp "Git user name: " name && [ -n "$name" ] && git config --global user.name "$name"
    [ -z "$email" ] && read -rp "Git email: " email && [ -n "$email" ] && git config --global user.email "$email"
    return 0
}

# configure_aws — run `aws configure` only when no AWS config exists yet.
configure_aws() {
    command -v aws &>/dev/null || return 0
    if [ -f "$HOME/.aws/config" ] || [ -f "$HOME/.aws/credentials" ]; then
        echo "AWS CLI already configured."
        return 0
    fi
    is_interactive || { echo "Skipping 'aws configure' (not interactive)."; return 0; }
    aws configure || warn "aws configure did not finish"
}

# install_gh_stack — the stacked-PR gh extension (non-fatal; needs gh auth).
install_gh_stack() {
    command -v gh &>/dev/null || return 0
    if gh extension list 2>/dev/null | grep -q 'github/gh-stack'; then
        echo "gh-stack already installed"
    else
        gh extension install github/gh-stack || warn "gh-stack install skipped (run 'gh auth login' first)"
    fi
}

# install_agent_tools — the agentic CLIs and their config, unless
# ./install.sh --machine called us (it installs them next).
install_agent_tools() {
    [ "${MACOLS_FROM_INSTALL:-0}" = "1" ] && return 0
    echo "Installing agentic coding CLIs and configs..."
    "$REPO_ROOT/install.sh"
}

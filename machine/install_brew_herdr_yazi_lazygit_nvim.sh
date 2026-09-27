#!/usr/bin/env bash

# Re-exec under bash if invoked with sh/dash (set -o pipefail and [[ ]] are bash-only)
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail

echo ""
echo "=============================="
echo " [1/8] Homebrew"
echo "=============================="

if ! command -v brew &>/dev/null; then
    echo "Installing Homebrew..."

    # Install build prerequisites (Ubuntu/apt)
    echo "  Installing build dependencies (apt)..."
    sudo apt-get update -y
    sudo apt-get install -y build-essential procps curl file git

    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "Homebrew already installed."
fi

# Ensure brew is on PATH for the rest of the script
if [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

echo ""
echo "=============================="
echo " [2/8] Installing packages"
echo "=============================="

echo "Installing neovim, yazi, lazygit, delta, and tmux..."
brew install neovim yazi lazygit git-delta tmux

echo "Installing modern CLI tools (ast-grep, jq, dasel)..."
brew install ast-grep jq dasel

echo "Installing herdr..."
if brew install herdr; then
    echo "  herdr installed."
else
    echo "  WARNING: 'brew install herdr' failed — herdr formula not available in the"
    echo "           configured taps. Add the tap that provides herdr, then re-run:"
    echo "             brew install herdr"
    echo "           The auto-launch hook is still installed and will activate once"
    echo "           herdr is on PATH."
fi

echo ""
echo "=============================="
echo " [3/8] herdr plugins + layouts"
echo "=============================="

HERDR_CONFIG_DIR="$HOME/.config/herdr"
HERDR_PLUS_CFG="$HERDR_CONFIG_DIR/plugins/config/cloudmanic.herdr-plus"

# Go is needed to build herdr-plus from source.
if command -v go &>/dev/null; then
    echo "go already installed."
else
    echo "Installing go (required to build herdr plugins)..."
    brew install go || echo "  WARNING: go install failed — the herdr-plus build may fail."
fi

# Bun is the runtime for herdr-browser (plugin itself + its CDP CLI).
if command -v bun &>/dev/null; then
    echo "bun already installed."
else
    echo "Installing bun (required by herdr-browser)..."
    brew install oven-sh/bun/bun \
        || npm install -g bun \
        || echo "  WARNING: bun install failed — herdr-browser will not run. Install it manually: https://bun.sh"
fi

# herdr-browser drives a real Chrome/Chromium; it never downloads one itself.
if command -v chromium &>/dev/null || command -v chromium-browser &>/dev/null \
    || command -v google-chrome &>/dev/null || command -v google-chrome-stable &>/dev/null \
    || [[ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]] \
    || [[ -x "/Applications/Chromium.app/Contents/MacOS/Chromium" ]]; then
    echo "Chrome/Chromium already installed."
else
    echo "Installing Chromium (required by herdr-browser)..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install --cask chromium \
            || echo "  WARNING: Chromium install failed — install Chrome or Chromium manually, then set HERDR_BROWSER_CHROME if herdr-browser cannot find it."
    else
        sudo apt-get install -y chromium || sudo apt-get install -y chromium-browser \
            || echo "  WARNING: Chromium install failed — install Chrome or Chromium manually, then set HERDR_BROWSER_CHROME if herdr-browser cannot find it."
    fi
fi

# On Ubuntu 24/26 the apt 'chromium' package is a snap shim. Snap confinement
# blocks writes to hidden directories in $HOME, which is where herdr-browser
# keeps its per-session Chrome profile.
if [[ "$OSTYPE" != "darwin"* ]] && command -v snap &>/dev/null \
    && snap list chromium &>/dev/null; then
    echo "  NOTE: Chromium is the snap build. If herdr-browser fails to start its"
    echo "        profile, install the Google Chrome .deb instead, or set"
    echo "        \"profileRoot\" in browser.json to a non-hidden path such as"
    echo "        \$HOME/herdr-browser-profiles."
fi

# Live plugin commands only make sense when herdr itself is present (the brew
# formula can be missing — see the WARNING above). The configs further down
# are still written either way and activate once herdr lands on PATH, same
# philosophy as the auto-launch hook.
if command -v herdr &>/dev/null; then
    herdr_plugin_installed() { herdr plugin list 2>/dev/null | grep -qF "$1"; }

    if herdr_plugin_installed "cloudmanic.herdr-plus"; then
        echo "  herdr-plus already installed."
    else
        herdr plugin install cloudmanic/herdr-plus --yes \
            || echo "  WARNING: herdr-plus install failed — retry manually: herdr plugin install cloudmanic/herdr-plus --yes"
        herdr_plugin_installed "cloudmanic.herdr-plus" \
            && echo "  herdr-plus installed." \
            || echo "  WARNING: herdr-plus not visible in 'herdr plugin list'."
    fi

    if herdr_plugin_installed "persiyanov.reviewr"; then
        echo "  herdr-reviewr already installed."
    else
        herdr plugin install persiyanov/herdr-reviewr --yes \
            || echo "  WARNING: herdr-reviewr install failed — retry manually: herdr plugin install persiyanov/herdr-reviewr --yes"
        herdr_plugin_installed "persiyanov.reviewr" \
            && echo "  herdr-reviewr installed." \
            || echo "  WARNING: herdr-reviewr not visible in 'herdr plugin list'."
    fi

    # herdr-browser registers itself as official.browser.
    if herdr_plugin_installed "official.browser"; then
        echo "  herdr-browser already installed."
    else
        herdr plugin install ogulcancelik/herdr-browser --yes \
            || echo "  WARNING: herdr-browser install failed — retry manually: herdr plugin install ogulcancelik/herdr-browser --yes"
        herdr_plugin_installed "official.browser" \
            && echo "  herdr-browser installed." \
            || echo "  WARNING: herdr-browser not visible in 'herdr plugin list'."
    fi
else
    echo "  herdr not on PATH — skipping plugin installs (configs below are still"
    echo "  written and will activate once herdr is installed)."
fi

# Keybindings: merge into config.toml, never overwrite user config. Each
# [[keys.command]] block is grep-guarded on its command string so re-runs
# don't duplicate entries.
mkdir -p "$HERDR_CONFIG_DIR"
touch "$HERDR_CONFIG_DIR/config.toml"
# Repair a missing trailing newline before appending TOML blocks.
if [ -s "$HERDR_CONFIG_DIR/config.toml" ] && [ -n "$(tail -c1 "$HERDR_CONFIG_DIR/config.toml")" ]; then
    echo >> "$HERDR_CONFIG_DIR/config.toml"
fi

# herdr-browser needs herdr's experimental kitty graphics support. Appending a
# second [experimental] header would be a TOML duplicate-table error, so when
# the table already exists we insert the key under it instead (awk + mv, since
# GNU and BSD sed -i differ).
if grep -qF 'kitty_graphics' "$HERDR_CONFIG_DIR/config.toml"; then
    echo "  kitty_graphics already set."
elif grep -q '^\[experimental\][[:space:]]*$' "$HERDR_CONFIG_DIR/config.toml"; then
    awk '
        { print }
        /^\[experimental\][ \t]*$/ && !inserted { print "kitty_graphics = true"; inserted = 1 }
    ' "$HERDR_CONFIG_DIR/config.toml" > "$HERDR_CONFIG_DIR/config.toml.tmp"
    mv "$HERDR_CONFIG_DIR/config.toml.tmp" "$HERDR_CONFIG_DIR/config.toml"
    echo "  Added kitty_graphics = true to the existing [experimental] table."
elif grep -q '^\[experimental\]' "$HERDR_CONFIG_DIR/config.toml"; then
    echo "  WARNING: an [experimental] table exists but could not be edited safely."
    echo "           Add 'kitty_graphics = true' to it by hand or herdr-browser panes stay blank."
else
    cat >> "$HERDR_CONFIG_DIR/config.toml" << 'EOF'

[experimental]
kitty_graphics = true
EOF
    echo "  Added [experimental] kitty_graphics = true (required by herdr-browser)."
fi

if ! grep -qF 'cloudmanic.herdr-plus.projects' "$HERDR_CONFIG_DIR/config.toml"; then
    cat >> "$HERDR_CONFIG_DIR/config.toml" << 'EOF'

[[keys.command]]
key = "prefix+p"
type = "plugin_action"
command = "cloudmanic.herdr-plus.projects"
EOF
    echo "  Added prefix+p -> herdr-plus projects keybinding."
else
    echo "  herdr-plus projects keybinding already present."
fi

if ! grep -qF 'persiyanov.reviewr.toggle' "$HERDR_CONFIG_DIR/config.toml"; then
    cat >> "$HERDR_CONFIG_DIR/config.toml" << 'EOF'

[[keys.command]]
key = "cmd+r"
type = "plugin_action"
command = "persiyanov.reviewr.toggle"
EOF
    echo "  Added cmd+r -> reviewr toggle keybinding."
else
    echo "  reviewr keybinding already present."
fi

# herdr-browser panes. The upstream README suggests prefix+b, but that is
# herdr's own sidebar toggle, so the split binding moves to prefix+shift+b and
# the overlay to prefix+shift+o.
if ! grep -qF 'official.browser --entrypoint browser --placement split' "$HERDR_CONFIG_DIR/config.toml"; then
    cat >> "$HERDR_CONFIG_DIR/config.toml" << 'EOF'

[[keys.command]]
key = "prefix+shift+b"
type = "shell"
command = '"${HERDR_BIN_PATH}" plugin pane open --plugin official.browser --entrypoint browser --placement split --direction right --focus'
description = "open browser in right split"
EOF
    echo "  Added prefix+shift+b -> herdr-browser right split keybinding."
else
    echo "  herdr-browser split keybinding already present."
fi

if ! grep -qF 'official.browser --entrypoint browser --placement overlay' "$HERDR_CONFIG_DIR/config.toml"; then
    cat >> "$HERDR_CONFIG_DIR/config.toml" << 'EOF'

[[keys.command]]
key = "prefix+shift+o"
type = "shell"
command = '"${HERDR_BIN_PATH}" plugin pane open --plugin official.browser --entrypoint browser --placement overlay --focus'
description = "open browser overlay"
EOF
    echo "  Added prefix+shift+o -> herdr-browser overlay keybinding."
else
    echo "  herdr-browser overlay keybinding already present."
fi

# herdr-plus layouts (plugin-owned files — full overwrite, same convention as
# the yazi configs below).
mkdir -p "$HERDR_PLUS_CFG/projects" "$HERDR_PLUS_CFG/worktrees"

echo "  Writing herdr-plus project layout..."
cat > "$HERDR_PLUS_CFG/projects/default.toml" << 'EOF'
name = "Dev (Claude + Yazi)"
description = "Claude Code dangerously in worktree (left) + yazi (right)"

[[tabs]]
name = "claude"
command = "claude --dangerously-skip-permissions"

[[tabs.panes]]
split = "right"
command = "yazi"
EOF

echo "  Writing herdr-plus worktree layout (applies to every repo)..."
cat > "$HERDR_PLUS_CFG/worktrees/default.toml" << 'EOF'
repo = "*"

[[tabs]]
name = "claude"
command = "claude --dangerously-skip-permissions"

[[tabs.panes]]
split = "right"
command = "yazi"
EOF

# Pick up the new config if the herdr server is running (non-fatal otherwise).
if command -v herdr &>/dev/null; then
    herdr server reload-config >/dev/null 2>&1 \
        || echo "  (herdr server not running — config loads on next start)"
fi

echo ""
echo "=============================="
echo " [4/8] LazyVim setup"
echo "=============================="

if [[ ! -d "$HOME/.config/nvim" ]]; then
    echo "Cloning LazyVim starter..."
    git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
    rm -rf "$HOME/.config/nvim/.git"
    echo "LazyVim installed."
else
    echo "Neovim config already exists, skipping LazyVim install."
fi

echo "  Writing git and theme plugins..."
mkdir -p "$HOME/.config/nvim/lua/plugins"
cat > "$HOME/.config/nvim/lua/plugins/git.lua" << 'EOF'
return {
  { "Shatur/neovim-ayu" },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "ayu-dark",
    },
  },

  {
    "lewis6991/gitsigns.nvim",
    opts = {
      signs = {
        add = { text = "+" },
        change = { text = "~" },
        delete = { text = "_" },
        topdelete = { text = "‾" },
        changedelete = { text = "~" },
      },
      current_line_blame = true,
    },
  },

  { "sindrets/diffview.nvim", cmd = { "DiffviewOpen", "DiffviewFileHistory" } },
}
EOF

echo ""
echo "=============================="
echo " [5/8] Verifying installations"
echo "=============================="

yazi --version
ya --version
lazygit --version
delta --version
nvim --version | head -1

echo ""
echo "=============================="
echo " [6/8] Installing Yazi plugins"
echo "=============================="

ya pkg add yazi-rs/plugins:git || true
ya pkg add yazi-rs/plugins:vcs-files || true
ya pkg install --discard || true

echo ""
echo "=============================="
echo " [7/8] Writing Yazi config"
echo "=============================="

YAZI_CONFIG="$HOME/.config/yazi"
mkdir -p "$YAZI_CONFIG/plugins/git-peek.yazi"
mkdir -p "$YAZI_CONFIG/plugins/git-diff.yazi"
mkdir -p "$YAZI_CONFIG/plugins/lazygit.yazi"

echo "  Writing yazi.toml..."
cat > "$YAZI_CONFIG/yazi.toml" << 'EOF'
[[plugin.prepend_previewers]]
url  = "*"
run  = "git-peek"

[[plugin.prepend_fetchers]]
id    = "git"
url   = "*"
run   = "git"
group = "git"

[[plugin.prepend_fetchers]]
id    = "git"
url   = "*/"
run   = "git"
group = "git"

[mgr]
show_hidden = true

[manager]
show_git = true
linemode = "git"

[opener]
edit = [
	{ run = 'nvim "$@"', block = true, desc = "nvim" },
]

[git]
modified = { fg = "yellow", bold = true }
untracked = { fg = "cyan" }
staged    = { fg = "green" }
renamed   = { fg = "magenta" }
deleted   = { fg = "red" }
EOF

echo "  Writing keymap.toml..."
cat > "$YAZI_CONFIG/keymap.toml" << 'EOF'
[[mgr.prepend_keymap]]
on   = [ "g", "i" ]
run  = "plugin lazygit"
desc = "run lazygit"

[[mgr.prepend_keymap]]
on   = [ "g", "c" ]
run  = "plugin vcs-files"
desc = "Show Git file changes"

[[mgr.prepend_keymap]]
on   = [ "g", "d" ]
run  = "plugin git-diff"
desc = "Show inline git diff for selected file"
EOF

echo "  Writing init.lua..."
cat > "$YAZI_CONFIG/init.lua" << 'EOF'
require("git"):setup {
	order = 1500,
}
EOF

echo "  Writing lazygit plugin..."
rm -f "$YAZI_CONFIG/plugins/lazygit.yazi/main.lua"
cat > "$YAZI_CONFIG/plugins/lazygit.yazi/main.lua" << 'EOF'
local function entry()
	ya.emit("shell", { "lazygit", block = true, orphan = true })
end

return { entry = entry }
EOF

echo "  Writing git-diff plugin..."
cat > "$YAZI_CONFIG/plugins/git-diff.yazi/main.lua" << 'EOF'
local selected = ya.sync(function()
	local h = cx.active.current.hovered
	if h then
		return tostring(h.url)
	end
end)

local function entry()
	local path = selected()
	if not path then return end

	ya.emit("shell", {
		'git diff HEAD -- "$0" | delta --paging=always',
		path,
		block = true,
		orphan = true,
	})
end

return { entry = entry }
EOF

echo "  Writing git-peek plugin..."
cat > "$YAZI_CONFIG/plugins/git-peek.yazi/main.lua" << 'EOF'
local M = {}

function M:peek(job)
	local path = tostring(job.file.path)

	local diff, err = Command("git"):arg({ "diff", "HEAD", "--", path }):output()
	if not diff or not diff.stdout or #diff.stdout == 0 then
		diff = Command("git"):arg({ "diff", "--", path }):output()
	end
	if not diff or not diff.stdout or #diff.stdout == 0 then
		return require("code"):peek(job)
	end

	local child = Command("sh")
		:arg({ "-c", "delta --width=" .. job.area.w })
		:stdin(Command.PIPED)
		:stdout(Command.PIPED)
		:stderr(Command.NULL)
		:spawn()

	local text
	if child then
		child:write_all(diff.stdout)
		child:flush()
		local output = child:wait_with_output()
		if output and output.stdout and #output.stdout > 0 then
			text = output.stdout
		else
			text = diff.stdout
		end
	else
		text = diff.stdout
	end

	local opt = { ansi = true, tab_size = rt.preview.tab_size, wrap = rt.preview.wrap, width = job.area.w }
	local limit = job.area.h
	local i, lines = 0, {}

	for line in text:gmatch("[^\n]*\n?") do
		if #line > 0 then
			local wrapped = ui.lines(line, opt)
			local from = math.max(1, job.skip - i + 1)
			local to = math.min(#wrapped, job.skip + limit - i)

			i = i + #wrapped
			for j = from, to do
				lines[#lines + 1] = wrapped[j]
			end

			if i >= job.skip + limit then break end
		end
	end

	if job.skip > 0 and i < job.skip + limit then
		ya.emit("peek", { math.max(0, i - limit), only_if = job.file.url, upper_bound = true })
	else
		ya.preview_widget(job, ui.Text(lines):area(job.area))
	end
end

function M:seek(job) require("code"):seek(job) end

return M
EOF

echo "  Done."

echo ""
echo "=============================="
echo " [8/8] Shell configuration"
echo "=============================="

BREW_LINE='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
EDITOR_LINE='export EDITOR="nvim"'

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rc" ]]; then
        if ! grep -qF 'linuxbrew' "$rc"; then
            echo "" >> "$rc"
            echo "$BREW_LINE" >> "$rc"
            echo "  Added brew shellenv to $rc"
        else
            echo "  brew shellenv already in $rc"
        fi

        if ! grep -qF 'export EDITOR="nvim"' "$rc"; then
            echo "" >> "$rc"
            echo "$EDITOR_LINE" >> "$rc"
            echo "  Added EDITOR=nvim to $rc"
        else
            echo "  EDITOR=nvim already set in $rc"
        fi

        # Auto-launch herdr on interactive SSH logins.
        #
        # Always strip any existing HERDR_AUTOLAUNCH block first, then re-add the
        # current one. This makes the wiring idempotent *and* self-healing.
        #
        # History of the "can't type after sshing in" lockout this guards against:
        #   1. An early version ran `herdr` plainly mid-rc, so the line editor and
        #      herdr fought over the tty and left it in raw mode on exit.
        #   2. The next version switched to `exec herdr`. That gives herdr clean
        #      ownership *while it runs*, but `exec` replaces the shell entirely --
        #      so if herdr crashes, exits, or hands back a terminal still in raw
        #      mode, there's no shell left to recover and no chance to restore the
        #      tty. You're locked out with a dead keyboard.
        #
        # Current approach: we do NOT exec. We run herdr as a child of the login
        # shell and *always* restore the terminal afterward (`stty sane`). So when
        # herdr detaches, exits, or breaks, control returns to a normal shell with
        # a working keyboard rather than a wedged session. The trade-off vs `exec`
        # is that detaching/quitting herdr drops you to a shell instead of closing
        # the SSH connection -- a deliberate choice, since a usable shell is what
        # lets you fix or disable herdr when something goes wrong.
        #
        # Resilience: before launching we still confirm herdr's service is healthy
        # (`herdr service status`); a stopped/hung service falls through to a
        # normal shell. The status check is bounded by `timeout` (or `gtimeout` on
        # macOS) so a wedged daemon can't stall login. Two escape hatches remain
        # for any other breakage: the ~/.no_herdr file, and an rc-skipping login
        # (`ssh -t host 'exec /bin/zsh -f'`).
        if grep -qF 'HERDR_AUTOLAUNCH' "$rc"; then
            # Avoid `sed -i`: GNU sed and BSD/macOS sed disagree on whether it
            # takes a backup-suffix argument, so the in-place form is not
            # portable. Filter to a temp file and move it back instead.
            sed '/# HERDR_AUTOLAUNCH/,/^fi$/d' "$rc" > "$rc.tmp" && mv "$rc.tmp" "$rc"
            echo "  Refreshing herdr auto-launch in $rc"
        fi
        cat >> "$rc" << 'EOF'

# HERDR_AUTOLAUNCH: drop into herdr on each interactive SSH login.
# Guards: interactive SSH shell, herdr installed, not already in a herdr
# session, and no ~/.no_herdr escape-hatch file. Only after confirming the
# herdr service is healthy do we launch it; a stopped/hung service falls
# through to a normal shell so it can't lock you out. The health check is
# time-bounded so a wedged daemon can't stall login.
#
# We intentionally do NOT `exec herdr`. herdr runs as a child of this shell
# and we ALWAYS `stty sane` afterward, so if herdr crashes, exits, or leaves
# the terminal in raw mode you land back in a normal shell with a working
# keyboard instead of a wedged session you can't type into. Detaching/quitting
# herdr therefore drops you to a shell rather than closing the SSH connection.
if [[ $- == *i* ]] && [[ -n "${SSH_CONNECTION:-}" ]] \
    && [[ -z "${HERDR_SESSION:-}" ]] && [[ ! -f "$HOME/.no_herdr" ]] \
    && command -v herdr &>/dev/null; then
    # Bound the health check: prefer GNU `timeout`, then macOS `gtimeout`,
    # else run unbounded. Written explicitly (not via a command-in-a-var) so
    # it behaves identically under bash and zsh.
    if command -v timeout &>/dev/null; then
        timeout 5 herdr service status >/dev/null 2>&1
    elif command -v gtimeout &>/dev/null; then
        gtimeout 5 herdr service status >/dev/null 2>&1
    else
        herdr service status >/dev/null 2>&1
    fi
    if [[ $? -eq 0 ]]; then
        # Mark the session so panes herdr spawns don't recurse into this block.
        export HERDR_SESSION=1
        herdr
        # herdr has detached/exited (or failed to take the tty). Restore the
        # line discipline so the fall-through shell is always usable, then clear
        # the marker so a manual `herdr` relaunch in this shell still works.
        stty sane 2>/dev/null || true
        unset HERDR_SESSION
    else
        echo "herdr: service not healthy -- starting a normal shell instead." >&2
        echo "       Fix with 'herdr service start' then re-login, or run" >&2
        echo "       'touch ~/.no_herdr' to disable auto-launch entirely." >&2
    fi
fi
EOF
        echo "  Added herdr auto-launch to $rc"
    fi
done

# Configure tmux mouse support
if ! grep -qF "set -g mouse on" "$HOME/.tmux.conf" 2>/dev/null; then
    echo "set -g mouse on" >> "$HOME/.tmux.conf"
    echo "  Added mouse support to ~/.tmux.conf"
else
    echo "  tmux mouse already enabled in ~/.tmux.conf"
fi

echo ""
echo "=============================="
echo " Complete!"
echo "=============================="
echo ""
echo "Keybindings:"
echo "  gi  - Open lazygit"
echo "  gc  - Show git changed files"
echo "  gd  - Full-screen git diff for hovered file"
echo ""
echo "Preview pane automatically shows inline diffs for modified files."
echo ""
echo "Next steps:"
echo "  source ~/.zshrc   (or ~/.bashrc)"
echo "  yazi"

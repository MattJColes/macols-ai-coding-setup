#!/usr/bin/env bash

# Re-exec under bash if invoked with sh/dash (set -o pipefail and [[ ]] are bash-only)
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

echo ""
echo "=============================="
echo " [1/6] Homebrew packages"
echo "=============================="

# neovim, yazi, lazygit, delta, tmux, go, bun, ast-grep, jq and dasel all come
# from machine/Brewfile. herdr's formula is not in the default taps on every
# machine, so it stays a separate, non-fatal install.
ensure_homebrew
if ! command -v yazi &>/dev/null || ! command -v lazygit &>/dev/null; then
    brew_bundle
fi

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
echo " [2/6] herdr plugins + layouts"
echo "=============================="

bash "$SCRIPT_DIR/install_herdr_plugins.sh"

echo ""
echo "=============================="
echo " [3/6] Verifying installations"
echo "=============================="

for tool in yazi ya lazygit delta nvim; do
    if command -v "$tool" &>/dev/null; then
        printf '  %-8s %s\n' "$tool" "$("$tool" --version 2>/dev/null | head -1)"
    else
        warn "$tool not found"
    fi
done

echo ""
echo "=============================="
echo " [4/6] Installing Yazi plugins"
echo "=============================="

if command -v ya &>/dev/null; then
    ya pkg add yazi-rs/plugins:git || true
    ya pkg add yazi-rs/plugins:vcs-files || true
    ya pkg install --discard || true
else
    warn "ya (yazi) missing; skipping yazi plugins"
fi

echo ""
echo "=============================="
echo " [5/6] Writing Yazi config"
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

[opener]
edit = [
	{ run = 'nvim "$@"', block = true, desc = "nvim" },
]
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
echo " [6/6] Shell configuration"
echo "=============================="

HERDR_AUTOLAUNCH_BLOCK=$(cat << 'EOF'
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
)

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rc" ]]; then
        # Homebrew's shellenv is written by ensure_homebrew (common.sh) with
        # this machine's prefix. Drop the linuxbrew line older versions
        # appended unconditionally (wrong on macOS).
        # Only lines outside the macols blocks: the homebrew block itself may
        # hold the same line on Linux.
        legacy='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
        LEGACY="$legacy" awk '
            /^# >>> macols: / { inblock = 1 }
            /^# <<< macols: / { inblock = 0; print; next }
            !inblock && $0 == ENVIRON["LEGACY"] { next }
            { print }' "$rc" > "$rc.macols.tmp"
        if cmp -s "$rc" "$rc.macols.tmp"; then rm -f "$rc.macols.tmp"; else mv "$rc.macols.tmp" "$rc"; fi
        if ! grep -qF 'export EDITOR="nvim"' "$rc"; then
            set_rc_block "$rc" editor 'export EDITOR="nvim"'
            echo "  Set EDITOR=nvim in $rc"
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
        # Retire the pre-marker copy (a bare "# HERDR_AUTOLAUNCH" ... "fi"
        # block) if an older run left one outside the managed blocks.
        if grep -qF '# HERDR_AUTOLAUNCH' "$rc" && ! grep -qF '# >>> macols: herdr-autolaunch >>>' "$rc"; then
            awk '/^# HERDR_AUTOLAUNCH/ { skip = 1 }
                 skip && /^fi$/ { skip = 0; next }
                 !skip { print }' "$rc" > "$rc.macols.tmp" && mv "$rc.macols.tmp" "$rc"
        fi
        set_rc_block "$rc" herdr-autolaunch "$HERDR_AUTOLAUNCH_BLOCK"
        echo "  herdr auto-launch set in $rc"
    fi
done

# tmux: mouse scrolling, and PgUp jumps straight into copy mode.
set_rc_block "$HOME/.tmux.conf" tmux-mouse 'set -g mouse on
bind -n Pageup copy-mode -u'
echo "  tmux mouse support set in ~/.tmux.conf"

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

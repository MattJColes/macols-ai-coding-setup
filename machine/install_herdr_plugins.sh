#!/usr/bin/env bash
# herdr plugins, their keybindings and layouts, agent integrations and the
# shell helpers that go with them. Called by install_brew_herdr_yazi_lazygit_nvim.sh;
# safe to re-run on its own.

# Re-exec under bash if invoked with sh/dash (set -o pipefail and [[ ]] are bash-only)
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

HERDR_CONFIG_DIR="$HOME/.config/herdr"
HERDR_PLUS_CFG="$HERDR_CONFIG_DIR/plugins/config/cloudmanic.herdr-plus"

# Go (herdr-plus build) and bun (herdr-browser runtime) come from the Brewfile.
command -v go &>/dev/null || warn "go missing - the herdr-plus build may fail"
command -v bun &>/dev/null || warn "bun missing - herdr-browser will not run"

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
    # Match the "- <id> (" line exactly: a bare substring such as "annotate"
    # would also match descriptions and other plugin ids.
    herdr_plugin_installed() { herdr plugin list 2>/dev/null | grep -qF -- "- $1 ("; }

    # herdr_plugin_ensure <plugin id> <github source> <label>
    herdr_plugin_ensure() {
        local id="$1" src="$2" label="$3"
        if herdr_plugin_installed "$id"; then
            echo "  $label already installed."
            return
        fi
        herdr plugin install "$src" --yes \
            || echo "  WARNING: $label install failed — retry manually: herdr plugin install $src --yes"
        herdr_plugin_installed "$id" \
            && echo "  $label installed." \
            || echo "  WARNING: $label not visible in 'herdr plugin list'."
    }

    herdr_plugin_ensure cloudmanic.herdr-plus cloudmanic/herdr-plus herdr-plus
    herdr_plugin_ensure persiyanov.reviewr persiyanov/herdr-reviewr herdr-reviewr
    # herdr-browser registers itself as official.browser.
    herdr_plugin_ensure official.browser ogulcancelik/herdr-browser herdr-browser
    # Names each tab after its foreground program or the agent session.
    herdr_plugin_ensure herdr-automatic-rename qu8n/herdr-automatic-rename herdr-automatic-rename
    # Full install: review plans, Markdown docs and agent replies, send notes back.
    herdr_plugin_ensure annotate plannotator/herdr-annotate herdr-annotate

    # Native agent detection, so herdr (and the rename/review plugins) see agent
    # state and replies without scraping the screen. Only for agents on PATH.
    for agent in claude codex omp; do
        command -v "$agent" &>/dev/null || continue
        if herdr integration status 2>/dev/null | grep -q "^$agent: current"; then
            echo "  herdr $agent integration already current."
        else
            herdr integration install "$agent" >/dev/null \
                && echo "  herdr $agent integration installed." \
                || echo "  WARNING: herdr $agent integration failed — retry: herdr integration install $agent"
        fi
    done
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

# herdr_toml_set <table> <key> <value> <why>: set one key in a top-level table
# of config.toml. Appending a second [table] header would be a TOML
# duplicate-table error, so when the table already exists we insert the key
# under it instead (awk + mv, since GNU and BSD sed -i differ). An existing
# key is left alone: the user's value wins.
herdr_toml_set() {
    local table="$1" key="$2" value="$3" why="$4" cfg="$HERDR_CONFIG_DIR/config.toml"
    if grep -q "^[[:space:]]*${key}[[:space:]]*=" "$cfg"; then
        echo "  $key already set."
    elif grep -q "^\\[${table}\\][[:space:]]*\$" "$cfg"; then
        TABLE="[$table]" LINE="$key = $value" awk '
            { print }
            !inserted { t = $0; sub(/[ \t]+$/, "", t) }
            !inserted && t == ENVIRON["TABLE"] { print ENVIRON["LINE"]; inserted = 1 }
        ' "$cfg" > "$cfg.tmp"
        mv "$cfg.tmp" "$cfg"
        echo "  Added $key = $value to the existing [$table] table ($why)."
    elif grep -q "^\\[${table}\\]" "$cfg"; then
        echo "  WARNING: a [$table] table exists but could not be edited safely."
        echo "           Add '$key = $value' to it by hand ($why)."
    else
        printf '\n[%s]\n%s = %s\n' "$table" "$key" "$value" >> "$cfg"
        echo "  Added [$table] $key = $value ($why)."
    fi
}

herdr_toml_set experimental kitty_graphics true "required by herdr-browser"
# herdr's new-tab name prompt counts as a hand rename, which opts every new tab
# out of herdr-automatic-rename.
herdr_toml_set ui prompt_new_tab_name false "lets herdr-automatic-rename name new tabs"

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

# herdr_bind_action <key> <plugin action> <description>: add a plugin_action
# binding unless that key is already bound, so a user's own binding wins.
herdr_bind_action() {
    local key="$1" action="$2" desc="$3" cfg="$HERDR_CONFIG_DIR/config.toml"
    if grep -qF "key = \"$key\"" "$cfg"; then
        echo "  $key already bound — skipped $action."
        return
    fi
    printf '\n[[keys.command]]\nkey = "%s"\ntype = "plugin_action"\ncommand = "%s"\ndescription = "%s"\n' \
        "$key" "$action" "$desc" >> "$cfg"
    echo "  Added $key -> $action."
}

# cmd+r above only reaches herdr from macOS terminals that pass cmd through;
# prefix+d (d for diff) works everywhere. prefix+r is herdr's resize mode.
herdr_bind_action prefix+d persiyanov.reviewr.toggle "toggle the reviewr diff pane"
herdr_bind_action prefix+a herdr-automatic-rename.reset "hand this tab's name back to automatic naming"
# herdr-annotate's README suggests prefix+o / prefix+shift+o, but those are
# herdr's notification jump and the browser overlay above.
herdr_bind_action prefix+ctrl+p annotate.open "review plans and docs in this folder"
herdr_bind_action prefix+ctrl+l annotate.last "review the agent's recent replies"
herdr_bind_action prefix+ctrl+o annotate.last-newest "review the agent's newest reply"

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

# herdr-automatic-rename's shell hook renames a tab the moment a command
# starts. Its own install.sh writes an unmanaged copy marked with the line
# below; skip an rc that already has it so the hook is not wired twice.
HAR_MARKER="# herdr-automatic-rename: live tab naming hook"
# Literal $HOME so the rc stays portable; the glob absorbs the version hash
# herdr puts in the plugin directory name.
HAR_DIR="\$HOME/.config/herdr/plugins/github/herdr-automatic-rename-*/shell"
for rc in $(shell_rcs); do
    [[ -f "$rc" ]] || continue
    if grep -qF "$HAR_MARKER" "$rc"; then
        echo "  herdr-automatic-rename hook already wired in $rc (by its own installer)."
        continue
    fi
    case "$rc" in
        *zshrc) body="for _f in $HAR_DIR/hook.zsh(N); do
  source \$_f; break
done" ;;
        *) body="for _f in $HAR_DIR/hook.bash; do
  [ -r \"\$_f\" ] && { source \"\$_f\"; break; }
done" ;;
    esac
    set_rc_block "$rc" herdr-automatic-rename "$body"
    echo "  herdr-automatic-rename hook set in $rc"
done

# Shell commands for the review panes. Over `herdr --remote` the client uses
# its local keybindings and never sends custom command bindings, so the
# prefix keys above do nothing there; these work in any herdr pane.
HERDR_REVIEW_ALIASES=$(cat << 'EOF'
alias rv='herdr plugin action invoke toggle --plugin persiyanov.reviewr >/dev/null'
alias rplan='herdr plugin action invoke annotate.open >/dev/null'
alias rlast='herdr plugin action invoke annotate.last >/dev/null'
alias rnew='herdr plugin action invoke annotate.last-newest >/dev/null'
EOF
)
for rc in $(shell_rcs); do
    [[ -f "$rc" ]] || continue
    set_rc_block "$rc" herdr-review-aliases "$HERDR_REVIEW_ALIASES"
    echo "  herdr review aliases (rv, rplan, rlast, rnew) set in $rc"
done

# Pick up the new config if the herdr server is running (non-fatal otherwise).
if command -v herdr &>/dev/null; then
    herdr server reload-config >/dev/null 2>&1 \
        || echo "  (herdr server not running — config loads on next start)"
fi

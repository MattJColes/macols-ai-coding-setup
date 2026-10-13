#!/usr/bin/env bash
# herdr plugins (herdr-auto-title, herdr-sidebar), their keybindings and the
# agent integrations, plus cleanup of the plugins earlier versions installed.
# Called by install_brew_herdr_yazi_lazygit_nvim.sh; safe to re-run on its own.

# Re-exec under bash if invoked with sh/dash (set -o pipefail and [[ ]] are bash-only)
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

HERDR_CONFIG_DIR="$HOME/.config/herdr"
HERDR_CFG="$HERDR_CONFIG_DIR/config.toml"

# Go builds herdr-auto-title at install time. herdr-sidebar fetches a
# checksum-verified release binary and only needs Rust when none matches.
command -v go &>/dev/null || warn "go missing - the herdr-auto-title build will fail"

# Plugins earlier versions of this script installed, as "<id> <marker>": the
# marker is a string unique to the keybindings it added for that plugin.
RETIRED_PLUGINS=(
    "cloudmanic.herdr-plus cloudmanic.herdr-plus."
    "persiyanov.reviewr persiyanov.reviewr"
    "official.browser --plugin official.browser"
    "herdr-automatic-rename herdr-automatic-rename."
    "annotate \"annotate."
)

# Live plugin commands only make sense when herdr itself is present (the brew
# formula can be missing — see the WARNING above). The configs further down
# are still written either way and activate once herdr lands on PATH, same
# philosophy as the auto-launch hook.
if command -v herdr &>/dev/null; then
    # Match the "- <id> (" line exactly: a bare substring such as "annotate"
    # would also match descriptions and other plugin ids.
    herdr_plugin_installed() { herdr plugin list 2>/dev/null | grep -qF -- "- $1 ("; }

    for entry in "${RETIRED_PLUGINS[@]}"; do
        id="${entry%% *}"
        herdr_plugin_installed "$id" || continue
        herdr plugin uninstall "$id" >/dev/null \
            && echo "  Removed retired plugin $id." \
            || echo "  WARNING: could not remove $id — retry: herdr plugin uninstall $id"
    done

    # herdr_plugin_ensure <plugin id> <github source> <label>: returns 0 only
    # when this call installed the plugin.
    herdr_plugin_ensure() {
        local id="$1" src="$2" label="$3"
        if herdr_plugin_installed "$id"; then
            echo "  $label already installed."
            return 1
        fi
        herdr plugin install "$src" --yes \
            || echo "  WARNING: $label install failed — retry manually: herdr plugin install $src --yes"
        if herdr_plugin_installed "$id"; then
            echo "  $label installed."
        else
            echo "  WARNING: $label not visible in 'herdr plugin list'."
            return 1
        fi
    }

    # Names tabs and panes after the work in them (directory, branch, agent task).
    # herdr starts plugins only when its server starts, so start this one now.
    if herdr_plugin_ensure herdr.auto-title kryptamine/herdr-auto-title herdr-auto-title; then
        herdr plugin action invoke herdr.auto-title.restart >/dev/null 2>&1 \
            || echo "  (herdr server not running — herdr-auto-title starts with it)"
    fi
    # VS Code-style file explorer, search and source control in a docked pane.
    herdr_plugin_ensure herdr-sidebar alexarthurs/herdr-sidebar/plugins/herdr-sidebar herdr-sidebar || true

    # Native agent detection, so herdr and herdr-auto-title see agent state
    # without scraping the screen. Only for agents on PATH.
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

# Keybindings: merge into config.toml, never overwrite user config.
mkdir -p "$HERDR_CONFIG_DIR"
touch "$HERDR_CFG"
# Repair a missing trailing newline before appending TOML blocks.
if [ -s "$HERDR_CFG" ] && [ -n "$(tail -c1 "$HERDR_CFG")" ]; then
    echo >> "$HERDR_CFG"
fi

# Drop the [[keys.command]] blocks earlier runs added for the retired plugins,
# together with the blank line each was appended after.
retired_markers=$(for entry in "${RETIRED_PLUGINS[@]}"; do printf '%s\n' "${entry#* }"; done)
if MARKERS="$retired_markers" awk '
    BEGIN { n = split(ENVIRON["MARKERS"], markers, "\n") }
    function settle() {
        if (in_block && !drop) printf "%s", block
        if (in_block && drop) dropped++
        block = ""; in_block = 0; drop = 0
    }
    /^[ \t]*\[/ {
        settle()
        t = $0; gsub(/[ \t]/, "", t)
        if (t == "[[keys.command]]") { in_block = 1; block = blanks $0 "\n"; blanks = ""; next }
    }
    /^[ \t]*$/ { blanks = blanks $0 "\n"; next }
    {
        if (in_block) {
            block = block blanks $0 "\n"
            for (i = 1; i <= n; i++) if (markers[i] != "" && index($0, markers[i])) drop = 1
        } else printf "%s%s\n", blanks, $0
        blanks = ""
    }
    END { settle(); printf "%s", blanks; exit dropped == 0 }
' "$HERDR_CFG" > "$HERDR_CFG.tmp"; then
    mv "$HERDR_CFG.tmp" "$HERDR_CFG"
    echo "  Removed keybindings for retired herdr plugins."
else
    rm -f "$HERDR_CFG.tmp"
fi

# herdr_toml_set <table> <key> <value> <why>: set one key in a top-level table
# of config.toml. Appending a second [table] header would be a TOML
# duplicate-table error, so when the table already exists we insert the key
# under it instead (awk + mv, since GNU and BSD sed -i differ). An existing
# key is left alone: the user's value wins.
herdr_toml_set() {
    local table="$1" key="$2" value="$3" why="$4" cfg="$HERDR_CFG"
    # Scope the existing-key check to the table: a generic key such as `name`
    # can legitimately appear in other tables.
    if TABLE="[$table]" KEY="$key" awk '
        /^\[/ { t = $0; sub(/[ \t]+$/, "", t); in_table = (t == ENVIRON["TABLE"]) }
        in_table && $0 ~ "^[ \t]*" ENVIRON["KEY"] "[ \t]*=" { found = 1 }
        END { exit !found }
    ' "$cfg"; then
        echo "  [$table] $key already set."
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

# herdr's new-tab name prompt counts as a hand rename, which opts every new tab
# out of herdr-auto-title.
herdr_toml_set ui prompt_new_tab_name false "lets herdr-auto-title name new tabs"
# Default theme, matching omp's dark-gruvbox. auto_switch off stops a light/dark
# OS change swapping it out.
herdr_toml_set theme name '"gruvbox"' "default theme"
herdr_toml_set theme auto_switch false "keeps the gruvbox theme"

# herdr_bind_action <key> <plugin action> <description>: add a plugin_action
# binding unless that key is already bound, so a user's own binding wins.
herdr_bind_action() {
    local key="$1" action="$2" desc="$3" cfg="$HERDR_CFG"
    if grep -qF "key = \"$key\"" "$cfg"; then
        echo "  $key already bound — skipped $action."
        return
    fi
    printf '\n[[keys.command]]\nkey = "%s"\ntype = "plugin_action"\ncommand = "%s"\ndescription = "%s"\n' \
        "$key" "$action" "$desc" >> "$cfg"
    echo "  Added $key -> $action."
}

# herdr-sidebar's README binds prefix+b, but that is herdr's own sidebar
# toggle, and prefix+e is taken too, so the explorer goes on prefix+f (files).
herdr_bind_action prefix+f herdr-sidebar.open-sidebar "toggle the herdr-sidebar explorer"
herdr_bind_action prefix+ctrl+p herdr-sidebar.quick-open "quick-open a file in herdr-sidebar"
# The README suggests prefix+R, which is herdr's own prefix+shift+r.
herdr_bind_action prefix+ctrl+r herdr.auto-title.restart "restart herdr-auto-title"

# herdr-plus layouts earlier runs wrote. Only these two files were ours, so
# the directories go only if nothing else is left in them.
HERDR_PLUS_CFG="$HERDR_CONFIG_DIR/plugins/config/cloudmanic.herdr-plus"
for layout in projects/default.toml worktrees/default.toml; do
    [[ -f "$HERDR_PLUS_CFG/$layout" ]] || continue
    rm -f "$HERDR_PLUS_CFG/$layout"
    echo "  Removed retired herdr-plus layout $layout."
done
rmdir "$HERDR_PLUS_CFG/projects" "$HERDR_PLUS_CFG/worktrees" "$HERDR_PLUS_CFG" 2>/dev/null || true

# Shell blocks earlier runs wrote for the retired plugins.
for rc in $(shell_rcs); do
    for block in herdr-automatic-rename herdr-review-aliases; do
        remove_rc_block "$rc" "$block" && echo "  Removed $block block from $rc." || true
    done
done

# Pick up the new config if the herdr server is running (non-fatal otherwise).
if command -v herdr &>/dev/null; then
    herdr server reload-config >/dev/null 2>&1 \
        || echo "  (herdr server not running — config loads on next start)"
fi

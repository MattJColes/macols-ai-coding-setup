#!/usr/bin/env bash
#
# lib/lgtmaybe.sh — the lgtmaybe local-review opt-in: the Z.AI GLM coding-plan
# key plus the CLI and PATH symlink behind bin/macols-lgtmaybe.
#
# Sourced by lib/common.sh, which sets the colours and repo layout variables
# used here. Not meant to be executed directly.
# shellcheck disable=SC2034  # variables here are read by other modules/installers
# shellcheck disable=SC2059  # colour variables in printf format strings, as lib/mcp.sh

# ── lgtmaybe — local AI code review ──────────────────────────────────────────
# bin/macols-lgtmaybe reviews the local git diff with the lgtmaybe CLI
# (https://github.com/MattJColes/lgtmaybe) against the Z.AI GLM coding plan.
# Two consumers: the audit persona's first review pass, and the commit
# checkpoint's lgtmaybe stage in hooks/checks/post_task.sh. Both read the key
# from $ZAI_KEY_FILE (mode 600); no secret reaches a config file or argv.
# ZAI_CHOICE_FILE records "off" when the user skips the prompt, so re-runs
# and other installers do not ask again; exporting ZAI_API_KEY clears it.

ensure_lgtmaybe() {
    local key="${ZAI_API_KEY:-}"
    if [ -e "$ZAI_KEY_FILE" ]; then
        chmod 600 "$ZAI_KEY_FILE" || return 1
    fi
    if [ -z "$key" ]; then
        if [ -s "$ZAI_KEY_FILE" ]; then
            printf "${GREEN}✓ lgtmaybe already configured (%s)${NC}\n" "$ZAI_KEY_FILE"
        elif [ -s "$ZAI_CHOICE_FILE" ] && [ "$(tr -d '[:space:]' < "$ZAI_CHOICE_FILE")" = off ]; then
            return 1
        elif [ -t 0 ]; then
            printf "${BLUE}lgtmaybe — local AI code review on the Z.AI GLM coding plan${NC}\n"
            printf "${BLUE}  mint a key at https://z.ai/manage-apikey/apikey-list (coding plan)${NC}\n"
            read -rsp "$(printf "${YELLOW}Z.AI API key (blank to skip): ${NC}")" key
            echo ""
            if [ -z "$key" ]; then
                mkdir -p "$(dirname "$ZAI_CHOICE_FILE")" || return 1
                printf 'off' > "$ZAI_CHOICE_FILE"
                return 1
            fi
        else
            printf "${YELLOW}⚠ Non-interactive install — set ZAI_API_KEY to enable lgtmaybe local review${NC}\n"
            return 1
        fi
    else
        printf "${BLUE}Using ZAI_API_KEY from the environment${NC}\n"
    fi

    if [ -n "$key" ]; then
        mkdir -p "$(dirname "$ZAI_KEY_FILE")"
        (umask 077; printf '%s' "$key" > "$ZAI_KEY_FILE")
        [ -s "$ZAI_CHOICE_FILE" ] && rm -f "$ZAI_CHOICE_FILE"
        printf "${GREEN}✓ Z.AI API key stored in %s${NC}\n" "$ZAI_KEY_FILE"
    fi

    # The CLI itself: Homebrew carries the formula; a machine setup that has
    # not run yet leaves it missing, which every consumer treats as a skip.
    if ! command -v lgtmaybe &>/dev/null; then
        local brew
        for brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
            [ -x "$brew" ] && break
            brew=""
        done
        if [ -n "$brew" ]; then
            printf "${BLUE}Installing lgtmaybe (brew install lgtmaybe)...${NC}\n"
            "$brew" install lgtmaybe || printf "${YELLOW}⚠ lgtmaybe install failed — the review stages skip until it is on PATH${NC}\n"
        else
            printf "${YELLOW}⚠ lgtmaybe CLI not found and no Homebrew — install it with 'brew install lgtmaybe'${NC}\n"
        fi
    fi

    # Both consumers call it by bare name; expose it like bin/macols-trust.
    mkdir -p "$HOME/.local/bin"
    ln -sf "$REPO_ROOT/bin/macols-lgtmaybe" "$HOME/.local/bin/macols-lgtmaybe"

    [ -s "$ZAI_KEY_FILE" ]
}

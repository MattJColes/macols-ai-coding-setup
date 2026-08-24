#!/usr/bin/env bash
#
# Post-install verification for a single CLI.
#
# Usage: tests/verify_install.sh <claudecode|codex|opencode|pi|zcode>
#
# Asserts that the installer placed files in the expected locations and that
# the CLI reports a configured state via non-auth introspection. Exits non-zero
# if any HARD check fails. Live introspection that may need network/auth (e.g.
# `claude mcp list`) is treated as SOFT (warn only); MCP wiring is asserted from
# the persisted config files instead.
#
# Tildes below appear inside human-readable check labels, not paths.
# shellcheck disable=SC2088
set -uo pipefail

TOOL="${1:-}"
FAILED=0

green() { printf '\033[0;32m  ✓ %s\033[0m\n' "$1"; }
red()   { printf '\033[0;31m  ✗ %s\033[0m\n' "$1"; FAILED=1; }
warn()  { printf '\033[1;33m  ⚠ %s\033[0m\n' "$1"; }

# pass <desc> <test-command...>
pass() { if eval "$2"; then green "$1"; else red "$1"; fi; }
# soft <desc> <test-command...>
soft() { if eval "$2"; then green "$1"; else warn "$1 (soft)"; fi; }

count_gt0() { [ "$(find "$1" -maxdepth "${3:-2}" -name "${2}" 2>/dev/null | wc -l)" -gt 0 ]; }
has_jq() { command -v jq &> /dev/null; }
has_ponytail_block() { grep -q 'ponytail:ruleset:start' "$1" 2>/dev/null; }

# The shared response-format block lands in the steering doc exactly once...
rf_once() { [ "$(grep -c '^## Response Format' "$1" 2>/dev/null)" = 1 ]; }
# ...and in every rendered persona, which carries its own system prompt.
# rf_every <dir> <find-name-pattern>
rf_every() {
    local have total
    have=$(grep -rl '^## Response Format' "$1" 2>/dev/null | wc -l)
    total=$(find "$1" -type f -name "$2" 2>/dev/null | wc -l)
    [ "$total" -gt 0 ] && [ "$have" -eq "$total" ]
}

verify_claudecode() {
    local d="$HOME/.claude"
    soft "claude --version" "command -v claude >/dev/null && claude --version >/dev/null 2>&1"
    pass "agents in ~/.claude/agents/*.md"        "count_gt0 '$d/agents' '*.md' 1"
    pass "skills in ~/.claude/skills/*/SKILL.md"  "count_gt0 '$d/skills' 'SKILL.md' 3"
    pass "~/.claude/CLAUDE.md is System-Level Claude" "grep -q 'System-Level Claude' '$d/CLAUDE.md'"
    pass "~/.claude/CLAUDE.md has response format (once)" "rf_once '$d/CLAUDE.md'"
    pass "every ~/.claude agent has response format" "rf_every '$d/agents' '*.md'"
    pass "every ~/.claude skill has response format"  "rf_every '$d/skills' 'SKILL.md'"
    pass "~/.claude/bin/claude-launch is executable" "[ -x '$d/bin/claude-launch' ]"
    if has_jq; then
        pass "settings.json has PostToolUse hook"  "jq -e '.hooks.PostToolUse[0].hooks[0].command' '$d/settings.json' >/dev/null"
        pass "~/.claude.json has filesystem MCP"    "jq -e '.mcpServers.filesystem' '$HOME/.claude.json' >/dev/null 2>&1"
    else
        warn "jq not available — skipping JSON assertions"
    fi
    # Ponytail lands either as an installed plugin (CLI path) or as a settings
    # declaration (offline fallback) — either satisfies the check.
    pass "ponytail plugin installed or declared" \
        "grep -qs 'ponytail@ponytail' '$d/plugins/installed_plugins.json' || grep -qs 'ponytail@ponytail' '$d/settings.json'"
    soft "git worktree available" "git worktree list >/dev/null 2>&1 || git worktree --help >/dev/null 2>&1"
    soft "openspec CLI installed" "command -v openspec >/dev/null && openspec --version >/dev/null 2>&1"
    soft "ast-grep CLI installed" "command -v ast-grep >/dev/null && ast-grep --version >/dev/null 2>&1"
    soft "yq CLI installed" "command -v yq >/dev/null 2>&1"
    soft "claude mcp list shows filesystem" "command -v claude >/dev/null && claude mcp list 2>/dev/null | grep -q filesystem"
}

verify_codex() {
    local d="$HOME/.codex"
    soft "codex --version" "command -v codex >/dev/null && codex --version >/dev/null 2>&1"
    pass "no legacy prompts dir (~/.codex/prompts removed)" "[ ! -d '$d/prompts' ]"
    pass "skills in ~/.codex/skills/*/SKILL.md"   "count_gt0 '$d/skills' 'SKILL.md' 3"
    pass "agents in ~/.codex/agents/*.toml"       "count_gt0 '$d/agents' '*.toml' 1"
    pass "agent toml has developer_instructions"  "grep -q 'developer_instructions' '$d/agents/review.toml'"
    pass "~/.codex/AGENTS.md is System-Level Codex" "grep -q 'System-Level Codex' '$d/AGENTS.md'"
    pass "~/.codex/AGENTS.md has ponytail ruleset (once)" "[ \"\$(grep -c 'ponytail:ruleset:start' '$d/AGENTS.md' 2>/dev/null)\" = 1 ]"
    pass "~/.codex/AGENTS.md has response format (once)" "rf_once '$d/AGENTS.md'"
    pass "every ~/.codex agent has response format"   "rf_every '$d/agents' '*.toml'"
    pass "every ~/.codex skill has response format"   "rf_every '$d/skills' 'SKILL.md'"
    if has_jq; then
        pass "hooks.json top level is Codex's description/hooks" "jq -e '[keys[] | select(. != \"description\" and . != \"hooks\")] | length == 0' '$d/hooks.json' >/dev/null"
        pass "hooks.json has PostToolUse hook"     "jq -e '.hooks.PostToolUse[0].hooks[0].command' '$d/hooks.json' >/dev/null"
        pass "hooks.json Stop runs post-task battery" "jq -e '.hooks.Stop[0].hooks[0].command | test(\"post_task\")' '$d/hooks.json' >/dev/null"
    fi
    soft "codex mcp list shows filesystem" "command -v codex >/dev/null && codex mcp list 2>/dev/null | grep -q filesystem"
}

verify_opencode() {
    local d="$HOME/.config/opencode"
    soft "opencode --version" "command -v opencode >/dev/null && opencode --version >/dev/null 2>&1"
    pass "agents in ~/.config/opencode/agents/*.md"       "count_gt0 '$d/agents' '*.md' 1"
    pass "skills in ~/.config/opencode/skills/*/SKILL.md" "count_gt0 '$d/skills' 'SKILL.md' 3"
    pass "~/.config/opencode/AGENTS.md is System-Level OpenCode" "grep -q 'System-Level OpenCode' '$d/AGENTS.md'"
    pass "~/.config/opencode/AGENTS.md has ponytail ruleset (once)" "[ \"\$(grep -c 'ponytail:ruleset:start' '$d/AGENTS.md' 2>/dev/null)\" = 1 ]"
    pass "~/.config/opencode/AGENTS.md has response format (once)" "rf_once '$d/AGENTS.md'"
    pass "every ~/.config/opencode agent has response format" "rf_every '$d/agents' '*.md'"
    pass "every ~/.config/opencode skill has response format" "rf_every '$d/skills' 'SKILL.md'"
    pass "plugins/post_code_hook_plugin.js exists (.js — OpenCode ignores .mjs)" "[ -f '$d/plugins/post_code_hook_plugin.js' ]"
    pass "no stale .mjs plugin remains" "[ ! -f '$d/plugins/post_code_hook_plugin.mjs' ]"
    pass "plugin placeholders substituted" "! grep -q '__.*_PATH__' '$d/plugins/post_code_hook_plugin.js'"
    pass "plugin wires pre-deploy check" "grep -q 'pre_deploy_check.sh' '$d/plugins/post_code_hook_plugin.js'"
    if has_jq; then
        pass "opencode.json has filesystem MCP under .mcp" "jq -e '.mcp.filesystem' '$d/opencode.json' >/dev/null"
    fi
}

# verify_pi_layout <dir> <label> — assert one Pi agent dir is fully provisioned.
verify_pi_layout() {
    local d="$1" label="$2"
    pass "skills in $label/skills/*/SKILL.md" "count_gt0 '$d/skills' 'SKILL.md' 3"
    pass "$label/AGENTS.md is System-Level Pi" "grep -q 'System-Level Pi' '$d/AGENTS.md'"
    pass "$label/AGENTS.md has ponytail ruleset (once)" "[ \"\$(grep -c 'ponytail:ruleset:start' '$d/AGENTS.md' 2>/dev/null)\" = 1 ]"
    pass "$label/AGENTS.md has response format (once)" "rf_once '$d/AGENTS.md'"
    pass "every $label skill has response format" "rf_every '$d/skills' 'SKILL.md'"
    pass "$label extensions/pi-checks.ts exists" "[ -f '$d/extensions/pi-checks.ts' ]"
    pass "$label extension hooks dir substituted" "! grep -q '__PI_HOOKS_DIR__' '$d/extensions/pi-checks.ts'"
    pass "$label extension wires pre-deploy check" "grep -q 'pre_deploy_check.sh' '$d/extensions/pi-checks.ts'"
}

verify_pi() {
    local omp_d="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}"
    soft "omp --version" "command -v omp >/dev/null && omp --version >/dev/null 2>&1"
    soft "pi --version" "command -v pi >/dev/null && pi --version >/dev/null 2>&1"
    pass "plain pi binary is installed" "command -v pi >/dev/null"
    verify_pi_layout "$HOME/.pi/agent" "~/.pi/agent"
    verify_pi_layout "$omp_d" "~/.omp/agent"
    if has_jq; then
        pass "omp mcp.json has filesystem MCP under .mcpServers" "jq -e '.mcpServers.filesystem' '$omp_d/mcp.json' >/dev/null"
    fi
}

verify_zcode() {
    local d="$HOME/.zcode"
    soft "ZCode app present" "[ -d /Applications/ZCode.app ] || [ -d '$HOME/Applications/ZCode.app' ]"
    pass "skills in ~/.zcode/skills/*/SKILL.md" "count_gt0 '$d/skills' 'SKILL.md' 3"
    pass "commands in ~/.zcode/commands/*.md" "count_gt0 '$d/commands' '*.md' 1"
    pass "~/.zcode/AGENTS.md is System-Level ZCode" "grep -q 'System-Level ZCode' '$d/AGENTS.md'"
    pass "~/.zcode/AGENTS.md has ponytail ruleset (once)" "[ \"\$(grep -c 'ponytail:ruleset:start' '$d/AGENTS.md' 2>/dev/null)\" = 1 ]"
    pass "~/.zcode/AGENTS.md has response format (once)" "rf_once '$d/AGENTS.md'"
    pass "every ~/.zcode skill has response format" "rf_every '$d/skills' 'SKILL.md'"
    pass "every ~/.zcode command has response format" "rf_every '$d/commands' '*.md'"
    if has_jq; then
        pass "config.json hooks are enabled" "jq -e '.hooks.enabled == true' '$d/cli/config.json' >/dev/null"
        pass "config.json has PostToolUse hook" "jq -e '.hooks.events.PostToolUse[0].hooks[0].command' '$d/cli/config.json' >/dev/null"
        pass "config.json Stop runs post-task battery" "jq -e '.hooks.events.Stop[0].hooks[0].command | test(\"post_task\")' '$d/cli/config.json' >/dev/null"
        pass "config.json has filesystem MCP under .mcp.servers" "jq -e '.mcp.servers.filesystem' '$d/cli/config.json' >/dev/null"
    fi
}

printf '\n=== Verifying %s ===\n' "$TOOL"
case "$TOOL" in
    claudecode) verify_claudecode ;;
    codex)      verify_codex ;;
    opencode)   verify_opencode ;;
    pi)         verify_pi ;;
    zcode)      verify_zcode ;;
    *) echo "Usage: $0 <claudecode|codex|opencode|pi|zcode>"; exit 2 ;;
esac

if [ "$FAILED" -eq 0 ]; then
    printf '\033[0;32m=== %s: all hard checks passed ===\033[0m\n\n' "$TOOL"
else
    printf '\033[0;31m=== %s: one or more hard checks FAILED ===\033[0m\n\n' "$TOOL"
fi
exit "$FAILED"

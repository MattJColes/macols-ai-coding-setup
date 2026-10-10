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
has_bun() { command -v bun &> /dev/null; }
# omp_yaml_has <file> <js expression over `doc`> — true when the expression is
# truthy for the parsed YAML. Bun is omp's own runtime, so it is present
# wherever omp is.
omp_yaml_has() {
    OMP_VERIFY_FILE="$1" OMP_VERIFY_EXPR="$2" bun -e '
import { YAML } from "bun";
const doc = YAML.parse(await Bun.file(process.env.OMP_VERIFY_FILE).text()) || {};
process.exit(new Function("doc", `return (${process.env.OMP_VERIFY_EXPR})`)(doc) ? 0 : 1);
' 2>/dev/null
}
has_ponytail_block() { grep -q 'ponytail:ruleset:start' "$1" 2>/dev/null; }
# brave-search is registered for OpenCode/pi/omp only, and only when a key file
# exists — so assert its presence or its absence, whichever the key implies.
has_brave_key() { [ -s "$HOME/.config/macols/brave-api-key" ]; }
# youtrack is registered for every tool once a URL and token are stored; the
# token stays in the header file, so the entry must never carry it inline.
has_youtrack() { [ -s "$HOME/.config/macols/youtrack-url" ] && [ -s "$HOME/.config/macols/youtrack-api-key" ]; }
# The AWS servers are opt-in for every tool; mirrors aws_mcp_enabled in lib/common.sh.
aws_on() {
    case "${MACOLS_AWS_MCP:-}" in
        1|y|Y|yes|true|on)  return 0 ;;
        0|n|N|no|false|off) return 1 ;;
    esac
    [ -s "$HOME/.config/macols/aws-mcp" ] && [ "$(tr -d '[:space:]' < "$HOME/.config/macols/aws-mcp")" = on ]
}

# mcp_checks <jq path to the server map> <file> <label> — the shared server
# list is present, retired servers are gone, and the opt-in / on-PATH servers
# appear exactly when they should.
mcp_checks() {
    local m="$1" f="$2" l="$3"
    pass "$l has playwright MCP" "jq -e '$m | .playwright' '$f' >/dev/null 2>&1"
    pass "$l has no retired context7/filesystem/puppeteer MCP" "! jq -e '$m | (.context7 // .filesystem // .puppeteer)' '$f' >/dev/null 2>&1"
    if aws_on; then
        pass "$l has the aws-* MCPs (opted in)" "jq -e '$m | .\"aws-mcp\" and .\"aws-iac\"' '$f' >/dev/null 2>&1"
    else
        pass "$l omits the aws-* MCPs (not opted in)" "! jq -e '$m | (.\"aws-mcp\" // .\"aws-iac\")' '$f' >/dev/null 2>&1"
    fi
    if has_youtrack; then
        pass "$l has youtrack MCP reading the header file, token not inlined" \
            "jq -e '$m.youtrack | tostring | contains(\"--header-file\") and (contains(\"Bearer\") | not)' '$f' >/dev/null 2>&1"
    else
        pass "$l omits youtrack MCP without a URL and token" \
            "! jq -e '$m.youtrack | tostring | contains(\"youtrack-api-key\")' '$f' >/dev/null 2>&1"
    fi
    if command -v gopls >/dev/null 2>&1; then
        pass "$l has gopls MCP (gopls on PATH)" "jq -e '$m.gopls' '$f' >/dev/null 2>&1"
    else
        pass "$l omits gopls MCP (gopls not on PATH)" "! jq -e '$m.gopls' '$f' >/dev/null 2>&1"
    fi
}

# The shared response-format block lands in the steering doc exactly once...
rf_once() { [ "$(grep -c '^## Response Format' "$1" 2>/dev/null)" = 1 ]; }
# ...and in every rendered persona, which carries its own system prompt.
# Upstream skills copied in beside the personas (hunk-review, .system) are not ours
# to render, so they are left out of the count.
# rf_every <dir> <find-name-pattern>
rf_every() {
    local have total
    have=$(grep -rl --exclude-dir=hunk-review --exclude-dir=.system '^## Response Format' "$1" 2>/dev/null | wc -l)
    total=$(find "$1" -type f -name "$2" -not -path '*/hunk-review/*' -not -path '*/.system/*' 2>/dev/null | wc -l)
    [ "$total" -gt 0 ] && [ "$have" -eq "$total" ]
}

# quality_tool_checks — the per-language tools ensure_quality_tools installs
# for the hook batteries and Fresh's language servers (lib/quality-tools.sh),
# and Fresh itself. Only for installs that ran the CLI step; ~/.local/bin is
# where the uv tools, Go, Flutter and Fresh links land.
quality_tool_checks() {
    local t
    for t in shellcheck jscpd ruff pyright mypy pytest lint-imports pylsp tsc eslint depcruise vitest jest \
             typescript-language-server prettier go gofmt golangci-lint gopls flutter dart fresh; do
        pass "hook tool on PATH: $t" "PATH=\"\$HOME/.local/bin:\$PATH\" command -v $t >/dev/null"
    done
}

# hunk_checks <skills_dir> <label> — the hunk-review skill is copied from the
# installed binary, so it is required whenever hunk is on PATH.
hunk_checks() {
    if command -v hunk >/dev/null 2>&1; then
        pass "$2 has the hunk-review skill" "grep -qs '^name: hunk-review' '$1/hunk-review/SKILL.md'"
    else
        warn "hunk not on PATH — skipping the $2 hunk-review skill check"
    fi
}

# Persona rendering contract shared by every skills dir: references/ travel
# with the skill, no rendered file leaks the source-only `tier:` key, and
# retired/renamed personas (review→audit, debug→diagnose, ...) are gone.
# persona_skill_checks <skills_dir> <label>
persona_skill_checks() {
    local d="$1" label="$2" r
    pass "$label editor skill ships references/" "[ -f '$d/editor/references/review-passes.md' ]"
    pass "$label skills carry no tier: key" "! grep -rqs '^tier:' '$d'"
    for r in coordinate linux ponytail review debug; do
        pass "$label has no retired '$r' persona" "[ ! -e '$d/$r' ]"
    done
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
    persona_skill_checks "$d/skills" "~/.claude"
    pass "only agent: true personas render as agents" "[ ! -e '$d/agents/python.md' ] && [ -f '$d/agents/audit.md' ]"
    pass "deep tier renders as effort: high (agent + skill)" \
        "grep -q '^effort: high' '$d/agents/audit.md' && grep -q '^effort: high' '$d/skills/audit/SKILL.md'"
    pass "light tier renders as effort: low" "grep -q '^effort: low' '$d/skills/explain/SKILL.md'"
    pass "~/.claude/bin/claude-launch is executable" "[ -x '$d/bin/claude-launch' ]"
    if has_jq; then
        pass "settings.json has PostToolUse hook"  "jq -e '.hooks.PostToolUse[0].hooks[0].command' '$d/settings.json' >/dev/null"
        pass "settings.json runs the commit checkpoint before git commit" "jq -e '[.hooks.PreToolUse[].hooks[].command | test(\"pre_commit_hook\")] | any' '$d/settings.json' >/dev/null"
        pass "settings.json hooks answer in Claude JSON (--format claude)" "jq -e '[.hooks[][].hooks[].command | test(\"--format claude\")] | all' '$d/settings.json' >/dev/null"
        mcp_checks '.mcpServers' "$HOME/.claude.json" '~/.claude.json'
    else
        warn "jq not available — skipping JSON assertions"
    fi
    # Ponytail lands either as an installed plugin (CLI path) or as a settings
    # declaration (offline fallback) — either satisfies the check.
    pass "ponytail plugin installed or declared" \
        "grep -qs 'ponytail@ponytail' '$d/plugins/installed_plugins.json' || grep -qs 'ponytail@ponytail' '$d/settings.json'"
    pass "no retired revdiff plugin declared" "! grep -qs 'revdiff@revdiff' '$d/settings.json'"
    soft "hunk binary installed" "command -v hunk >/dev/null 2>&1"
    hunk_checks "$d/skills" "~/.claude"
    soft "git worktree available" "git worktree list >/dev/null 2>&1 || git worktree --help >/dev/null 2>&1"
    soft "openspec CLI installed" "command -v openspec >/dev/null && openspec --version >/dev/null 2>&1"
    soft "openspec 'macols' schema installed user-level" "[ -f \"\${XDG_DATA_HOME:-\$HOME/.local/share}/openspec/schemas/macols/schema.yaml\" ]"
    soft "ast-grep CLI installed" "command -v ast-grep >/dev/null && ast-grep --version >/dev/null 2>&1"
    soft "yq CLI installed" "command -v yq >/dev/null 2>&1"
    soft "claude mcp list shows playwright" "command -v claude >/dev/null && claude mcp list 2>/dev/null | grep -q playwright"
    quality_tool_checks
}

verify_codex() {
    local d="$HOME/.codex"
    soft "codex --version" "command -v codex >/dev/null && codex --version >/dev/null 2>&1"
    pass "no legacy prompts dir (~/.codex/prompts removed)" "[ ! -d '$d/prompts' ]"
    pass "skills in ~/.codex/skills/*/SKILL.md"   "count_gt0 '$d/skills' 'SKILL.md' 3"
    pass "agents in ~/.codex/agents/*.toml"       "count_gt0 '$d/agents' '*.toml' 1"
    pass "agent toml has developer_instructions"  "grep -q 'developer_instructions' '$d/agents/audit.toml'"
    pass "~/.codex/AGENTS.md is System-Level Codex" "grep -q 'System-Level Codex' '$d/AGENTS.md'"
    pass "~/.codex/AGENTS.md has ponytail ruleset (once)" "[ \"\$(grep -c 'ponytail:ruleset:start' '$d/AGENTS.md' 2>/dev/null)\" = 1 ]"
    pass "~/.codex/AGENTS.md has response format (once)" "rf_once '$d/AGENTS.md'"
    pass "every ~/.codex agent has response format"   "rf_every '$d/agents' '*.toml'"
    pass "every ~/.codex skill has response format"   "rf_every '$d/skills' 'SKILL.md'"
    persona_skill_checks "$d/skills" "~/.codex"
    pass "codex skills carry no effort: key" "! grep -rqs '^effort:' '$d/skills'"
    pass "deep tier renders as model_reasoning_effort = high" "grep -q '^model_reasoning_effort = \"high\"' '$d/agents/audit.toml'"
    pass "no retired review/debug agent TOML" "[ ! -e '$d/agents/review.toml' ] && [ ! -e '$d/agents/debug.toml' ]"
    if has_jq; then
        pass "hooks.json top level is Codex's description/hooks" "jq -e '[keys[] | select(. != \"description\" and . != \"hooks\")] | length == 0' '$d/hooks.json' >/dev/null"
        pass "hooks.json has PostToolUse hook"     "jq -e '.hooks.PostToolUse[0].hooks[0].command' '$d/hooks.json' >/dev/null"
        pass "hooks.json Stop runs post-task battery" "jq -e '.hooks.Stop[0].hooks[0].command | test(\"post_task\")' '$d/hooks.json' >/dev/null"
        pass "hooks.json hooks answer in Codex JSON (--format codex)" "jq -e '[.hooks[][].hooks[].command | test(\"--format codex\")] | all' '$d/hooks.json' >/dev/null"
    fi
    soft "codex mcp list shows playwright" "command -v codex >/dev/null && codex mcp list 2>/dev/null | grep -q playwright"
    pass "no retired revdiff plugin enabled" "! grep -qs 'revdiff@revdiff' '$d/config.toml'"
    hunk_checks "$d/skills" "~/.codex"
    quality_tool_checks
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
    persona_skill_checks "$d/skills" "~/.config/opencode"
    pass "plugins/post_code_hook_plugin.js exists (.js — OpenCode ignores .mjs)" "[ -f '$d/plugins/post_code_hook_plugin.js' ]"
    pass "no stale .mjs plugin remains" "[ ! -f '$d/plugins/post_code_hook_plugin.mjs' ]"
    pass "plugin placeholders substituted" "! grep -q '__.*_PATH__' '$d/plugins/post_code_hook_plugin.js'"
    pass "plugin wires pre-deploy check" "grep -q 'pre_deploy_check.sh' '$d/plugins/post_code_hook_plugin.js'"
    pass "plugin handles session.idle as a bus event" "grep -q 'event?.type !== \"session.idle\"' '$d/plugins/post_code_hook_plugin.js'"
    pass "no retired revdiff plan-review plugin" "[ ! -e '$d/plugins/revdiff-plan-review.ts' ] && ! grep -qs 'revdiff-plan-review' '$d/opencode.json'"
    hunk_checks "$d/skills" "~/.config/opencode"
    if has_jq; then
        mcp_checks '.mcp' "$d/opencode.json" 'opencode.json .mcp'
        if has_brave_key; then
            pass "opencode.json has brave-search MCP reading the key file" \
                "jq -e '.mcp[\"brave-search\"].environment.BRAVE_API_KEY_FILE' '$d/opencode.json' >/dev/null"
        else
            pass "opencode.json omits brave-search MCP without a key" \
                "! jq -e '.mcp[\"brave-search\"]' '$d/opencode.json' >/dev/null"
        fi
    fi
    quality_tool_checks
}

# verify_pi_layout <dir> <label> — assert one Pi agent dir is fully provisioned.
verify_pi_layout() {
    local d="$1" label="$2"
    pass "skills in $label/skills/*/SKILL.md" "count_gt0 '$d/skills' 'SKILL.md' 3"
    pass "$label/AGENTS.md is System-Level Pi" "grep -q 'System-Level Pi' '$d/AGENTS.md'"
    pass "$label/AGENTS.md has no ponytail block (the package provides it)" "! grep -q 'ponytail:ruleset:start' '$d/AGENTS.md'"
    pass "$label/AGENTS.md has response format (once)" "rf_once '$d/AGENTS.md'"
    pass "every $label skill has response format" "rf_every '$d/skills' 'SKILL.md'"
    persona_skill_checks "$d/skills" "$label"
    hunk_checks "$d/skills" "$label"
    pass "$label extensions/pi-checks.ts exists" "[ -f '$d/extensions/pi-checks.ts' ]"
    pass "$label extension hooks dir substituted" "! grep -q '__PI_HOOKS_DIR__' '$d/extensions/pi-checks.ts'"
    pass "$label extension flavour substituted" "! grep -q '__PI_FLAVOUR__' '$d/extensions/pi-checks.ts'"
    pass "$label extension wires pre-deploy check" "grep -q 'pre_deploy_check.sh' '$d/extensions/pi-checks.ts'"
}

verify_pi() {
    local omp_d="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}"
    soft "omp --version" "command -v omp >/dev/null && omp --version >/dev/null 2>&1"
    soft "pi --version" "command -v pi >/dev/null && pi --version >/dev/null 2>&1"
    pass "plain pi binary is installed" "command -v pi >/dev/null"
    pass "no retired revdiff package (pi)" "! grep -qs 'umputun/revdiff' '$HOME/.pi/agent/settings.json'"
    pass "no retired revdiff package (omp)" "! grep -qs 'revdiff-pi' '$HOME/.omp/plugins/package.json'"
    soft "pi pi-yaml-hooks package installed" "grep -qs 'pi-yaml-hooks' '$HOME/.pi/agent/settings.json'"
    soft "omp pi-yaml-hooks package installed" "grep -qs 'pi-yaml-hooks' '$HOME/.omp/plugins/package.json'"
    soft "pi pi-mcp-adapter package installed" "grep -qs 'pi-mcp-adapter' '$HOME/.pi/agent/settings.json'"
    local p
    for p in pi-subagents ponytail pi-web-search pi-lens; do
        soft "pi $p package installed" "grep -qs '$p' '$HOME/.pi/agent/settings.json'"
    done
    verify_pi_layout "$HOME/.pi/agent" "~/.pi/agent"
    verify_pi_layout "$omp_d" "~/.omp/agent"
    if has_jq; then
        local f l
        for f in "$omp_d/mcp.json" "$HOME/.pi/agent/mcp-adapter.json"; do
            l="$(basename "$(dirname "$(dirname "$f")")")/$(basename "$f")"
            mcp_checks '.mcpServers' "$f" "$l .mcpServers"
            if has_brave_key; then
                pass "$l has brave-search MCP reading the key file" \
                    "jq -e '.mcpServers[\"brave-search\"].env.BRAVE_API_KEY_FILE' '$f' >/dev/null"
            else
                pass "$l omits brave-search MCP without a key" \
                    "! jq -e '.mcpServers[\"brave-search\"]' '$f' >/dev/null"
            fi
        done
    fi
    if has_bun; then
        local model_file
        for model_file in "$HOME/.pi/agent/models.json" "$omp_d/models.yml"; do
            if [ "$model_file" = "$omp_d/models.yml" ] && [ ! -f "$model_file" ]; then
                model_file="$omp_d/models.yaml"
            fi
            pass "$model_file registers the Swift LAN model" \
                "omp_yaml_has '$model_file' 'doc.providers?.[\"vllm-lan\"]?.models?.filter(m => m.id === \"ukisai/Swift-Qwen3.8-27B-NVFP4\").length === 1'"
        done
    fi
    if [ -f "$omp_d/models.yml" ] || [ -f "$omp_d/config.yml" ]; then
        if has_bun; then
            [ -f "$omp_d/models.yml" ] && pass "omp models.yml parses with a non-empty providers map" \
                "omp_yaml_has '$omp_d/models.yml' 'doc.providers && Object.keys(doc.providers).length > 0'"
            [ -f "$omp_d/config.yml" ] && soft "omp config.yml assigns modelRoles.default" \
                "omp_yaml_has '$omp_d/config.yml' 'typeof doc.modelRoles?.default === \"string\"'"
        else
            warn "bun not available — skipping omp model config assertions"
        fi
        # Keys belong in a mode-600 file referenced as `!cat ...`, never inline.
        [ -f "$omp_d/models.yml" ] && pass "omp models.yml references API keys instead of inlining them" \
            "! grep -qE '^[[:space:]]+apiKey: \"?(sk-|gsk_|xai-|AIza)' '$omp_d/models.yml'"
    else
        warn "omp models not configured — run ./install.sh pi --models-only to pick them"
    fi
    quality_tool_checks
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
    persona_skill_checks "$d/skills" "~/.zcode"
    hunk_checks "$d/skills" "~/.zcode"
    pass "single-file /editor command inlines its references" "grep -q '^### references/review-passes.md' '$d/commands/editor.md'"
    if has_jq; then
        pass "config.json hooks are enabled" "jq -e '.hooks.enabled == true' '$d/cli/config.json' >/dev/null"
        pass "config.json has PostToolUse hook" "jq -e '.hooks.events.PostToolUse[0].hooks[0].args[0]' '$d/cli/config.json' >/dev/null"
        pass "config.json Stop runs post-task battery" "jq -e '.hooks.events.Stop[0].hooks[0].args[0] | test(\"post_task\")' '$d/cli/config.json' >/dev/null"
        pass "config.json hooks are ZCode process hooks with timeoutMs" "jq -e '[.hooks.events[][].hooks[] | .type == \"process\" and (.timeoutMs | type == \"number\") and (.args | index(\"zcode\"))] | all' '$d/cli/config.json' >/dev/null"
        mcp_checks '.mcp.servers' "$d/cli/config.json" 'config.json .mcp.servers'
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

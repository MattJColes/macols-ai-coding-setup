#!/usr/bin/env bash
#
# lib/hooks.sh — Hook wiring: writes each tool's hook config pointing at hooks/ in place.
#
# Sourced by lib/common.sh, which sets the colours and repo layout variables
# used here. Not meant to be executed directly.
# shellcheck disable=SC2034  # variables here are read by other modules/installers

# ── Hook wiring ──────────────────────────────────────────────────────────────
# Hooks are referenced in place from hooks/ (not copied), so the shared
# check libraries resolve correctly via the wrappers' relative path.

CODE_HOOK="$HOOKS_DIR/post_code_hook.sh"
TASK_HOOK="$HOOKS_DIR/post_task_hook.sh"
PRE_DEPLOY_HOOK="$HOOKS_DIR/pre_deploy_hook.sh"
PRE_DEPLOY_CHECK="$HOOKS_DIR/pre_deploy_check.sh"
# Local checkpoint: `git commit` runs the checkpoint battery first.
PRE_COMMIT_HOOK="$HOOKS_DIR/pre_commit_hook.sh"
PRE_COMMIT_CHECK="$HOOKS_DIR/pre_commit_check.sh"

check_hook_sources() {
    local f
    for f in "$CHECKS_DIR/common.sh" "$CHECKS_DIR/post_code.sh" "$CHECKS_DIR/post_task.sh" "$ADAPTERS_DIR/hook_output.sh" "$@"; do
        [ -f "$f" ] || { printf "${RED}Required file not found: %s${NC}\n" "$f"; return 1; }
    done
    chmod +x "$@" 2>/dev/null || true
}

# write_claude_hooks <settings_file>
write_claude_hooks() {
    require_node || return 1
    check_hook_sources "$CODE_HOOK" "$TASK_HOOK" "$PRE_DEPLOY_HOOK" "$PRE_COMMIT_HOOK" "$PRE_COMMIT_CHECK" || return 1
    mkdir -p "$(dirname "$1")"
    SETTINGS_FILE="$1" HOOK_SCRIPT="$CODE_HOOK" TASK_HOOK_SCRIPT="$TASK_HOOK" PRE_DEPLOY_HOOK_SCRIPT="$PRE_DEPLOY_HOOK" PRE_COMMIT_HOOK_SCRIPT="$PRE_COMMIT_HOOK" node -e '
const fs = require("fs"), env = process.env;
let existing = {};
if (fs.existsSync(env.SETTINGS_FILE)) { try { existing = JSON.parse(fs.readFileSync(env.SETTINGS_FILE, "utf8")); } catch (e) {} }
// --format claude makes the hooks answer in the Claude JSON shape: PostToolUse
// additionalContext and a one-shot Stop decision:block, both model-visible
// (plain stdout on exit 0 only reaches the debug log).
existing.hooks = {
    PreToolUse: [{ matcher: "Bash", hooks: [
        { type: "command", command: env.PRE_DEPLOY_HOOK_SCRIPT + " --format claude", timeout: 30 },
        { type: "command", command: env.PRE_COMMIT_HOOK_SCRIPT + " --format claude", timeout: 900 }
    ] }],
    PostToolUse: [{ matcher: "Edit|Write|NotebookEdit", hooks: [{ type: "command", command: env.HOOK_SCRIPT + " --format claude", timeout: 120 }] }],
    Stop: [{ hooks: [
        { type: "command", command: env.TASK_HOOK_SCRIPT + " --format claude", timeout: 600 }
    ] }]
};
// Hard safety the model cannot talk itself out of: deny reads of AWS
// credentials. Bypass ("yolo") mode stays available.
existing.permissions = existing.permissions || {};
const deny = new Set(existing.permissions.deny || []);
deny.add("Read(~/.aws/**)"); deny.add("Read(./.aws/**)");
existing.permissions.deny = [...deny];
delete existing.disableBypassPermissionsMode;
fs.writeFileSync(env.SETTINGS_FILE, JSON.stringify(existing, null, 2) + "\n");
'
    printf "${GREEN}✓ Hooks, permissions and safety settings written to %s${NC}\n" "$1"
}

# install_claude_launcher <claude_dir> — install the root-safe launcher that lets
# --dangerously-skip-permissions work by dropping from root to a non-root user
# instead of running the agent as root (which Claude Code refuses).
install_claude_launcher() {
    local dir="$1/bin" src="$REPO_ROOT/bin/claude-launch.sh"
    [ -f "$src" ] || { printf "${RED}launcher source not found: %s${NC}\n" "$src"; return 1; }
    mkdir -p "$dir"
    install -m 0755 "$src" "$dir/claude-launch"
    printf "${GREEN}✓ Installed root-safe launcher to %s/claude-launch${NC}\n" "$dir"
}

# write_codex_hooks <hooks_json>
write_codex_hooks() {
    require_node || return 1
    check_hook_sources "$CODE_HOOK" "$TASK_HOOK" "$PRE_DEPLOY_HOOK" "$PRE_COMMIT_HOOK" "$PRE_COMMIT_CHECK" || return 1
    mkdir -p "$(dirname "$1")"
    HOOKS_JSON="$1" HOOK_SCRIPT="$CODE_HOOK" TASK_HOOK_SCRIPT="$TASK_HOOK" PRE_DEPLOY_HOOK_SCRIPT="$PRE_DEPLOY_HOOK" PRE_COMMIT_HOOK_SCRIPT="$PRE_COMMIT_HOOK" node -e '
const fs = require("fs"), env = process.env;
// Codex deserialises hooks.json into a struct with deny_unknown_fields that
// accepts only "description" and "hooks". The event map is nested under
// "hooks" — a Claude-style flat file fails with `unknown field PreToolUse`.
// Matchers: Codex maps its apply_patch tool onto the Write/Edit aliases, so
// the Claude-style matcher strings select the same edits; the post-code hook
// reads the edited paths from the patch text in tool_input.command.
// --format codex: Codex has no "ask" (unsupported decisions fail open), so
// the deploy guard denies once and lets an identical retry through.
const config = {
    description: "macols-ai-coding-setup quality and safety hooks",
    hooks: {
        PreToolUse: [{ matcher: "Bash", hooks: [
            { type: "command", command: env.PRE_DEPLOY_HOOK_SCRIPT + " --format codex", timeout: 30 },
            { type: "command", command: env.PRE_COMMIT_HOOK_SCRIPT + " --format codex", timeout: 900 }
        ] }],
        PostToolUse: [{ matcher: "Edit|Write", hooks: [{ type: "command", command: env.HOOK_SCRIPT + " --format codex", timeout: 120 }] }],
        // Stop mirrors Claude: the turn-end battery, one decision:block nudge.
        Stop: [{ hooks: [
            { type: "command", command: env.TASK_HOOK_SCRIPT + " --format codex", timeout: 600 }
        ] }]
    }
};
fs.writeFileSync(env.HOOKS_JSON, JSON.stringify(config, null, 2) + "\n");
'
    printf "${GREEN}✓ Hooks written to %s${NC}\n" "$1"
    printf "${YELLOW}  Codex only runs hooks you have trusted: open Codex and approve the macols hooks (again after each change to them).${NC}\n"
}

# write_zcode_hooks <config_json> — merge the hooks into ZCode's config.json
# under hooks.events. Config-file hooks only fire when hooks.enabled is true.
# ZCode runs "process" hooks (argv, no shell) with timeouts in timeoutMs, and
# only JSON stdout reaches the model. Existing keys elsewhere in the config
# (mcp, plugins, …) survive.
write_zcode_hooks() {
    require_node || return 1
    check_hook_sources "$CODE_HOOK" "$TASK_HOOK" "$PRE_DEPLOY_HOOK" "$PRE_COMMIT_HOOK" "$PRE_COMMIT_CHECK" || return 1
    mkdir -p "$(dirname "$1")"
    HOOKS_JSON="$1" HOOK_SCRIPT="$CODE_HOOK" TASK_HOOK_SCRIPT="$TASK_HOOK" PRE_DEPLOY_HOOK_SCRIPT="$PRE_DEPLOY_HOOK" PRE_COMMIT_HOOK_SCRIPT="$PRE_COMMIT_HOOK" node -e '
const fs = require("fs"), env = process.env;
let cfg = {};
if (fs.existsSync(env.HOOKS_JSON)) { try { cfg = JSON.parse(fs.readFileSync(env.HOOKS_JSON, "utf8")); } catch (e) {} }
// Same events as the Claude settings hooks. Matchers are regexes over the
// tool name; Write/Edit alias the apply-patch tool, as in the Codex hooks.
const hook = (script, timeoutMs) => ({ type: "process", command: "bash", args: [script, "--format", "zcode"], timeoutMs });
cfg.hooks = {
    ...(cfg.hooks || {}),
    enabled: true,
    events: {
        PreToolUse: [{ matcher: "Bash", hooks: [hook(env.PRE_DEPLOY_HOOK_SCRIPT, 30000), hook(env.PRE_COMMIT_HOOK_SCRIPT, 900000)] }],
        PostToolUse: [{ matcher: "Edit|Write|NotebookEdit", hooks: [hook(env.HOOK_SCRIPT, 120000)] }],
        Stop: [{ hooks: [hook(env.TASK_HOOK_SCRIPT, 600000)] }]
    }
};
fs.writeFileSync(env.HOOKS_JSON, JSON.stringify(cfg, null, 2) + "\n");
'
    printf "${GREEN}✓ Hooks written to %s${NC}\n" "$1"
}

# install_opencode_plugin <plugins_dir>
# The installed file must be .js — OpenCode's plugin loader scans only
# *.ts and *.js, so a .mjs plugin is silently never loaded.
install_opencode_plugin() {
    check_hook_sources "$CODE_HOOK" "$TASK_HOOK" "$PRE_DEPLOY_CHECK" "$PRE_COMMIT_CHECK" "$ADAPTERS_DIR/opencode_plugin.mjs" || return 1
    mkdir -p "$1"
    rm -f "$1/post_code_hook_plugin.mjs" "$1/post_code_hook_env.mjs"
    sed -e "s|__HOOK_SCRIPT_PATH__|${CODE_HOOK}|g" \
        -e "s|__TASK_HOOK_SCRIPT_PATH__|${TASK_HOOK}|g" \
        -e "s|__PRE_DEPLOY_CHECK_PATH__|${PRE_DEPLOY_CHECK}|g" \
        -e "s|__PRE_COMMIT_CHECK_PATH__|${PRE_COMMIT_CHECK}|g" \
        "$ADAPTERS_DIR/opencode_plugin.mjs" > "$1/post_code_hook_plugin.js"
    printf "${GREEN}✓ Plugin installed to %s${NC}\n" "$1/post_code_hook_plugin.js"
}

# install_pi_extension <extensions_dir> <pi|omp> — bake the repo hooks dir and
# the agent flavour into pi-checks.ts (the turn-end event differs: pi's
# agent_before_settle vs omp's session_stop).
install_pi_extension() {
    check_hook_sources "$CODE_HOOK" "$TASK_HOOK" "$PRE_DEPLOY_CHECK" "$PRE_COMMIT_CHECK" "$ADAPTERS_DIR/pi-checks.ts" || return 1
    mkdir -p "$1"
    sed -e "s#__PI_HOOKS_DIR__#$HOOKS_DIR#g" -e "s#__PI_FLAVOUR__#${2:-pi}#g" "$ADAPTERS_DIR/pi-checks.ts" > "$1/pi-checks.ts"
    printf "${GREEN}✓ Extension installed to %s${NC}\n" "$1/pi-checks.ts"
}

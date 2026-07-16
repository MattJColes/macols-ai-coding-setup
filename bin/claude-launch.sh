#!/usr/bin/env bash
#
# claude-launch — launch Claude Code with --dangerously-skip-permissions,
# safely, even from contexts that start out as root.
#
# Why this exists: Claude Code refuses to start in bypassPermissions mode under
# root/sudo ("--dangerously-skip-permissions cannot be used with root/sudo
# privileges for security reasons"). Install scripts and containers commonly run
# as root, so the flag silently drops back to the default permission mode.
#
# This wrapper resolves the situation the documented way — by running Claude as
# a NON-root user rather than trying to override the safety check:
#
#   • Not root            → exec `claude --dangerously-skip-permissions "$@"`.
#   • Root, user resolved → re-exec as that user via sudo, same arguments.
#   • Root, no user       → fail loudly with guidance (don't run blind as root).
#
# Target user resolution order (first non-root wins):
#   1. $CLAUDE_USER   — explicit override
#   2. $SUDO_USER     — the user who invoked sudo
#   3. owner of $HOME — the human this shell belongs to
#
# NOTE: for the drop-privileges path to be coherent, Claude Code and its config
# (~/.claude) should belong to that same non-root user. The cleanest setup is to
# install AND run Claude as the non-root user from the start; this wrapper is the
# safety net for when something lands you at a root prompt.
set -euo pipefail

readonly FLAG="--dangerously-skip-permissions"

die() { printf 'claude-launch: %s\n' "$1" >&2; exit 1; }

resolve_claude() {
    command -v claude 2>/dev/null || die "claude CLI not found on PATH"
}

# ── Non-root: run directly ───────────────────────────────────────────────────
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    exec "$(resolve_claude)" "$FLAG" "$@"
fi

# ── Root: resolve a non-root user to drop to ─────────────────────────────────
target=""
for candidate in "${CLAUDE_USER:-}" "${SUDO_USER:-}" "$(stat -c '%U' "$HOME" 2>/dev/null || stat -f '%Su' "$HOME" 2>/dev/null || true)"; do
    [ -n "$candidate" ] || continue
    [ "$candidate" = "root" ] && continue
    id "$candidate" >/dev/null 2>&1 || continue
    target="$candidate"
    break
done

if [ -z "$target" ]; then
    die "running as root and no non-root user found.
  Set CLAUDE_USER=<username> to pick one, e.g. CLAUDE_USER=builder claude-launch
  (If this container IS your sandbox and root is intentional, the documented
   escape hatch is: IS_SANDBOX=1 claude $FLAG — but prefer a non-root user.)"
fi

command -v sudo >/dev/null 2>&1 || die "need sudo to drop from root to '$target', but sudo is not installed"

# Claude must be on the target user's PATH — a root-only install (e.g. under
# /root/.local/bin) won't be reachable. Fail with guidance rather than a bare
# "command not found" from sudo.
if ! sudo -u "$target" -H -- bash -lc 'command -v claude >/dev/null 2>&1'; then
    die "user '$target' has no 'claude' on their PATH.
  Install Claude Code as '$target' (recommended), or system-wide, so the
  dropped-privilege launch can find it. A root-only install is not reachable."
fi

printf 'claude-launch: running as root — dropping to non-root user "%s"\n' "$target" >&2
exec sudo -u "$target" -H -- bash -lc 'exec claude "$@"' claude "$FLAG" "$@"

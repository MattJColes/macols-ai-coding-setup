# Getting Started: Herdr + Yazi + Claude Code

A workflow guide for using Herdr as your terminal workspace manager, Yazi as your file navigator, and Claude Code working in git worktrees so you can watch its work live.

## Quick Install

```bash
bash ~/Downloads/install_brew_herdr_yazi_lazygit_nvim.sh
```

This installs everything: Herdr, Yazi, Neovim (LazyVim), lazygit, delta, and tmux.

---

## 1. Launching Herdr

Start Herdr from any terminal:

```bash
herdr
```

This creates (or attaches to) a persistent session. Your workspace survives terminal closes.

### Named sessions

```bash
herdr --session myproject
```

### Detach and reattach

- Detach: `Ctrl+b` then `q`
- Reattach: just run `herdr` again

---

## 2. Herdr Pane Management

All Herdr commands start with the prefix key `Ctrl+b`.

| Action | Keys |
|--------|------|
| Split vertical | `Ctrl+b` then `v` |
| Split horizontal | `Ctrl+b` then `-` |
| Focus left pane | `Ctrl+b` then `h` |
| Focus down pane | `Ctrl+b` then `j` |
| Focus up pane | `Ctrl+b` then `k` |
| Focus right pane | `Ctrl+b` then `l` |
| Cycle panes | `Ctrl+b` then `Tab` |
| Close pane | `Ctrl+b` then `x` |
| Zoom/fullscreen pane | `Ctrl+b` then `z` |
| Resize mode | `Ctrl+b` then `r` |
| Toggle sidebar | `Ctrl+b` then `b` |

### Tabs

| Action | Keys |
|--------|------|
| New tab | `Ctrl+b` then `c` |
| Next tab | `Ctrl+b` then `n` |
| Previous tab | `Ctrl+b` then `p` |
| Switch to tab N | `Ctrl+b` then `1-9` |
| Rename tab | `Ctrl+b` then `Shift+t` |
| Close tab | `Ctrl+b` then `Shift+x` |

### Workspaces

| Action | Keys |
|--------|------|
| Workspace picker | `Ctrl+b` then `w` |
| New workspace | `Ctrl+b` then `Shift+n` |
| Rename workspace | `Ctrl+b` then `Shift+w` |
| Close workspace | `Ctrl+b` then `Shift+d` |
| New worktree | `Ctrl+b` then `Shift+g` |

### Plugin keybindings (installed by the setup script)

| Action | Keys |
|--------|------|
| herdr-plus project picker | `Ctrl+b` then `p` |
| Toggle reviewr | `Cmd+r` |
| Browser in a right split | `Ctrl+b` then `Shift+b` |
| Browser overlay | `Ctrl+b` then `Shift+o` |

The browser keys are `Shift`-ed because plain `Ctrl+b` then `b` is herdr's own
sidebar toggle.

The herdr-plus **worktree layout** (`repo = "*"`) applies to every repo: each
new worktree opens with Claude Code (`--dangerously-skip-permissions`) on the
left and Yazi split right, automatically.

### Help

Press `Ctrl+b` then `?` to see all keybindings.

---

## 3. Recommended Layout

Set up a three-pane layout for active development:

```
+-------------------+------------------+
|                   |                  |
|   Claude Code     |   Yazi / Editor  |
|   (git worktree)  |                  |
|                   |                  |
+-------------------+------------------+
```

1. Start Herdr: `herdr`
2. In the first pane, launch Claude in its own git worktree (see section 5)
3. Split vertical: `Ctrl+b` then `v`
4. In the second pane, launch Yazi: `yazi`

With the herdr-plus worktree layout installed, `Ctrl+b` then `Shift+g` gives
you this layout automatically in a fresh worktree.

---

## 4. Using Yazi

Launch Yazi in any pane:

```bash
yazi
```

### Navigation

| Action | Keys |
|--------|------|
| Move up/down | `k` / `j` |
| Enter directory | `l` or `Enter` |
| Go up a directory | `h` |
| Go to top/bottom | `g g` / `G` |
| Search files | `/` |
| Toggle hidden files | `.` |
| Quit | `q` |

### Git Integration (custom keybindings)

| Action | Keys |
|--------|------|
| Open lazygit | `g i` |
| Show git changed files | `g c` |
| Full-screen git diff for file | `g d` |

The preview pane automatically shows inline diffs (via delta) for any file with uncommitted changes.

### File Operations

| Action | Keys |
|--------|------|
| Open file in $EDITOR | `Enter` |
| Copy file(s) | `y` |
| Cut file(s) | `x` |
| Paste | `p` |
| Delete | `d` |
| Rename | `r` |
| Create file | `a` (type name, Enter) |
| Create directory | `a` (type name/, Enter) |
| Select/deselect | `Space` |
| Select all | `Ctrl+a` |

### Opening Files in Neovim

When you press `Enter` on a file, Yazi opens it in `$EDITOR` (nvim). After editing, exit nvim to return to Yazi.

---

## 5. Claude Code in a Git Worktree

Each agent works in its own git worktree -- a separate directory checked out on
its own branch -- so several agents can run in parallel without colliding in
one checkout. Three ways to get one:

1. **Herdr built-in**: `Ctrl+b` then `Shift+g` creates a new worktree for the
   current repo. With the herdr-plus worktree layout installed, the new tab
   opens with Claude Code on the left and Yazi split right, automatically.
2. **herdr-plus project picker**: `Ctrl+b` then `p` opens the project layouts
   (the default "Dev (Claude + Yazi)" layout launches the same split).
3. **Manually**:

```bash
git worktree add ../myrepo-feat-x -b feat/x
cd ../myrepo-feat-x
claude
```

Claude will:
- Edit files on the worktree's branch, committing in small conventional commits
- Leave every in-flight branch visible in `git log --oneline --graph --all`

### Watching Claude's changes live

In your Yazi pane the git-peek preview shows diffs as Claude writes code.
Use `g c` to see which files Claude has modified, or run `git status` /
`git diff` in any pane of the same worktree.

### Typical workflow

1. Pane 1: create a worktree (`Ctrl+b` `Shift+g`, or `git worktree add ../repo-task -b feat/task && cd ../repo-task`) then `claude` -- give Claude a task
2. Pane 2: `yazi` -- watch diffs appear in preview, or `git log --oneline --graph --all` to see all agents' branches
3. Review with `git diff main...feat/task` (lazygit via `g i` still works for browsing history)
4. When satisfied: `git push -u origin feat/task`, then open a PR
5. After merge: `git worktree remove ../repo-task && git branch -d feat/task`

If something goes sideways, `git reflog` finds the commit you were on before
things went wrong.

---

## 6. Browser Panes (herdr-browser)

`herdr-browser` renders a real Chromium view inside a herdr pane, so you can
watch a dev server or an agent's browser automation without leaving the
terminal. The setup script installs the plugin, `bun`, Chrome/Chromium, and the
`[experimental] kitty_graphics = true` flag herdr needs to draw into a pane.

It only works in a terminal with Kitty graphics support: Ghostty, kitty or
WezTerm. It does not work over plain SSH into a non-graphics terminal, and
per-frame bandwidth makes remote use impractical.

### Opening a browser

| Action | Keys |
|--------|------|
| Browser in a right split | `Ctrl+b` then `Shift+b` |
| Browser overlay | `Ctrl+b` then `Shift+o` |

Or open one at a specific URL:

```bash
herdr plugin pane open --plugin official.browser --entrypoint browser \
  --placement split --direction right \
  --env HERDR_BROWSER_INITIAL_URL=http://127.0.0.1:3000 --focus
```

`Ctrl`-click any `localhost`, `127.0.0.1` or `[::1]` URL printed in a terminal
pane to open it in a browser pane.

### Letting an agent drive it

The plugin ships a CLI (no global binary). Find the checkout, then attach a CDP
client:

```bash
herdr plugin list --plugin official.browser --json   # read result.plugins[0].plugin_root
bun run "<plugin_root>/src/cli.ts" views
bun run "<plugin_root>/src/cli.ts" connect --view <view_id>
```

`connect` returns a loopback CDP endpoint. Point Playwright at it with
`chromium.connectOverCDP(<cdp_http_url>)`, Playwright MCP with
`--cdp-endpoint=<cdp_http_url>`, or Browser Use with `BU_CDP_URL`. The pane
stays interactive while a client is attached, so you can take over mid-run.
Keep the endpoint local — it grants full control of that browser view.

### Tuning

Config lives in `browser.json` under `herdr plugin config-dir official.browser`.
If a browser pane costs more CPU than you want, drop `captureScale` to `0.75`.
If Chromium is installed somewhere the plugin cannot find, export
`HERDR_BROWSER_CHROME=/path/to/chrome` in the environment that starts the herdr
server and restart herdr.

---

## 7. Neovim (LazyVim) Quick Reference

When you open a file from Yazi, it launches in Neovim with LazyVim.

### Essential shortcuts

| Action | Keys |
|--------|------|
| Save file | `Space` then `w` (or `:w`) |
| Quit | `Space` then `q` (or `:q`) |
| File explorer | `Space` then `e` |
| Find file | `Space` then `f f` |
| Search in files (grep) | `Space` then `s g` |
| Buffer list | `Space` then `,` |
| Close buffer | `Space` then `b d` |
| Split vertical | `Space` then `\|` |
| Split horizontal | `Space` then `-` |
| Terminal | `Space` then `f t` |

### Getting help

| Action | Keys |
|--------|------|
| Show all keybindings | `Space` then `s k` |
| Which-key popup (wait) | Press `Space` and wait |
| Command palette | `Space` then `:` |
| LazyVim dashboard | `Space` then `l` |

The which-key popup is your best friend -- press `Space` and pause for 300ms to see all available leader-key commands grouped by category.

### Movement basics

| Action | Keys |
|--------|------|
| Word forward/back | `w` / `b` |
| Start/end of line | `0` / `$` |
| Go to line N | `N G` |
| Go to definition | `g d` |
| Go back | `Ctrl+o` |
| Find references | `g r` |

---

## 8. Putting It All Together

```bash
# Start your workspace
herdr --session dev

# Pane 1: Claude doing work in its own git worktree
# (or just Ctrl+b, Shift+g — the herdr-plus layout opens Claude + Yazi for you)
git worktree add ../myrepo-the-task -b feat/the-task
cd ../myrepo-the-task
claude

# Ctrl+b, v to split

# Pane 2: Navigate and watch changes
yazi

# Inside Yazi:
#   g c  -> see what Claude changed
#   g d  -> see the diff
#   Enter -> open file in nvim to edit
# In any shell pane:
#   git log --oneline --graph --all   -> all in-flight branches (every agent)
#   git diff main...feat/the-task     -> review one branch
#   git push -u origin feat/the-task  -> publish, then open a PR
```

### Tips

- Use `Ctrl+b` then `z` to zoom any pane to fullscreen (toggle)
- Use `Ctrl+b` then `?` if you forget a Herdr keybinding
- In Yazi, the preview pane auto-shows diffs -- no action needed
- In nvim, press `Space` and wait to discover commands via which-key
- Herdr sessions persist -- close your terminal and `herdr` picks up where you left off

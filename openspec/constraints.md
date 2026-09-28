# Constraint Register

The standing rules every change in this repo is held to. Proposals cite them by
id in their Constraints section (one line on why each applies) instead of
copying the text, and evidence.md proves the ones a change could break.

- Ids are `C-UPPER-KEBAB`. They are never renumbered or reused.
- To retire a rule, keep its row, mark the Rule `Retired YYYY-MM-DD: <reason>`
  and leave the id unused from then on.
- **Source** is the authoritative doc section. **Guard** is a test or check that
  already fails when the rule is broken; `Review` means nothing automated
  catches it, so a reviewer must.
- Add a rule when a change relies on one that has no id and is likely to be
  cited again, in that same change.

| Id | Rule | Source | Guard |
|---|---|---|---|
| C-EDIT-SOURCE-NOT-OUTPUT | Change `config/` or `hooks/` and rerun the installer; never edit the rendered files under `~/.claude`, `~/.codex`, `~/.config/opencode`, `~/.pi`, `~/.omp` or `~/.zcode`. | [AGENTS.md: Change routing](../AGENTS.md#change-routing) | Review |
| C-BUNDLE-REGENERATED | Adding, editing, renaming or removing a persona ships the regenerated `dist/macols-personas-claude-plugin.zip` in the same change. | [AGENTS.md: Change routing (Personas)](../AGENTS.md#change-routing) | `./scripts/package_claude_desktop_personas.sh --check` (CI `test-installers` / shellcheck job) |
| C-INSTALL-IDEMPOTENT | Re-running an installer never duplicates config; blocks that may change are marker-delimited and replaced. | [AGENTS.md: Conventions](../AGENTS.md#conventions-follow-these-in-every-installer-change) | `./tests/verify_install.sh <tool>` "(once)" checks for the response-format and ponytail blocks (CI install matrix); other blocks: Review |
| C-MERGE-USER-CONFIG | User-owned config (herdr, OpenCode, omp models, ZCode) is merged, never overwritten; only files this repo fully owns are rewritten. | [AGENTS.md: Conventions](../AGENTS.md#conventions-follow-these-in-every-installer-change) | Review |
| C-OPTIONAL-NON-FATAL | An optional install step that fails warns and lets the install carry on. | [AGENTS.md: Conventions](../AGENTS.md#conventions-follow-these-in-every-installer-change) | Review |
| C-PORTABLE-SHELL | Scripts run on macOS and Ubuntu 24/26: branch on `$OSTYPE`, never use `sed -i` (filter to a temp file and `mv` it back). | [AGENTS.md: Conventions](../AGENTS.md#conventions-follow-these-in-every-installer-change) | Review |
| C-BASH-SOURCE-PATHS | Scripts resolve sibling and parent paths from `${BASH_SOURCE[0]}` once at the top, never from `$0` after a `cd`. | [AGENTS.md: Rule on script paths](../AGENTS.md#rule-resolve-script-paths-from-bash_source0-never-0-after-a-cd) | Review |
| C-SHELLCHECK-CLEAN | Every shell script passes shellcheck at warning severity, including when checked file by file. | [AGENTS.md: Verifying changes](../AGENTS.md#verifying-changes) | CI `shellcheck` (`.github/workflows/test-installers.yml`) and `Shell Script Analysis` (`.github/workflows/security-scanning.yml`) |
| C-SPEC-ANCHORS-HEALTHY | Every anchor rule resolves to exactly one code site; when anchored behaviour changes, the matching spec section changes with it. | [AGENTS.md: Specs](../AGENTS.md#change-routing) | `./scripts/spec_drift_gate.sh --check` (CI `spec-anchors`) for hygiene; the spec-update half is only the advisory `--github` drift pass, so also Review |
| C-HOOKS-MODEL-VISIBLE | Every hook wiring passes `--format <tool>` so findings reach the model; plain stdout on exit 0 is never relied on. | [docs/hooks.md](../docs/hooks.md) | `./tests/verify_install.sh` "--format claude", "--format codex" and ZCode process-hook checks (CI install matrix) |
| C-TRUSTED-REPO-CODE | Hook checks that run repository-controlled code (tests, `.venv`/`node_modules` tools, executable configs, project commands) run only when `project_trusted` accepts the project. | [docs/hooks.md: Trusted Projects](../docs/hooks.md#trusted-projects) | Review |
| C-SECRETS-OUT-OF-CONFIG | API keys live in `~/.config/macols/*-key` files (mode 600) and are referenced, never inlined into rendered config or committed. | [AGENTS.md: omp models](../AGENTS.md#change-routing) | `./tests/verify_install.sh pi` "references API keys instead of inlining them"; Gitleaks (`Scan for Secrets`) for committed secrets |
| C-NO-JUJUTSU | Version control is plain git with worktrees; jj is not reintroduced in installers, steering or docs. | [AGENTS.md: Conventions](../AGENTS.md#conventions-follow-these-in-every-installer-change) | Review |
| C-OPENSPEC-OPT-IN | Installers provision the OpenSpec and ast-grep CLIs only; they never run `openspec init` or create spec anchors in a user's repo. | [AGENTS.md: Conventions](../AGENTS.md#conventions-follow-these-in-every-installer-change) | Review |
| C-RESPONSE-FORMAT-CHAT-ONLY | `config/steering/response-format.md` governs chat replies only; it is never widened to authored content. | [AGENTS.md: Response format](../AGENTS.md#change-routing) | Review |

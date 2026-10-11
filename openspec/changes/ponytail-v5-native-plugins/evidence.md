# Evidence

All runs use a scratch `$HOME` and the repo's real entry points. Codex 0.162.1 and OpenCode 1.19.0 came from npm into a scratch prefix on PATH. Base HEAD b9806d1291b034e04623e3dd167404df8515943e; uncommitted source diff (excluding `openspec/`) SHA-256 prefix 73ca74012e4b19a5.

## E1. Codex plugin replaces the block

- **Claim**: with `codex` on PATH the installer records `ponytail@ponytail` and `~/.codex/AGENTS.md` carries no ponytail block; a second run changes nothing.
- **Command**: `HOME=$H ./install.sh codex --no-cli` twice, then `grep -c 'ponytail:ruleset:start' $H/.codex/AGENTS.md` and `HOME=$H ./tests/verify_install.sh codex`
- **Expected**: both runs exit 0; block count 0; `[plugins."ponytail@ponytail"]` enabled in `config.toml`; both ponytail checks pass.
- **Fails before**: base writes the pre-v5 block (1/1, with `ponytail:` comment wording) and no `config.toml` plugin entry.
- **Recorded**: pass. Runs 1 and 2 exit 0; block count 0; `codex plugin list` shows `ponytail@ponytail installed, enabled 5.1.0`; "codex ponytail plugin installed" and "ponytail loads once" pass.

## E2. Codex fallback and upgrade

- **Claim**: without `codex` the installer warns and appends exactly one v5.1 block; re-running once the plugin is available drops it.
- **Command**: `HOME=$H ./install.sh codex --no-cli` twice with no codex on PATH, then once with codex on PATH; `./tests/verify_install.sh codex` after each.
- **Expected**: "ponytail plugin install skipped/failed — using the AGENTS.md ruleset"; block count 1 with v5 `shortcut:` wording; after the upgrade run, block count 0 and plugin recorded; the "trust the ponytail hooks" next step prints only once the plugin is present.
- **Recorded**: pass. Fallback runs exit 0, block 1/1, plugin check soft-warns, "loads once" passes. Upgrade run: block 0, plugin recorded, both checks pass.

## E3. OpenCode plugin merge

- **Claim**: the installer merges `@dietrichgebert/ponytail` into an existing `opencode.json` without touching other keys or plugins, writes no block, and OpenCode 1.19 loads it.
- **Command**: seed `{"plugin":["opencode-foo"],"theme":"x"}`, run `HOME=$H ./install.sh opencode --no-cli` twice, `jq -c '{plugin,theme}'`, `./tests/verify_install.sh opencode`; separately `opencode debug config` with the plugin listed.
- **Expected**: `{"plugin":["opencode-foo","@dietrichgebert/ponytail"],"theme":"x"}` after both runs; block count 0; ponytail checks pass; debug config lists the six `/ponytail*` commands.
- **Recorded**: pass. Exact JSON above after run 2; block 0; both checks pass; `opencode debug config` shows the plugin with `scope: global` and commands ponytail, ponytail-review, ponytail-help, ponytail-gain, ponytail-debt, ponytail-audit (6/6).

## E4. Verifier catches double delivery

- **Claim**: a Codex install with the plugin and a block fails the hard check.
- **Command**: copy E1's `$HOME`, `append_ponytail_ruleset "$HOME/.codex/AGENTS.md"`, `./tests/verify_install.sh codex`
- **Expected**: "ponytail loads once" fails.
- **Recorded**: pass (the check reports ✗).

## E5. ZCode and untouched tools

- **Claim**: ZCode keeps exactly one block, now v5.1; nothing else in the verifier regresses.
- **Command**: `HOME=$H ./install.sh zcode --no-cli` twice, `./tests/verify_install.sh zcode`; codex verifier failure count on base vs this change with the same `--no-cli` setup.
- **Expected**: ZCode block 1/1 with `shortcut:` wording; equal failure counts.
- **Recorded**: pass. ZCode block 1/1. Codex failures 12 on base, 12 here, all "hook tool on PATH" checks for quality tools `--no-cli` does not install. Claude Code and pi were not re-run: their installers are untouched (could-not-check beyond the shared helpers' shellcheck).

## E6. Lint, anchors, change validity

- **Command**: `shellcheck -S warning -x install.sh installers/*.sh lib/*.sh tests/*.sh hooks/*.sh hooks/checks/*.sh hooks/adapters/*.sh bin/*.sh scripts/*.sh`; `shellcheck -S warning -P SCRIPTDIR -x` on each touched script; `./scripts/spec_drift_gate.sh --check`; `openspec validate ponytail-v5-native-plugins --strict`
- **Expected**: clean; all anchors healthy, `steering-assembly.ponytail-append` still resolves; change valid.
- **Recorded**: pass. Shellcheck clean (whole set and 5/5 file by file); "All anchors healthy" with `steering-assembly.ponytail-append → lib/steering.sh:51`; "Change 'ponytail-v5-native-plugins' is valid".

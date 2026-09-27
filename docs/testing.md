# Testing

[Back to README](../README.md)

## After an Install

`tests/verify_install.sh <tool>` checks that the installer put files in the
expected places and asks the CLI to report its config without logging in.
Hard checks fail the run. Live introspection that may need network or auth
(such as `claude mcp list`) only warns, so MCP wiring is asserted from the
saved config files instead.

```bash
./tests/verify_install.sh claudecode    # or codex, opencode, pi, zcode
```

## Before a Change Lands

Run the checks that match what you touched:

```bash
bash -n install.sh installers/*.sh lib/*.sh hooks/*.sh hooks/checks/*.sh machine/*.sh
./scripts/package_claude_desktop_personas.sh --check   # persona bundle is current
./scripts/spec_drift_gate.sh --check                   # anchor hygiene (needs ast-grep + yq)
./tests/test_spec_drift_gate.sh                        # drift gate self-test
./tests/test_scoped_pytest.sh                          # turn-end pytest scoping
./tests/test_pi_lan_models.sh                          # pi/omp LAN model setup (needs bun)
./tests/verify_install.sh <tool>                       # after re-running ./install.sh <tool>
```

For config-merge logic, prove idempotency: run the step twice against a
scratch `$HOME` and check the config appears exactly once.

```bash
export HOME=$(mktemp -d)
./install.sh codex --mcps-only --no-cli
./install.sh codex --mcps-only --no-cli
```

The root [AGENTS.md](../AGENTS.md) tells maintainers and coding agents which
source file owns each part of the setup and which check proves a change.

## CI

`.github/workflows/test-installers.yml` runs on pushes and pull requests that
touch the installers, `config/`, `hooks/`, `dist/`, tests, scripts or specs:

- shellcheck, plus the Claude Desktop persona bundle check.
- An Ubuntu matrix that runs `./install.sh <tool>` for all five tools, then
  `tests/verify_install.sh <tool>`. ZCode runs config-only with `--no-cli`
  because it is a macOS desktop app.
- Spec anchors: anchor hygiene, the drift gate self-test, the scoped pytest
  self-test and, on pull requests, an advisory drift pass against the base
  branch.

`security-scanning.yml` runs Gitleaks secret scanning and ShellCheck.

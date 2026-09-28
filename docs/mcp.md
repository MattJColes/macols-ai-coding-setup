# MCP Servers

[Back to README](../README.md)

The server definitions live in `config/mcp/`:

| File | Servers | Registered for |
|---|---|---|
| `servers.json` | playwright, context7, dart, gopls | every tool with MCP support |
| `aws.json` | aws-mcp, aws-iac | every tool with MCP support, opt-in |
| `brave.json` | brave-search | OpenCode and Oh My Pi, only with an API key |

The Claude Code, Codex, OpenCode, Pi (omp) and ZCode installers register them
in their own config formats, all from one resolver (`mcp_resolve` in
`lib/mcp.sh`). Plain `pi` has no MCP support. See
[Installing](installing.md#what-gets-installed-and-where) for where each tool's
config lands.

## Default Servers

`config/mcp/servers.json` holds playwright, context7, dart and gopls
(`gopls mcp`).

- Package versions are pinned (no `@latest`), so a server only changes when
  this repo bumps it.
- dart and gopls carry a `requires` key and are registered only when that
  binary is on `PATH`. Re-run the installer after installing Dart or Go tools
  to pick them up.
- Re-runs merge rather than overwrite: your own servers in `opencode.json`,
  `mcp.json` or ZCode's `config.json` survive, and only servers this repo owns
  are updated or removed.
- filesystem and puppeteer were retired. A re-run removes them when the entry
  still runs the `@modelcontextprotocol/server-*` package this repo installed,
  and leaves a server of your own with the same name alone.

To register only MCP servers for a tool:

```bash
./install.sh claudecode --mcps-only --no-cli
```

## AWS (Opt-In, Every Tool)

`config/mcp/aws.json` holds the two AWS servers. They need AWS credentials and
`uvx`, so they are off unless you ask for them:

```bash
./install.sh --aws-mcp                        # every tool; or MACOLS_AWS_MCP=1
./install.sh claudecode --mcps-only --aws-mcp # one tool
./install.sh --no-aws-mcp                     # remove them again
```

Interactive installs ask once (y/N). The answer is remembered in
`~/.config/macols/aws-mcp`, so the other installers and later re-runs follow
it. An unattended install with no answer leaves them off.

- aws-mcp: the managed
  [AWS MCP Server](https://aws.amazon.com/blogs/aws/the-aws-mcp-server-is-now-generally-available/)
  (Agent Toolkit for AWS), reached through the `mcp-proxy-for-aws` package,
  which SigV4-signs requests with your ambient AWS credentials. The endpoint
  is in `us-east-1`. Operations default to your credential chain's region.
- aws-iac: the
  [AWS IaC MCP Server](https://awslabs.github.io/mcp/servers/aws-iac-mcp-server)
  (`awslabs.aws-iac-mcp-server` via uvx): CloudFormation/CDK validation,
  documentation search and best-practice checks. Uses ambient AWS credentials.

Run `aws configure` after opting in if you have no credentials yet.

## Brave Search (OpenCode and omp)

Web search is a separate, opt-in server in `config/mcp/brave.json`:
brave-search (the official
[`@brave/brave-search-mcp-server`](https://github.com/brave/brave-search-mcp-server),
needs Node 22+). Only the OpenCode and Pi (omp) installers register it. Claude
Code, Codex and ZCode keep the default list alone, and plain `pi` has no MCP
support at all.

The OpenCode and Pi installers ask for a Brave API key
([get one here](https://brave.com/search/api/)) when they register MCP servers.
A blank answer skips it, and the server is then left out of the config rather
than registered broken. To add a key later, or on a non-interactive machine:

```bash
BRAVE_API_KEY=<key> ./install.sh opencode --mcps-only
BRAVE_API_KEY=<key> ./install.sh pi --mcps-only
```

The key is written to `~/.config/macols/brave-api-key` with mode 600 and the
config only references it through `BRAVE_API_KEY_FILE`. No secret is written
into `opencode.json` or `mcp.json`. Delete that file and re-run the installer
to remove the server again.

The key path in `config/mcp/brave.json` and `BRAVE_KEY_FILE` in
`lib/common.sh` must stay in sync.

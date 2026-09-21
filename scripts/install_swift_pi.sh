#!/usr/bin/env bash
# Standalone bootstrap: Node.js 24+ and npm must already be on PATH.
set -euo pipefail

for tool in node npm curl tar; do
    command -v "$tool" >/dev/null || { printf 'Install %s first.\n' "$tool" >&2; exit 1; }
done
node -e 'if (Number(process.versions.node.split(".")[0]) < 24) { console.error("Install Node.js 24+ first."); process.exit(1); }'

INSTALL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/swift-pi.XXXXXX")"
trap 'rm -rf "$INSTALL_DIR"' EXIT
curl --fail --location --connect-timeout 15 --max-time 120 --retry 2 \
    https://github.com/MattJColes/macols-ai-coding-setup/archive/refs/heads/main.tar.gz \
    --output "$INSTALL_DIR/source.tar.gz"
tar -xzf "$INSTALL_DIR/source.tar.gz" -C "$INSTALL_DIR"

export npm_config_fetch_timeout=60000
export npm_config_fetch_retries=2
# shellcheck source=/dev/null
source "$INSTALL_DIR/macols-ai-coding-setup-main/lib/common.sh"
ensure_cli pi
configure_pi_lan_models "$HOME/.pi/agent" "${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}"

printf '\nInstalled pi and omp with the keyless Swift Qwen provider.\n'
printf 'The machine must be able to reach http://exodus:8000/v1.\n'
printf 'Start either agent:\n  pi --provider vllm-lan --model ukisai/Swift-Qwen3.8-27B-NVFP4\n'
printf '  omp --model vllm-lan/ukisai/Swift-Qwen3.8-27B-NVFP4\n'

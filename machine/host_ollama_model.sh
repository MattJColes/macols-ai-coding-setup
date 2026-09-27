#!/usr/bin/env bash
#
# setup-ollama-persistent.sh
# Configures Ollama on Ubuntu to:
#   1. Start automatically on boot (systemd)
#   2. Keep models resident in memory indefinitely (OLLAMA_KEEP_ALIVE=-1)
#   3. Serve at the model's full context window (OLLAMA_CONTEXT_LENGTH)
#   4. Preload a specific model on boot so it's warm before first request
#   5. Expose the server ONLY over the Tailscale network (ufw on tailscale0)
#
# Usage:  sudo ./setup-ollama-persistent.sh [model-tag] [context-length]
# Example: sudo ./setup-ollama-persistent.sh qwen3.6:27b 262144
#
set -euo pipefail

MODEL="${1:-qwen3.6:27b}"
CTX="${2:-262144}"   # qwen3.6:27b native context window (262K)
OLLAMA_BIN="$(command -v ollama || echo /usr/bin/ollama)"

# --- sanity checks ---------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run with sudo (needs to write systemd units)." >&2
  exit 1
fi

if [[ ! -x "$OLLAMA_BIN" ]]; then
  echo "ERROR: ollama not found. Install it first:" >&2
  echo "  curl -fsSL https://ollama.com/install.sh | sh" >&2
  exit 1
fi

echo ">>> Using ollama binary: $OLLAMA_BIN"
echo ">>> Target model:        $MODEL"

# --- ensure base service is enabled ---------------------------------------
echo ">>> Enabling + starting ollama.service ..."
systemctl enable ollama.service
systemctl start ollama.service

# --- keep models resident forever + max context ---------------------------
echo ">>> Setting OLLAMA_KEEP_ALIVE=-1 and OLLAMA_CONTEXT_LENGTH=$CTX ..."
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment="OLLAMA_KEEP_ALIVE=-1"
Environment="OLLAMA_CONTEXT_LENGTH=$CTX"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF

# --- firewall: allow ONLY traffic arriving over Tailscale -----------------
if command -v ufw >/dev/null 2>&1; then
  echo ">>> Restricting port 11434 to the tailscale0 interface only ..."
  # Remove any prior LAN-wide rules if present (ignore errors).
  ufw delete allow 11434/tcp 2>/dev/null || true
  ufw allow in on tailscale0 to any port 11434 proto tcp || true
  ufw reload || true
else
  echo ">>> ufw not installed; skipping firewall step."
  echo "    Ensure 11434 is reachable ONLY via tailscale0 by other means."
fi

# --- pull the model now (so first boot isn't a giant download) ------------
echo ">>> Pulling $MODEL (this may take a while) ..."
if ! "$OLLAMA_BIN" pull "$MODEL"; then
  echo "WARNING: pull failed. Check the tag exists at https://ollama.com/library/qwen3" >&2
  echo "         Run 'ollama list' or fix the tag, then re-run this script." >&2
  exit 1
fi

# --- preload unit: warms the model on every boot --------------------------
echo ">>> Creating ollama-preload.service ..."
cat > /etc/systemd/system/ollama-preload.service <<EOF
[Unit]
Description=Preload $MODEL into Ollama on boot
After=ollama.service network-online.target
Requires=ollama.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/curl -fsS http://localhost:11434/api/generate -d '{"model":"$MODEL","keep_alive":-1}'
RemainAfterExit=yes
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# --- apply everything ------------------------------------------------------
echo ">>> Reloading systemd + restarting services ..."
systemctl daemon-reload
systemctl restart ollama.service
systemctl enable ollama-preload.service
systemctl start ollama-preload.service

# --- report ----------------------------------------------------------------
echo
echo ">>> Done. Status:"
systemctl --no-pager --lines=0 status ollama.service ollama-preload.service || true
echo
echo ">>> Loaded models (should show $MODEL):"
sleep 3
"$OLLAMA_BIN" ps
echo
TS_IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"
if [[ -n "$TS_IP" ]]; then
  echo ">>> Reach it over Tailscale:  curl http://$TS_IP:11434/api/tags"
else
  echo ">>> Tailscale IP not detected — once connected: curl http://<tailscale-ip>:11434/api/tags"
fi
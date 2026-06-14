#!/usr/bin/env bash
# uninstall-openclaw-jetson.sh — Remove OpenClaw (preserves Ollama and models)
set -euo pipefail

OPENCLAW_PREFIX="${OPENCLAW_PREFIX:-$HOME/.openclaw}"
REMOVE_CONFIG="${REMOVE_CONFIG:-0}"
REMOVE_MODELS="${REMOVE_MODELS:-0}"

log() { echo "[jetson-openclaw] $*"; }

export PATH="$OPENCLAW_PREFIX/bin:$OPENCLAW_PREFIX/tools/node-v22.22.0/bin:$PATH" 2>/dev/null || true

# Stop and remove systemd user service
if command -v openclaw >/dev/null 2>&1; then
  log "Stopping OpenClaw gateway..."
  openclaw gateway stop 2>/dev/null || true
  openclaw gateway uninstall 2>/dev/null || true
fi

systemctl --user disable --now openclaw-gateway.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/openclaw-gateway.service"
systemctl --user daemon-reload 2>/dev/null || true

# Remove system service if installed
if [[ -f /etc/systemd/system/openclaw-gateway.service ]]; then
  sudo systemctl disable --now openclaw-gateway.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/openclaw-gateway.service
  sudo systemctl daemon-reload
fi

# Docker cleanup
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q openclaw-gateway; then
  log "Removing Docker container..."
  docker compose -f "$(dirname "$0")/../docker-compose.jetson.yml" down 2>/dev/null || \
    docker rm -f openclaw-gateway 2>/dev/null || true
fi

# Remove OpenClaw prefix (CLI + Node + config)
if [[ "$REMOVE_CONFIG" == "1" ]]; then
  log "Removing $OPENCLAW_PREFIX (config, workspace, secrets)..."
  rm -rf "$OPENCLAW_PREFIX"
else
  log "Keeping config at $OPENCLAW_PREFIX (set REMOVE_CONFIG=1 to delete)"
  rm -rf "$OPENCLAW_PREFIX/bin" "$OPENCLAW_PREFIX/tools" 2>/dev/null || true
fi

# Optional: remove pulled Docker image
docker rmi ghcr.io/openclaw/openclaw:latest 2>/dev/null || true

# Optional: remove Ollama models
if [[ "$REMOVE_MODELS" == "1" ]]; then
  log "Removing Ollama models..."
  ollama list 2>/dev/null | awk 'NR>1 {print $1}' | xargs -r -I{} ollama rm {} 2>/dev/null || true
fi

# Cleanup compile cache
rm -rf /var/tmp/openclaw-compile-cache "$HOME/.cache/openclaw-compile" 2>/dev/null || true

log "Uninstall complete."
log "Ollama service left intact. To remove Ollama: sudo systemctl disable --now ollama && sudo rm /usr/local/bin/ollama"

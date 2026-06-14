#!/usr/bin/env bash
# monitor-openclaw-jetson.sh — Quick health check for OpenClaw + Ollama on Jetson
set -euo pipefail

export PATH="${HOME}/.openclaw/bin:${HOME}/.openclaw/tools/node-v22.22.0/bin:${PATH}"
PORT="${OPENCLAW_GATEWAY_PORT:-18789}"

echo "=== Jetson OpenClaw Monitor $(date -Is) ==="
echo "--- System ---"
free -h | head -2
if command -v tegrastats >/dev/null 2>&1; then
  timeout 2 tegrastats --interval 500 2>/dev/null | tail -1 || true
fi

echo "--- Ollama ---"
systemctl is-active ollama 2>/dev/null || echo "ollama: not systemd-managed"
curl -fsS "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1 && echo "ollama API: OK" || echo "ollama API: FAIL"
ollama ps 2>/dev/null || true

echo "--- OpenClaw Gateway ---"
systemctl --user is-active openclaw-gateway.service 2>/dev/null || echo "gateway service: inactive"
curl -fsS "http://127.0.0.1:${PORT}/healthz" 2>/dev/null && echo "healthz: OK" || echo "healthz: FAIL"
curl -fsS "http://127.0.0.1:${PORT}/readyz" 2>/dev/null | python3 -m json.tool 2>/dev/null | head -8 || true

if command -v openclaw >/dev/null 2>&1; then
  openclaw gateway status 2>/dev/null | grep -E 'Runtime|Listening|Probe' || true
fi

echo "--- Logs (last 5 lines) ---"
journalctl --user -u openclaw-gateway.service -n 5 --no-pager 2>/dev/null || \
  tail -5 /tmp/openclaw/openclaw-*.log 2>/dev/null || echo "no logs found"

#!/usr/bin/env bash
# Remove old system Ollama 0.7.0 and switch to user-space Ollama 0.30.7 on port 11434.
# Run: sudo bash scripts/uninstall-old-ollama.sh
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Run with sudo: sudo bash $0"
  exit 1
fi

REAL_USER="${SUDO_USER:-ajmalrasi}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

echo "[1/6] Stopping old Ollama service..."
systemctl stop ollama 2>/dev/null || true
systemctl disable ollama 2>/dev/null || true

echo "[2/6] Removing systemd unit..."
rm -f /etc/systemd/system/ollama.service
rm -rf /etc/systemd/system/ollama.service.d
systemctl daemon-reload

echo "[3/6] Removing old binaries and libraries..."
rm -f /usr/local/bin/ollama
rm -rf /usr/local/lib/ollama

echo "[4/6] Removing old system model store (optional, frees ~7GB+)..."
if [[ -d /usr/share/ollama/.ollama ]]; then
  du -sh /usr/share/ollama/.ollama 2>/dev/null || true
  rm -rf /usr/share/ollama/.ollama
fi
# Remove ollama system user if present and unused
if id ollama &>/dev/null; then
  userdel ollama 2>/dev/null || true
fi

echo "[5/6] Configuring user-space Ollama 0.30.7 on port 11434..."
# Update user systemd unit to standard port
cat > "$REAL_HOME/.config/systemd/user/ollama-v30.service" <<EOF
[Unit]
Description=Ollama 0.30.7 (JetPack 6)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=OLLAMA_HOST=127.0.0.1:11434
Environment=OLLAMA_MODELS=${REAL_HOME}/.ollama/models
Environment=OLLAMA_MAX_LOADED_MODELS=1
Environment=OLLAMA_NUM_PARALLEL=1
Environment=OLLAMA_KEEP_ALIVE=5m
ExecStart=${REAL_HOME}/.local/ollama/bin/ollama serve
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/systemd/user/ollama-v30.service"

echo "[6/6] Done. Old Ollama removed."
echo ""
echo "As user $REAL_USER, run:"
echo "  mkdir -p ~/.local/bin"
echo "  ln -sf ~/.local/ollama/bin/ollama ~/.local/bin/ollama"
echo "  systemctl --user daemon-reload"
echo "  systemctl --user restart ollama-v30.service"
echo "  export PATH=\"\$HOME/.openclaw/bin:\$HOME/.local/bin:\$PATH\""
echo "  openclaw config set models.providers.ollama.baseUrl \"http://127.0.0.1:11434\""
echo "  systemctl --user restart openclaw-gateway.service"
echo "  ollama --version   # should show 0.30.7"
echo "  ollama list"

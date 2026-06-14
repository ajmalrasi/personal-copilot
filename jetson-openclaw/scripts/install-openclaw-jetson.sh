#!/usr/bin/env bash
# install-openclaw-jetson.sh — Official OpenClaw native install for Jetson Orin Nano 8GB
# Tested: JetPack 6.x (L4T R36.x), aarch64, OpenClaw 2026.6.5
set -euo pipefail

OPENCLAW_PREFIX="${OPENCLAW_PREFIX:-$HOME/.openclaw}"
MODEL="${OPENCLAW_MODEL:-llama3.2:1b}"
SKIP_OLLAMA="${SKIP_OLLAMA:-0}"

log() { echo "[jetson-openclaw] $*"; }
die() { echo "[jetson-openclaw] ERROR: $*" >&2; exit 1; }

# --- Preflight ---
[[ "$(uname -m)" == "aarch64" ]] || die "This script requires ARM64 (aarch64). Found: $(uname -m)"
command -v docker >/dev/null 2>&1 || log "WARN: Docker not found (optional for native install)"

if [[ -f /etc/nv_tegra_release ]]; then
  log "Jetson detected: $(head -1 /etc/nv_tegra_release)"
else
  log "WARN: /etc/nv_tegra_release not found — continuing anyway"
fi

FREE_MB=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
[[ "$FREE_MB" -ge 1500 ]] || log "WARN: Only ${FREE_MB}MB RAM available — stop other GPU workloads before inference"

# --- Jetson performance mode (requires sudo) ---
if command -v nvpmodel >/dev/null 2>&1; then
  log "Setting max power mode (requires sudo)..."
  sudo nvpmodel -m 0 2>/dev/null || log "WARN: Could not set nvpmodel (run: sudo nvpmodel -m 0)"
  sudo jetson_clocks 2>/dev/null || true
fi

# --- Ollama ---
if [[ "$SKIP_OLLAMA" != "1" ]]; then
  if ! command -v ollama >/dev/null 2>&1; then
    log "Installing Ollama (official ARM64 installer)..."
    curl -fsSL https://ollama.com/install.sh | sh
  else
    log "Ollama already installed: $(ollama --version)"
  fi

  # Apply Jetson systemd tuning if drop-in exists
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$SCRIPT_DIR/systemd/ollama-jetson.conf" ]]; then
    sudo mkdir -p /etc/systemd/system/ollama.service.d
    sudo cp "$SCRIPT_DIR/systemd/ollama-jetson.conf" /etc/systemd/system/ollama.service.d/jetson.conf
    sudo systemctl daemon-reload
    sudo systemctl enable --now ollama
  fi

  log "Pulling model: $MODEL"
  ollama pull "$MODEL"
fi

# --- OpenClaw (official install-cli.sh) ---
log "Installing OpenClaw via official install-cli.sh..."
curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install-cli.sh | bash -s -- --prefix "$OPENCLAW_PREFIX"

export PATH="$OPENCLAW_PREFIX/bin:$OPENCLAW_PREFIX/tools/node-v22.22.0/bin:$PATH"
export OLLAMA_API_KEY="ollama-local"

# --- Environment file ---
ENV_FILE="$OPENCLAW_PREFIX/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cp "$SCRIPT_DIR/.env.example" "$ENV_FILE"
  TOKEN=$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p)
  sed -i "s/CHANGE_ME_generate_with_openssl_rand_hex_32/$TOKEN/" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  log "Created $ENV_FILE with generated gateway token"
fi

# shellcheck disable=SC1090
set -a && source "$ENV_FILE" && set +a

# --- Compile cache dir ---
sudo mkdir -p /var/tmp/openclaw-compile-cache 2>/dev/null || mkdir -p "$HOME/.cache/openclaw-compile"
export NODE_COMPILE_CACHE="${NODE_COMPILE_CACHE:-/var/tmp/openclaw-compile-cache}"

# --- Onboarding (Ollama local) ---
log "Configuring OpenClaw for Ollama..."
openclaw onboard --non-interactive \
  --auth-choice ollama \
  --custom-base-url "http://127.0.0.1:11434" \
  --custom-model-id "$MODEL" \
  --accept-risk \
  --skip-health || true

openclaw config set agents.defaults.memorySearch.enabled false
openclaw config set agents.defaults.model.primary "ollama/$MODEL"

# --- Systemd gateway ---
log "Installing systemd user service..."
openclaw gateway install --force
systemctl --user daemon-reload
systemctl --user enable --now openclaw-gateway.service

log "Enabling user lingering for boot persistence (requires sudo)..."
sudo loginctl enable-linger "$USER" 2>/dev/null || log "WARN: Run manually: sudo loginctl enable-linger $USER"

# --- Verify ---
sleep 5
openclaw --version
curl -fsS "http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}/healthz" && log "Gateway healthz: OK"
openclaw gateway status

log "Install complete."
log "Dashboard: http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}/"
log "Add to shell: export PATH=\"$OPENCLAW_PREFIX/bin:\$PATH\""

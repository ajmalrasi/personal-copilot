# personal-copilot

OpenClaw + Ollama deployment for **NVIDIA Jetson Orin Nano 8GB** (JetPack 6.x, ARM64).

Runs the official [OpenClaw](https://github.com/openclaw/openclaw) gateway with local [Ollama](https://ollama.com) inference and GPU acceleration on unified memory.

## Requirements

| Item | Notes |
|------|-------|
| Hardware | Jetson Orin Nano 8GB (aarch64) |
| OS | JetPack 6.x (L4T R36.x) |
| RAM | 8 GB unified memory — tight for 4B models |
| Storage | NVMe SSD recommended for models |
| Network | LAN access optional (see below) |

## Quick start

```bash
git clone https://github.com/ajmalrasi/personal-copilot.git
cd personal-copilot/jetson-openclaw
chmod +x scripts/*.sh
./scripts/install-openclaw-jetson.sh
```

Or step-by-step:

```bash
# 1. Ollama (JetPack 6 CUDA build)
curl -fsSL https://ollama.com/install.sh | sh
sudo systemctl enable --now ollama

# 2. Pull model
ollama pull qwen3.5:4b

# 3. OpenClaw
curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install-cli.sh | bash -s -- --prefix ~/.openclaw
export PATH="$HOME/.openclaw/bin:$PATH"
export OLLAMA_API_KEY=ollama-local

openclaw onboard --non-interactive \
  --auth-choice ollama \
  --custom-base-url "http://127.0.0.1:11434" \
  --custom-model-id "qwen3.5:4b" \
  --accept-risk

openclaw config set agents.defaults.memorySearch.enabled false
openclaw config set gateway.bind lan
openclaw gateway install
sudo loginctl enable-linger $USER
systemctl --user enable --now openclaw-gateway.service
```

## Default model: Qwen 3.5 4B

Recommended for Jetson 8GB when other GPU workloads are stopped:

```bash
ollama pull qwen3.5:4b
openclaw config set agents.defaults.model.primary "ollama/qwen3.5:4b"
systemctl --user restart openclaw-gateway.service
```

| Model | Size | Notes |
|-------|------|-------|
| `qwen3.5:4b` | ~3.4 GB | Default — best quality on 8GB |
| `llama3.2:1b` | ~1.3 GB | Fallback if GPU OOM |
| `qwen2.5:1.5b` | ~1.0 GB | Good tool-calling, lighter |

Ollama integration (critical):

- Use native API: `http://127.0.0.1:11434` — **no `/v1` suffix**
- Set `api: "ollama"` in config for reliable tool calling
- Set `OLLAMA_API_KEY=ollama-local` for loopback hosts

## LAN access

By default OpenClaw binds to loopback. To reach the Control UI from other devices:

```bash
openclaw config set gateway.bind lan
openclaw config set --batch-json '[{"path":"gateway.controlUi.allowedOrigins","value":["http://localhost:18789","http://127.0.0.1:18789","http://YOUR_JETSON_IP:18789"]}]'
openclaw gateway install --force
systemctl --user restart openclaw-gateway.service
```

Then open `http://YOUR_JETSON_IP:18789/` and paste your gateway token (Settings).

Get token:

```bash
openclaw config get gateway.auth.token
```

## Repository layout

```
jetson-openclaw/
├── .env.example              # Secrets template (copy to ~/.openclaw/.env)
├── config/openclaw.jetson.json
├── docker-compose.jetson.yml # Optional Docker deployment
├── scripts/
│   ├── install-openclaw-jetson.sh
│   ├── monitor-openclaw-jetson.sh
│   ├── uninstall-old-ollama.sh
│   └── uninstall-openclaw-jetson.sh
└── systemd/
    ├── ollama-jetson.conf
    └── openclaw-gateway.system.service
```

## Verify

```bash
curl http://127.0.0.1:18789/healthz          # OpenClaw
curl http://127.0.0.1:11434/api/tags         # Ollama
openclaw gateway status
ollama ps
./scripts/monitor-openclaw-jetson.sh
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `cudaMalloc failed: out of memory` | Stop other GPU apps; use `llama3.2:1b`; set `OLLAMA_MAX_LOADED_MODELS=1` |
| `unable to allocate CUDA0 buffer` | Reboot; stop competing services; remove old Ollama (`scripts/uninstall-old-ollama.sh`) |
| Can't reach UI from LAN | Set `gateway.bind` to `lan`; add your IP to `allowedOrigins` |
| Gateway stops after logout | `sudo loginctl enable-linger $USER` |
| `qwen3.5:4b` pull fails on old Ollama | Upgrade: `curl -fsSL https://ollama.com/install.sh \| sh` (needs 0.30+) |
| Tool calling outputs raw JSON | Use native Ollama URL without `/v1`, set `api: "ollama"` |

## Upgrade / remove old Ollama

If you have Ollama 0.7.x on port 11434 alongside a newer install:

```bash
sudo bash scripts/uninstall-old-ollama.sh
systemctl --user restart ollama-v30.service   # if using user-space Ollama
```

Full uninstall:

```bash
./scripts/uninstall-openclaw-jetson.sh
REMOVE_CONFIG=1 ./scripts/uninstall-openclaw-jetson.sh   # also delete ~/.openclaw
```

## Docker (optional)

Use pre-built ARM64 image only — do not build locally on 8GB:

```bash
export OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:latest
docker compose -f docker-compose.jetson.yml up -d
```

Host Ollama must be reachable at `host.docker.internal:11434`.

## Links

- [OpenClaw docs](https://docs.openclaw.ai)
- [OpenClaw Ollama provider](https://docs.openclaw.ai/providers/ollama)
- [Ollama on Jetson (NVIDIA)](https://www.jetson-ai-lab.com/tutorials/ollama/)

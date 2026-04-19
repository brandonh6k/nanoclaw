#!/usr/bin/env bash
# Bootstraps OneCLI state inside the sandbox after a restart.
# Runs OneCLI compose, waits for health, creates CLI session + Anthropic secret.
set -euo pipefail

COMPOSE_DIR="/Users/brandon.hunt/nanoclaw-sandbox/data/onecli"
GATEWAY_URL="http://localhost:10254"
ENV_FILE="/Users/brandon.hunt/nanoclaw-sandbox/.env"
COMPOSE_TEMPLATE="/Users/brandon.hunt/nanoclaw-sandbox/scripts/onecli-compose.yml"

# Sync the tracked compose template into the runtime location. COMPOSE_DIR
# lives under data/ (gitignored) because that's what we bind-mount as the
# app data volume; the template is the canonical version kept in git.
mkdir -p "$COMPOSE_DIR"
if [[ -f "$COMPOSE_TEMPLATE" ]] && ! cmp -s "$COMPOSE_TEMPLATE" "$COMPOSE_DIR/docker-compose.yml" 2>/dev/null; then
  cp "$COMPOSE_TEMPLATE" "$COMPOSE_DIR/docker-compose.yml"
  echo "[onecli] refreshed compose file from template"
fi

export PATH="$HOME/.local/bin:$PATH"
export ONECLI_BIND_HOST=0.0.0.0

# The compose file mounts the Docker Sandbox's MITM CA cert into the OneCLI
# container so outbound HTTPS (to api.anthropic.com) can terminate through
# the sandbox proxy. Copy it into the workspace (DinD requires workspace
# paths for bind mounts). Idempotent — only writes if missing or stale.
SYS_CA="/usr/local/share/ca-certificates/proxy-ca.crt"
WORKSPACE_CA="$COMPOSE_DIR/proxy-ca.crt"
if [[ -f "$SYS_CA" ]]; then
  if ! cmp -s "$SYS_CA" "$WORKSPACE_CA" 2>/dev/null; then
    cp "$SYS_CA" "$WORKSPACE_CA"
    echo "[onecli] refreshed proxy CA cert in workspace"
  fi
fi

echo "[onecli] starting compose stack..."
(cd "$COMPOSE_DIR" && docker compose up -d >/dev/null)

echo "[onecli] waiting for gateway health..."
for i in $(seq 1 30); do
  if curl -sf "$GATEWAY_URL/api/health" >/dev/null; then
    break
  fi
  sleep 1
done
curl -sf "$GATEWAY_URL/api/health" >/dev/null || { echo "[onecli] gateway never came up"; exit 1; }

echo "[onecli] fetching admin API key from local-mode gateway..."
KEY=$(curl -sf "$GATEWAY_URL/api/user/api-key" | sed -n 's/.*"apiKey":"\([^"]*\)".*/\1/p')
if [[ -z "$KEY" ]]; then
  echo "[onecli] could not fetch API key"; exit 1
fi
onecli auth login --api-key "$KEY" >/dev/null

ANTHROPIC_KEY=$(grep '^ANTHROPIC_API_KEY=' "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)
if [[ -z "$ANTHROPIC_KEY" ]]; then
  echo "[onecli] no ANTHROPIC_API_KEY in .env — skipping secret creation"
  exit 0
fi

if onecli secrets list 2>/dev/null | grep -q '"type": "anthropic"'; then
  echo "[onecli] Anthropic secret already present"
else
  echo "[onecli] creating Anthropic secret..."
  onecli secrets create \
    --name Anthropic \
    --type anthropic \
    --value "$ANTHROPIC_KEY" \
    --host-pattern api.anthropic.com >/dev/null
  echo "[onecli] done"
fi

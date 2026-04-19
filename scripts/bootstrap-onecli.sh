#!/usr/bin/env bash
# Bootstraps OneCLI state inside the sandbox after a restart.
# Runs OneCLI compose, waits for health, creates CLI session + Anthropic secret.
set -euo pipefail

COMPOSE_DIR="/Users/brandon.hunt/nanoclaw-sandbox/data/onecli"
GATEWAY_URL="http://localhost:10254"
ENV_FILE="/Users/brandon.hunt/nanoclaw-sandbox/.env"

export PATH="$HOME/.local/bin:$PATH"
export ONECLI_BIND_HOST=0.0.0.0

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

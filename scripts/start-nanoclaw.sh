#!/usr/bin/env bash
# Foreground launcher for NanoClaw inside the Docker Sandbox.
#
# Called by launchd (via `docker sandbox exec`) on macOS login, and whenever
# the previous run exits (KeepAlive). Runs NanoClaw in the foreground so
# launchd supervises the actual process.
set -uo pipefail
cd /Users/brandon.hunt/nanoclaw-sandbox
mkdir -p logs

log() { echo "[$(date -Iseconds)] $*" >> logs/supervisor.log; }

# Kill any previously-started instance so launchd owns the lifecycle.
# Without this, a manual `node dist/index.js &` would orphan itself and
# launchd would see its own exec exit 0 and stop supervising.
if pgrep -f "node dist/index.js" >/dev/null; then
  log "killing existing node dist/index.js processes"
  pkill -f "node dist/index.js" || true
  sleep 1
  pkill -9 -f "node dist/index.js" 2>/dev/null || true
fi

log "starting node dist/index.js"
exec node dist/index.js >> logs/nanoclaw.log 2>> logs/nanoclaw.error.log

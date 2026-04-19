#!/usr/bin/env bash
# Foreground launcher for NanoClaw inside the Docker Sandbox.
#
# Called by launchd (via `docker sandbox exec`) on macOS login, and whenever
# the previous run exits (KeepAlive). Idempotent: if NanoClaw is already
# running this script exits quickly so launchd backs off.
#
# Also re-runs bootstrap-onecli.sh so OneCLI's tmpfs state is re-hydrated
# every time the sandbox VM comes back up.
set -uo pipefail
cd /Users/brandon.hunt/nanoclaw-sandbox
mkdir -p logs

log() { echo "[$(date -Iseconds)] $*" >> logs/supervisor.log; }

# 1. Ensure OneCLI is up with an Anthropic secret.
log "running bootstrap-onecli"
if ! ./scripts/bootstrap-onecli.sh >> logs/supervisor.log 2>&1; then
  log "bootstrap-onecli failed — exiting so launchd retries after ThrottleInterval"
  exit 1
fi

# 2. Kill any previously-started instance so launchd owns the lifecycle.
#    Without this, a manual `node dist/index.js &` would orphan itself and
#    launchd would see its own exec exit 0 and stop supervising.
if pgrep -f "node dist/index.js" >/dev/null; then
  log "killing existing node dist/index.js processes"
  pkill -f "node dist/index.js" || true
  sleep 1
  pkill -9 -f "node dist/index.js" 2>/dev/null || true
fi

# 3. Run in foreground. launchd's KeepAlive restarts us if we exit non-zero.
log "starting node dist/index.js"
exec node dist/index.js >> logs/nanoclaw.log 2>> logs/nanoclaw.error.log
